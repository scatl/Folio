package com.scatl.folio.library

import com.scatl.folio.auth.LibraryAccessService
import com.scatl.folio.catalog.CatalogService
import com.scatl.folio.catalog.ExternalProvider
import com.scatl.folio.dto.RankedCandidate
import com.scatl.folio.entity.LibraryFile
import com.scatl.folio.entity.MatchStatus
import com.scatl.folio.parse.TitleScore
import com.scatl.folio.provider.SearchCandidate
import com.scatl.folio.provider.TmdbClient
import com.scatl.folio.provider.TvdbClient
import com.scatl.folio.repository.LibraryFileRepository
import com.scatl.folio.settings.FolioSettings
import com.scatl.folio.util.TmdbImageUrls
import org.slf4j.LoggerFactory
import org.springframework.beans.factory.annotation.Qualifier
import org.springframework.data.domain.Page
import org.springframework.data.domain.PageRequest
import org.springframework.data.domain.Sort
import org.springframework.http.HttpStatus
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import org.springframework.web.server.ResponseStatusException
import java.util.concurrent.Executor

@Service
open class ManualMatchService(
    private val files: LibraryFileRepository,
    private val matchState: FileMatchService,
    private val tmdb: TmdbClient,
    private val tvdb: TvdbClient,
    private val catalog: CatalogService,
    private val seriesIngest: SeriesEpisodeIngest,
    private val aliases: SeriesTitleAliasService,
    private val omdbRatings: OmdbRatingService,
    private val fingerprints: FileFingerprintService,
    private val events: ScrapeEventPublisher,
    private val libraryAccess: LibraryAccessService,
    private val appSettings: FolioSettings,
    @Qualifier("manualMatchExecutor") private val matchExecutor: Executor,
) {
    private val log = LoggerFactory.getLogger(javaClass)

    @Transactional(readOnly = true)
    open fun listForReview(page: Int, size: Int): Page<LibraryFile> {
        val pageable = PageRequest.of(page.coerceAtLeast(0), size.coerceIn(1, 100), Sort.by(Sort.Direction.DESC, "id"))
        return files.findByMatchStatus(MatchStatus.needs_review, pageable)
    }

    @Transactional(readOnly = true)
    open fun fileForMatch(id: Long): LibraryFile {
        val file = files.findById(id).orElseThrow { ResponseStatusException(HttpStatus.NOT_FOUND, "文件不存在") }
        if (
            file.matchStatus != MatchStatus.needs_review &&
            file.matchStatus != MatchStatus.failed &&
            file.matchStatus != MatchStatus.matched
        ) {
            throw ResponseStatusException(HttpStatus.BAD_REQUEST, "当前状态不可人工匹配")
        }
        return file
    }

    fun searchCandidates(fileId: Long, query: String?, kind: String?, year: Int? = null): List<RankedCandidate> {
        if (!tmdb.configured()) {
            throw ResponseStatusException(HttpStatus.BAD_REQUEST, "TMDB API Key 未配置")
        }
        val file = fileForMatch(fileId)
        val q = query?.trim()?.takeIf { it.isNotEmpty() } ?: file.parsedTitle?.trim().orEmpty()
        if (q.isEmpty()) {
            throw ResponseStatusException(HttpStatus.BAD_REQUEST, "请提供搜索关键词")
        }
        val resolvedKind = when (kind?.trim()?.lowercase()) {
            "movie" -> "movie"
            "series", "tv" -> "series"
            else -> if (file.parsedSeason != null) "series" else "movie"
        }
        // 留空时：电影用文件名年份；剧集不按年份过滤，避免把季发行年当成首播年。
        val resolvedYear = year ?: if (resolvedKind == "series") null else file.parsedYear
        log.info("人工匹配搜索 fileId={} kind={} query={} year={}", fileId, resolvedKind, q, resolvedYear)
        val hits = if (resolvedKind == "series") {
            tmdb.searchSeriesCandidates(q, resolvedYear)
        } else {
            tmdb.searchMovieCandidates(q, resolvedYear)
        }
        return hits.map { it.toRanked(q, resolvedYear) }
            .sortedByDescending { it.score }
    }

    fun confirm(
        fileId: Long,
        kind: String,
        tmdbId: Long,
        year: Int? = null,
        season: Int? = null,
        episode: Int? = null,
        scope: String? = null,
    ) {
        if (!tmdb.configured()) {
            throw ResponseStatusException(HttpStatus.BAD_REQUEST, "TMDB API Key 未配置")
        }
        val file = fileForMatch(fileId)
        val previousWorkId = files.findWorkIdById(fileId)
        val resolvedKind = when (kind.trim().lowercase()) {
            "movie" -> "movie"
            "series", "tv" -> "series"
            else -> throw ResponseStatusException(HttpStatus.BAD_REQUEST, "kind 无效，可选 movie / series")
        }
        val wholeWork = when (scope?.trim()?.lowercase()) {
            null, "", "file" -> false
            "work" -> true
            else -> throw ResponseStatusException(HttpStatus.BAD_REQUEST, "scope 无效，可选 file / work")
        }
        if (wholeWork && resolvedKind == "series") {
            confirmWholeSeries(fileId, tmdbId, year ?: file.parsedYear, file.parsedTitle)
            return
        }
        val resolvedSeason = season ?: file.parsedSeason
        val resolvedEpisode = episode ?: file.parsedEpisode
        val parsedTitle = file.parsedTitle
        val parsedYear = year ?: file.parsedYear
        log.info(
            "人工匹配已入队 fileId={} kind={} tmdbId={} season={} episode={}",
            fileId,
            resolvedKind,
            tmdbId,
            resolvedSeason,
            resolvedEpisode,
        )
        matchState.beginManualMatch(fileId)
        matchExecutor.execute {
            scrapeManualMatch(
                fileId,
                resolvedKind,
                tmdbId,
                resolvedSeason,
                resolvedEpisode,
                parsedTitle,
                parsedYear,
                previousWorkId,
            )
        }
    }

    /** 整部剧改挂：每个视频用自己文件名里的季、集，不把所有文件挂到同一集。 */
    private fun confirmWholeSeries(anchorId: Long, tmdbId: Long, parsedYear: Int?, parsedTitle: String?) {
        val previousWorkId = files.findWorkIdById(anchorId)
            ?: throw ResponseStatusException(HttpStatus.BAD_REQUEST, "这个文件还没有挂到作品，无法整部改挂")
        val targets = files.findByWork_IdOrderByIdAsc(previousWorkId).map { file ->
            SeriesFileTarget(
                id = requireNotNull(file.id),
                season = file.parsedSeason,
                episode = file.parsedEpisode,
            )
        }
        if (targets.isEmpty()) {
            throw ResponseStatusException(HttpStatus.BAD_REQUEST, "这部剧没有可改挂的视频")
        }
        for (target in targets) {
            libraryAccess.requireFileWritable(target.id)
        }
        val ready = targets.filter { it.season != null && it.episode != null }
        val skipped = targets.filter { it.season == null || it.episode == null }
        if (ready.isEmpty()) {
            throw ResponseStatusException(HttpStatus.BAD_REQUEST, "这些文件名里都没有季或集，无法整部改挂")
        }
        for (target in skipped) {
            matchState.markReview(target.id, 0.0, "整部改挂时跳过：文件名里没有季或集")
        }
        for (target in ready) {
            matchState.beginManualMatch(target.id)
        }
        log.info("整部改挂已入队 workId={} files={} skipped={}", previousWorkId, ready.size, skipped.size)
        matchExecutor.execute {
            scrapeWholeSeries(previousWorkId, tmdbId, parsedTitle, parsedYear, ready)
        }
    }

    private fun scrapeManualMatch(
        fileId: Long,
        resolvedKind: String,
        tmdbId: Long,
        season: Int?,
        episode: Int?,
        parsedTitle: String?,
        parsedYear: Int?,
        previousWorkId: Long?,
    ) {
        try {
            val knownSeason = season
            val knownEpisode = episode
            if (resolvedKind != "movie" && knownSeason != null && knownEpisode != null) {
                matchSeriesEpisode(
                    fileId,
                    tmdbId,
                    knownSeason,
                    knownEpisode,
                    parsedTitle,
                    parsedYear,
                    previousWorkId,
                )
                return
            }
            val work = if (resolvedKind == "movie") {
                tmdb.movie(tmdbId)
            } else {
                tmdb.series(tmdbId, season)
            }
            val saved = catalog.save(work, season, episode)
            if (tvdb.configured()) {
                try {
                    catalog.applySupplement(
                        saved.workId,
                        tvdb.enrich(work.kind, parsedTitle ?: work.originalTitle, parsedYear, work.originalTitle, season),
                    )
                } catch (ex: RuntimeException) {
                    log.warn("人工匹配 TVDB 补充失败 fileId={} reason={}", fileId, ex.message)
                }
            }
            supplementRatings(saved.workId)
            matchState.markMatched(fileId, saved.workId, saved.episodeId, 1.0, "人工匹配")
            fingerprints.remember(fileId, saved.workId, saved.episodeId)
            if (resolvedKind != "movie") {
                aliases.remember(parsedTitle, parsedYear, saved.workId, tmdbId)
            }
            if (previousWorkId != null && previousWorkId != saved.workId && files.findByWork_IdOrderByIdAsc(previousWorkId).isEmpty()) {
                events.notifyWorkRemovedAfterCommit(previousWorkId)
            }
            log.info("人工匹配完成 fileId={} workId={} episodeId={}", fileId, saved.workId, saved.episodeId)
        } catch (ex: Exception) {
            log.warn("人工匹配失败 fileId={} reason={}", fileId, ex.message)
            matchState.markFailed(fileId, ex.message ?: "人工匹配失败")
        }
    }

    /** 人工匹配电视剧：只改挂当前文件，不连带同名其它集。 */
    private fun matchSeriesEpisode(
        fileId: Long,
        tmdbId: Long,
        season: Int,
        episode: Int,
        parsedTitle: String?,
        parsedYear: Int?,
        previousWorkId: Long?,
    ) {
        val refreshed = seriesIngest.refreshSeason(tmdbId, season)
        val saved = catalog.findSavedEpisode(ExternalProvider.tmdb, tmdbId.toString(), season, episode)
            ?: throw IllegalStateException("没有找到第 $season 季第 $episode 集")
        val work = refreshed.work
        if (work != null && tvdb.configured()) {
            try {
                catalog.applySupplement(
                    saved.workId,
                    tvdb.enrich(work.kind, parsedTitle ?: work.originalTitle, parsedYear, work.originalTitle, season),
                )
            } catch (ex: RuntimeException) {
                log.warn("人工匹配 TVDB 补充失败 fileId={} reason={}", fileId, ex.message)
            }
        }
        supplementRatings(saved.workId)
        linkFile(fileId, saved.workId, saved.episodeId)
        aliases.remember(parsedTitle, parsedYear, saved.workId, tmdbId)
        if (previousWorkId != null && previousWorkId != saved.workId && files.findByWork_IdOrderByIdAsc(previousWorkId).isEmpty()) {
            events.notifyWorkRemovedAfterCommit(previousWorkId)
        }
        log.info(
            "人工匹配单集完成 fileId={} tmdbId={} workId={} season={} episode={}",
            fileId,
            tmdbId,
            saved.workId,
            season,
            episode,
        )
    }

    private fun scrapeWholeSeries(
        previousWorkId: Long,
        tmdbId: Long,
        parsedTitle: String?,
        parsedYear: Int?,
        ready: List<SeriesFileTarget>,
    ) {
        var linkedWorkId: Long? = null
        var enriched = false
        for ((season, group) in ready.groupBy { requireNotNull(it.season) }) {
            try {
                val refreshed = seriesIngest.refreshSeason(tmdbId, season)
                val work = refreshed.work
                val savedWorkId = refreshed.saved.workId
                if (!enriched && work != null && tvdb.configured()) {
                    try {
                        catalog.applySupplement(
                            savedWorkId,
                            tvdb.enrich(work.kind, parsedTitle ?: work.originalTitle, parsedYear, work.originalTitle, season),
                        )
                    } catch (ex: RuntimeException) {
                        log.warn("整部改挂 TVDB 补充失败 workId={} reason={}", savedWorkId, ex.message)
                    }
                    enriched = true
                }
                for (target in group) {
                    val episode = target.episode ?: continue
                    val saved = catalog.findSavedEpisode(ExternalProvider.tmdb, tmdbId.toString(), season, episode)
                    if (saved == null) {
                        matchState.markFailed(target.id, "没有找到第 $season 季第 $episode 集")
                        continue
                    }
                    linkFile(target.id, saved.workId, saved.episodeId)
                    linkedWorkId = saved.workId
                }
            } catch (ex: Exception) {
                log.warn("整部改挂失败 season={} reason={}", season, ex.message)
                for (target in group) {
                    matchState.markFailed(target.id, ex.message ?: "整部改挂失败")
                }
            }
        }
        val linked = linkedWorkId
        if (linked != null) {
            supplementRatings(linked)
            aliases.remember(parsedTitle, parsedYear, linked, tmdbId)
            if (files.findByWork_IdOrderByIdAsc(previousWorkId).isEmpty()) {
                events.notifyWorkRemovedAfterCommit(previousWorkId)
            }
        }
        log.info("整部改挂结束 previousWorkId={} linkedWorkId={}", previousWorkId, linkedWorkId)
    }

    private fun linkFile(fileId: Long, workId: Long, episodeId: Long?) {
        matchState.markMatched(fileId, workId, episodeId, 1.0, "人工匹配")
        fingerprints.remember(fileId, workId, episodeId)
    }

    private fun supplementRatings(workId: Long) {
        try {
            omdbRatings.enrichWork(workId)
        } catch (ex: RuntimeException) {
            log.warn("OMDb 评分补充失败 workId={} reason={}", workId, ex.message)
        }
    }

    private fun SearchCandidate.toRanked(query: String?, queryYear: Int?): RankedCandidate {
        val score = TitleScore.of(query, queryYear, title, originalTitle, year)
        return RankedCandidate(
            provider = "tmdb",
            kind = kind,
            externalId = id.toString(),
            title = title,
            originalTitle = originalTitle,
            year = year,
            overview = overview,
            posterUrl = TmdbImageUrls.resolve(posterUrl, appSettings.current().tmdbImageBaseUrl),
            score = score,
        )
    }
}

data class SeriesFileLink(
    val id: Long,
    val workId: Long,
    val episodeId: Long?,
    val parsedTitle: String,
    val parsedYear: Int?,
    val parsedSeason: Int,
    val parsedEpisode: Int,
)

private data class SeriesFileTarget(
    val id: Long,
    val season: Int?,
    val episode: Int?,
)
