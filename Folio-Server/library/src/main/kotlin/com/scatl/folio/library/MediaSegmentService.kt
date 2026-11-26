package com.scatl.folio.library

import com.scatl.folio.auth.LibraryAccessService
import com.scatl.folio.catalog.ExternalProvider
import com.scatl.folio.catalog.OwnerType
import com.scatl.folio.catalog.WorkKind
import com.scatl.folio.dto.MediaSegmentView
import com.scatl.folio.dto.MediaSegmentsView
import com.scatl.folio.entity.LibraryFile
import com.scatl.folio.entity.MatchStatus
import com.scatl.folio.entity.MediaSegmentCache
import com.scatl.folio.provider.RequestPacer
import com.scatl.folio.repository.ExternalIdRepository
import com.scatl.folio.repository.LibraryFileRepository
import com.scatl.folio.repository.MediaSegmentCacheRepository
import com.scatl.folio.repository.SeasonRepository
import org.slf4j.LoggerFactory
import org.springframework.boot.json.JsonParserFactory
import org.springframework.dao.DataIntegrityViolationException
import org.springframework.http.HttpHeaders
import org.springframework.http.client.JdkClientHttpRequestFactory
import org.springframework.stereotype.Service
import org.springframework.web.client.RestClient
import org.springframework.web.server.ResponseStatusException
import tools.jackson.databind.json.JsonMapper
import java.net.http.HttpClient
import java.time.Duration
import java.time.Instant
import java.util.concurrent.ConcurrentHashMap

@Service
class MediaSegmentService(
    private val libraryAccess: LibraryAccessService,
    private val files: LibraryFileRepository,
    private val seasons: SeasonRepository,
    private val externalIds: ExternalIdRepository,
    private val cache: MediaSegmentCacheRepository,
    private val json: JsonMapper,
) {
    private val log = LoggerFactory.getLogger(javaClass)
    private val pacer = RequestPacer(2.0)
    private val theIntroDb = client("https://api.theintrodb.org/v4")
    private val introDb = client("https://api.introdb.app")
    private val locks = ConcurrentHashMap<String, Any>()

    fun forFile(fileId: Long): MediaSegmentsView {
        libraryAccess.requireFileReadable(fileId)
        return try {
            load(fileId)
        } catch (ex: ResponseStatusException) {
            throw ex
        } catch (ex: Exception) {
            log.warn("片头片尾查询失败 fileId={}: {}", fileId, ex.message)
            MediaSegmentsView(emptyList())
        }
    }

    private fun load(fileId: Long): MediaSegmentsView {
        val file = files.findWithMatchById(fileId).orElse(null) ?: return MediaSegmentsView(emptyList())
        val located = locate(file) ?: return MediaSegmentsView(emptyList())
        val lock = locks.computeIfAbsent(located.cacheKey) { Any() }
        synchronized(lock) {
            val cached = fresh(located)
            if (cached != null) return cached
            val fetched = fetch(located)
            if (fetched.save) remember(located, fetched.segments)
            return view(fetched.segments)
        }
    }

    private fun locate(file: LibraryFile): Lookup? {
        if (file.matchStatus != MatchStatus.matched) return null
        val work = file.work ?: return null
        val workId = work.id ?: return null
        val series = work.kind == WorkKind.series
        val season: Int?
        val episode: Int?
        if (series) {
            val row = file.episode
            if (row != null) {
                val seasonRow = seasons.findById(row.seasonId).orElse(null) ?: return null
                season = seasonRow.seasonNumber
                episode = row.episodeNumber
            } else if (file.parsedSeason != null && file.parsedEpisode != null) {
                season = file.parsedSeason
                episode = file.parsedEpisode
            } else {
                return null
            }
        } else {
            season = null
            episode = null
        }
        val ids = externalIds.findByOwnerTypeAndOwnerIdOrderByProviderAsc(OwnerType.work, workId)
        val tmdbId = ids.firstOrNull { it.provider == ExternalProvider.tmdb }?.externalId?.toLongOrNull()
        val imdbId = ids.firstOrNull { it.provider == ExternalProvider.imdb }?.externalId
            ?.trim()
            ?.takeIf { IMDB.matches(it) }
        if (tmdbId == null && imdbId == null) return null
        return Lookup(
            workId = workId,
            seasonNumber = season ?: -1,
            episodeNumber = episode ?: -1,
            season = season,
            episode = episode,
            movie = !series,
            tmdbId = tmdbId,
            imdbId = imdbId,
            durationMs = file.durationMs?.takeIf { it > 0 },
            durationBucket = MediaSegmentLogic.durationBucket(file.durationMs),
        )
    }

    private fun fresh(lookup: Lookup): MediaSegmentsView? {
        val row = cache.findByWorkIdAndSeasonNumberAndEpisodeNumberAndDurationBucket(
            lookup.workId,
            lookup.seasonNumber,
            lookup.episodeNumber,
            lookup.durationBucket,
        ) ?: return null
        val age = Duration.between(row.fetchedAt, Instant.now())
        val limit = if (row.emptyResult) Duration.ofDays(1) else Duration.ofDays(30)
        if (age.isNegative || age > limit) return null
        return view(decode(row.payload))
    }

    private fun fetch(lookup: Lookup): Fetch {
        val primary = readTheIntroDb(lookup)
        val needFallback = lookup.imdbId != null && (
            !primary.save ||
                primary.segments.none { it.kind == MediaSegmentLogic.CREDITS } ||
                primary.segments.none { it.kind == MediaSegmentLogic.INTRO && !lookup.movie }
            )
        val extra = if (needFallback) readIntroDb(lookup) else Fetch(emptyList(), save = true)
        val merged = MediaSegmentLogic.merge(primary.segments, extra.segments)
        val save = when {
            merged.isNotEmpty() -> primary.save || extra.save
            primary.save && extra.save -> true
            else -> false
        }
        if (merged.isNotEmpty() || save) {
            log.info(
                "片头片尾已获取 workId={} season={} episode={} count={}",
                lookup.workId,
                lookup.season,
                lookup.episode,
                merged.size,
            )
        }
        return Fetch(merged, save)
    }

    private fun readTheIntroDb(lookup: Lookup): Fetch {
        val query = MediaSegmentLogic.theIntroDbQuery(
            movie = lookup.movie,
            tmdbId = lookup.tmdbId,
            imdbId = lookup.imdbId,
            season = lookup.season,
            episode = lookup.episode,
            durationMs = lookup.durationMs,
        ) ?: return Fetch(emptyList(), save = true)
        return read(theIntroDb, "/media", query, MediaSegmentLogic::fromTheIntroDb)
    }

    private fun readIntroDb(lookup: Lookup): Fetch {
        val imdbId = lookup.imdbId ?: return Fetch(emptyList(), save = true)
        val query = linkedMapOf<String, Any?>("imdb_id" to imdbId)
        if (lookup.movie) {
            query["is_movie"] = true
        } else if (lookup.season != null && lookup.episode != null) {
            query["season"] = lookup.season
            query["episode"] = lookup.episode
        } else {
            return Fetch(emptyList(), save = true)
        }
        return read(introDb, "/segments", query, MediaSegmentLogic::fromIntroDb)
    }

    private fun read(
        client: RestClient,
        path: String,
        query: Map<String, Any?>,
        parse: (Map<String, Any?>) -> List<MediaSegment>,
    ): Fetch {
        val remote = try {
            pacer.acquire()
            client.get()
                .uri { builder ->
                    var next = builder.path(path)
                    query.forEach { (key, value) ->
                        if (value != null) next = next.queryParam(key, value)
                    }
                    next.build()
                }
                .header(HttpHeaders.USER_AGENT, "Folio")
                .header(HttpHeaders.ACCEPT, "application/json")
                .exchange { _, response ->
                    val body = try {
                        response.bodyTo(String::class.java)
                    } catch (_: Exception) {
                        null
                    }
                    response.statusCode.value() to body
                }
        } catch (ex: Exception) {
            log.info("片头片尾来源不可用 path={}: {}", path, ex.message)
            return Fetch(emptyList(), save = false)
        }
        val (status, body) = remote
        if (status == 404) return Fetch(emptyList(), save = true)
        if (status != 200 || body.isNullOrBlank()) {
            log.info("片头片尾来源返回 {} path={} body={}", status, path, body?.take(160))
            return Fetch(emptyList(), save = false)
        }
        val root = try {
            @Suppress("UNCHECKED_CAST")
            JsonParserFactory.getJsonParser().parseMap(body) as Map<String, Any?>
        } catch (ex: RuntimeException) {
            log.info("片头片尾响应无法解析 path={}: {}", path, ex.message)
            return Fetch(emptyList(), save = false)
        }
        return try {
            Fetch(parse(root), save = true)
        } catch (ex: RuntimeException) {
            log.info("片头片尾字段无法解析 path={}: {}", path, ex.message)
            Fetch(emptyList(), save = false)
        }
    }

    private fun remember(lookup: Lookup, segments: List<MediaSegment>) {
        val row = cache.findByWorkIdAndSeasonNumberAndEpisodeNumberAndDurationBucket(
            lookup.workId,
            lookup.seasonNumber,
            lookup.episodeNumber,
            lookup.durationBucket,
        ) ?: MediaSegmentCache().apply {
            workId = lookup.workId
            seasonNumber = lookup.seasonNumber
            episodeNumber = lookup.episodeNumber
            durationBucket = lookup.durationBucket
        }
        row.payload = encode(segments)
        row.emptyResult = segments.isEmpty()
        row.fetchedAt = Instant.now()
        try {
            cache.save(row)
        } catch (_: DataIntegrityViolationException) {
            val winner = cache.findByWorkIdAndSeasonNumberAndEpisodeNumberAndDurationBucket(
                lookup.workId,
                lookup.seasonNumber,
                lookup.episodeNumber,
                lookup.durationBucket,
            ) ?: return
            winner.payload = row.payload
            winner.emptyResult = row.emptyResult
            winner.fetchedAt = row.fetchedAt
            cache.save(winner)
        }
    }

    private fun encode(segments: List<MediaSegment>): String {
        val rows = segments.map {
            mapOf("kind" to it.kind, "startMs" to it.startMs, "endMs" to it.endMs)
        }
        return json.writeValueAsString(rows)
    }

    private fun decode(payload: String): List<MediaSegment> {
        if (payload.isBlank()) return emptyList()
        return try {
            val rows = json.readValue(payload, List::class.java)
            rows.mapNotNull { item ->
                val row = item as? Map<*, *> ?: return@mapNotNull null
                val kind = row["kind"]?.toString()?.trim().orEmpty()
                val start = (row["startMs"] as? Number)?.toLong() ?: return@mapNotNull null
                if (kind.isEmpty() || start < 0) return@mapNotNull null
                MediaSegment(kind, start, (row["endMs"] as? Number)?.toLong())
            }
        } catch (ex: Exception) {
            log.info("片头片尾缓存无法解析: {}", ex.message)
            emptyList()
        }
    }

    private fun view(segments: List<MediaSegment>) = MediaSegmentsView(
        segments.map { MediaSegmentView(it.kind, it.startMs, it.endMs) },
    )

    private fun client(baseUrl: String): RestClient {
        val timeout = Duration.ofSeconds(8)
        val http = HttpClient.newBuilder().connectTimeout(timeout).build()
        val factory = JdkClientHttpRequestFactory(http).apply { setReadTimeout(timeout) }
        return RestClient.builder().baseUrl(baseUrl).requestFactory(factory).build()
    }

    private data class Lookup(
        val workId: Long,
        val seasonNumber: Int,
        val episodeNumber: Int,
        val season: Int?,
        val episode: Int?,
        val movie: Boolean,
        val tmdbId: Long?,
        val imdbId: String?,
        val durationMs: Long?,
        val durationBucket: Int,
    ) {
        val cacheKey = "$workId:$seasonNumber:$episodeNumber:$durationBucket"
    }

    private data class Fetch(val segments: List<MediaSegment>, val save: Boolean)

    private companion object {
        val IMDB = Regex("^tt\\d+$")
    }
}
