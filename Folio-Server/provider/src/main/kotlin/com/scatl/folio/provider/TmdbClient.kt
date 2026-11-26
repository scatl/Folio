package com.scatl.folio.provider

import com.scatl.folio.catalog.ArtworkKind
import com.scatl.folio.catalog.ExternalProvider
import com.scatl.folio.settings.FolioSettings
import com.scatl.folio.util.TmdbImageUrls
import org.slf4j.LoggerFactory
import org.springframework.stereotype.Component
import java.math.BigDecimal
import java.math.RoundingMode

@Component
class TmdbClient(
    private val appSettings: FolioSettings,
    private val providers: ProviderClients,
) {
    private val log = LoggerFactory.getLogger(javaClass)
    private val settings get() = appSettings.current()
    private val client get() = providers.tmdb.client
    private val pacer get() = providers.tmdb.pacer

    fun configured(): Boolean = settings.tmdbConfigured()

    fun searchMovies(query: String, year: Int?, language: String? = null): List<MediaHit> {
        val root = getObject(
            "搜索电影",
            "/search/movie",
            queryParams(query, year, "year", language ?: settings.tmdbSearchLanguage),
        )
        return hits("movie", "title", "original_title", "release_date", JsonBodies.maps(root["results"]))
    }

    fun searchSeries(query: String, year: Int?, language: String? = null): List<MediaHit> {
        val root = getObject(
            "搜索剧集",
            "/search/tv",
            queryParams(query, year, "first_air_date_year", language ?: settings.tmdbSearchLanguage),
        )
        return hits("series", "name", "original_name", "first_air_date", JsonBodies.maps(root["results"]))
    }

    fun searchMovieCandidates(query: String, year: Int?): List<SearchCandidate> {
        // 人工匹配展示用配置语言（默认 zh-CN），简介/标题走中文
        val root = getObject("搜索电影候选", "/search/movie", queryParams(query, year, "year", settings.tmdbLanguage))
        return candidates("movie", "title", "original_title", "release_date", JsonBodies.maps(root["results"]))
    }

    fun searchSeriesCandidates(query: String, year: Int?): List<SearchCandidate> {
        val root = getObject("搜索剧集候选", "/search/tv", queryParams(query, year, "first_air_date_year", settings.tmdbLanguage))
        return candidates("series", "name", "original_name", "first_air_date", JsonBodies.maps(root["results"]))
    }

    fun findByImdb(imdbId: String): List<MediaHit> {
        val root = getObject(
            "按 IMDb 反查",
            "/find/$imdbId",
            mapOf("external_source" to "imdb_id", "language" to settings.tmdbSearchLanguage),
        )
        val found = mutableListOf<MediaHit>()
        found += hits("movie", "title", "original_title", "release_date", JsonBodies.maps(root["movie_results"]))
        found += hits("series", "name", "original_name", "first_air_date", JsonBodies.maps(root["tv_results"]))
        for (item in JsonBodies.maps(root["tv_episode_results"])) {
            val showId = JsonBodies.longValue(item, "show_id") ?: continue
            val aired = Dates.parse(JsonBodies.text(item, "air_date"))
            found += MediaHit(
                "series",
                showId,
                JsonBodies.text(item, "name"),
                JsonBodies.text(item, "name"),
                aired?.year,
                JsonBodies.integer(item, "season_number"),
                JsonBodies.integer(item, "episode_number"),
            )
        }
        return found
    }

    fun collection(id: Long): TmdbCollection {
        log.info("TMDB 拉取系列详情 开始 id={}", id)
        val started = System.nanoTime()
        return try {
            val root = getObject(
                "请求系列详情接口",
                "/collection/$id",
                mapOf("language" to settings.tmdbLanguage),
            )
            val parts = JsonBodies.maps(root["parts"]).mapNotNull { item ->
                val partId = JsonBodies.longValue(item, "id") ?: return@mapNotNull null
                val premiere = Dates.parse(JsonBodies.text(item, "release_date"))
                val genreIds = (item["genre_ids"] as? List<*>)
                    ?.mapNotNull { value -> (value as? Number)?.toInt() }
                    .orEmpty()
                TmdbCollection.Part(
                    partId,
                    JsonBodies.text(item, "title"),
                    JsonBodies.text(item, "original_title"),
                    JsonBodies.text(item, "overview"),
                    premiere,
                    image(JsonBodies.text(item, "poster_path")),
                    image(JsonBodies.text(item, "backdrop_path")),
                    JsonBodies.text(item, "original_language"),
                    score(JsonBodies.decimal(item, "vote_average")),
                    JsonBodies.integer(item, "vote_count"),
                    genreIds,
                )
            }
            val collection = TmdbCollection(
                id,
                JsonBodies.text(root, "name") ?: "系列 $id",
                JsonBodies.text(root, "overview"),
                image(JsonBodies.text(root, "poster_path")),
                image(JsonBodies.text(root, "backdrop_path")),
                parts,
            )
            log.info("TMDB 拉取系列详情 结束 id={} name={} parts={} 总耗时={}ms", id, collection.name, parts.size, elapsedMs(started))
            collection
        } catch (ex: RuntimeException) {
            log.warn("TMDB 拉取系列详情 失败 id={} 总耗时={}ms: {}", id, elapsedMs(started), ex.message)
            throw ex
        }
    }

    fun movie(id: Long): CanonicalWork {
        log.info("TMDB 拉取电影详情 开始 id={}", id)
        val started = System.nanoTime()
        return try {
            val body = get("请求电影详情接口", "/movie/$id", detailQuery())
            val root = JsonBodies.read("tmdb", body)
            val premiere = Dates.parse(JsonBodies.text(root, "release_date"))
            val originalTitle = firstNonBlank(JsonBodies.text(root, "original_title"), JsonBodies.text(root, "title"))
            val work = assemble(
                "movie", id, originalTitle, JsonBodies.text(root, "original_language"), premiere,
                JsonBodies.integer(root, "runtime"), JsonBodies.text(root, "status"), "movie/$id", body, root,
                JsonBodies.text(root, "title"), emptyList(), emptyList(),
            )
            log.info("TMDB 拉取电影详情 结束 id={} title={} 总耗时={}ms", id, work.originalTitle, elapsedMs(started))
            work
        } catch (ex: RuntimeException) {
            log.warn("TMDB 拉取电影详情 失败 id={} 总耗时={}ms: {}", id, elapsedMs(started), ex.message)
            throw ex
        }
    }

    fun person(id: Long): TmdbPerson {
        log.info("TMDB 拉取人物详情 开始 id={}", id)
        val started = System.nanoTime()
        return try {
            val root = getObject(
                "请求人物详情接口",
                "/person/$id",
                mapOf("language" to settings.tmdbLanguage),
            )
            val alsoKnownAs = (root["also_known_as"] as? List<*>)
                ?.mapNotNull { value -> value?.toString()?.trim()?.takeIf { it.isNotEmpty() } }
                .orEmpty()
            val person = TmdbPerson(
                id = id,
                name = JsonBodies.text(root, "name") ?: "人物 $id",
                biography = JsonBodies.text(root, "biography"),
                birthday = Dates.parse(JsonBodies.text(root, "birthday")),
                deathday = Dates.parse(JsonBodies.text(root, "deathday")),
                placeOfBirth = JsonBodies.text(root, "place_of_birth"),
                profileUrl = image(JsonBodies.text(root, "profile_path")),
                knownForDepartment = JsonBodies.text(root, "known_for_department"),
                alsoKnownAs = alsoKnownAs,
            )
            log.info("TMDB 拉取人物详情 结束 id={} name={} 总耗时={}ms", id, person.name, elapsedMs(started))
            person
        } catch (ex: RuntimeException) {
            log.warn("TMDB 拉取人物详情 失败 id={} 总耗时={}ms: {}", id, elapsedMs(started), ex.message)
            throw ex
        }
    }

    fun personCombinedCredits(id: Long): List<TmdbPersonCredit> {
        log.info("TMDB 拉取人物作品 开始 id={}", id)
        val started = System.nanoTime()
        return try {
            val root = getObject(
                "请求人物作品接口",
                "/person/$id/combined_credits",
                mapOf("language" to settings.tmdbLanguage),
            )
            val byKey = linkedMapOf<String, TmdbPersonCredit>()
            fun putCredit(item: Map<String, Any?>, character: String?, job: String?, department: String?) {
                val mediaType = JsonBodies.text(item, "media_type")?.lowercase() ?: return
                if (mediaType != "movie" && mediaType != "tv") return
                val creditId = JsonBodies.longValue(item, "id") ?: return
                val dateText = if (mediaType == "movie") {
                    JsonBodies.text(item, "release_date")
                } else {
                    JsonBodies.text(item, "first_air_date")
                }
                val premiere = Dates.parse(dateText)
                val title = if (mediaType == "movie") {
                    JsonBodies.text(item, "title")
                } else {
                    JsonBodies.text(item, "name")
                }
                val originalTitle = if (mediaType == "movie") {
                    JsonBodies.text(item, "original_title")
                } else {
                    JsonBodies.text(item, "original_name")
                }
                val key = "$mediaType:$creditId"
                val existing = byKey[key]
                if (existing == null) {
                    byKey[key] = TmdbPersonCredit(
                        mediaType = mediaType,
                        id = creditId,
                        title = title,
                        originalTitle = originalTitle,
                        year = premiere?.year,
                        releaseDate = premiere,
                        posterUrl = image(JsonBodies.text(item, "poster_path")),
                        character = character,
                        job = job,
                        department = department,
                    )
                    return
                }
                byKey[key] = existing.copy(
                    character = existing.character ?: character,
                    job = existing.job ?: job,
                    department = existing.department ?: department,
                    title = existing.title ?: title,
                    originalTitle = existing.originalTitle ?: originalTitle,
                    posterUrl = existing.posterUrl ?: image(JsonBodies.text(item, "poster_path")),
                    year = existing.year ?: premiere?.year,
                    releaseDate = existing.releaseDate ?: premiere,
                )
            }
            JsonBodies.maps(root["cast"]).forEach { item ->
                putCredit(
                    item,
                    character = JsonBodies.text(item, "character"),
                    job = null,
                    department = "Acting",
                )
            }
            JsonBodies.maps(root["crew"]).forEach { item ->
                putCredit(
                    item,
                    character = null,
                    job = JsonBodies.text(item, "job"),
                    department = JsonBodies.text(item, "department"),
                )
            }
            val credits = byKey.values.toList()
            log.info("TMDB 拉取人物作品 结束 id={} credits={} 总耗时={}ms", id, credits.size, elapsedMs(started))
            credits
        } catch (ex: RuntimeException) {
            log.warn("TMDB 拉取人物作品 失败 id={} 总耗时={}ms: {}", id, elapsedMs(started), ex.message)
            throw ex
        }
    }

    fun alternativeTitles(seriesId: Long): List<String> = try {
        val root = getObject(
            "拉取剧集别名 seriesId=$seriesId",
            "/tv/$seriesId/alternative_titles",
            emptyMap(),
        )
        JsonBodies.maps(root["results"]).mapNotNull { item ->
            JsonBodies.text(item, "title")?.trim()?.takeIf { it.isNotEmpty() }
        }
    } catch (ex: ProviderException) {
        if (ex.status == 404) emptyList() else throw ex
    }

    fun series(id: Long, seasonNumber: Int?): CanonicalWork {
        log.info("TMDB 拉取剧集详情 开始 id={} season={}", id, seasonNumber)
        val started = System.nanoTime()
        return try {
            val body = get("请求剧集详情接口", "/tv/$id", detailQuery())
            val root = JsonBodies.read("tmdb", body)
            val premiere = Dates.parse(JsonBodies.text(root, "first_air_date"))
            val originalTitle = firstNonBlank(JsonBodies.text(root, "original_name"), JsonBodies.text(root, "name"))
            val seasons = JsonBodies.maps(root["seasons"]).mapNotNull { item ->
                val number = JsonBodies.integer(item, "season_number") ?: return@mapNotNull null
                if (number < 0) return@mapNotNull null
                CanonicalWork.SeasonShell(
                    number,
                    JsonBodies.text(item, "name"),
                    JsonBodies.integer(item, "episode_count"),
                    Dates.parse(JsonBodies.text(item, "air_date")),
                    JsonBodies.text(item, "overview"),
                    image(JsonBodies.text(item, "poster_path")),
                )
            }
            val fetched = if (seasonNumber != null && seasonNumber >= 0) {
                listOfNotNull(season(id, seasonNumber))
            } else {
                emptyList()
            }
            val work = assemble(
                "series", id, originalTitle, JsonBodies.text(root, "original_language"), premiere,
                firstInteger(root["episode_run_time"]), JsonBodies.text(root, "status"), "tv/$id", body, root,
                JsonBodies.text(root, "name"), seasons, fetched,
            )
            log.info("TMDB 拉取剧集详情 结束 id={} title={} 总耗时={}ms", id, work.originalTitle, elapsedMs(started))
            work
        } catch (ex: RuntimeException) {
            log.warn("TMDB 拉取剧集详情 失败 id={} 总耗时={}ms: {}", id, elapsedMs(started), ex.message)
            throw ex
        }
    }

    private fun detailQuery(): Map<String, Any?> = mapOf(
        "append_to_response" to "credits,external_ids,translations,keywords,videos,images",
        "language" to settings.tmdbLanguage,
    )

    fun episode(seriesId: Long, seasonNumber: Int, episodeNumber: Int): TmdbEpisodeDetail {
        log.info("TMDB 拉取集详情 开始 seriesId={} season={} episode={}", seriesId, seasonNumber, episodeNumber)
        val started = System.nanoTime()
        return try {
            val root = getObject(
                "拉取集详情 seriesId=$seriesId season=$seasonNumber episode=$episodeNumber",
                "/tv/$seriesId/season/$seasonNumber/episode/$episodeNumber",
                mapOf(
                    "append_to_response" to "credits,external_ids,images,videos",
                    "language" to settings.tmdbLanguage,
                ),
            )
            val detail = TmdbEpisodeDetail(
                JsonBodies.text(root, "production_code")?.trim()?.takeIf { it.isNotEmpty() },
                episodeCredits(root),
                episodeStills(root),
                videos(root),
                episodeExternalRefs(root),
            )
            log.info(
                "TMDB 拉取集详情 结束 seriesId={} season={} episode={} credits={} stills={} videos={} 总耗时={}ms",
                seriesId,
                seasonNumber,
                episodeNumber,
                detail.credits.size,
                detail.stills.size,
                detail.videos.size,
                elapsedMs(started),
            )
            detail
        } catch (ex: RuntimeException) {
            log.warn(
                "TMDB 拉取集详情 失败 seriesId={} season={} episode={} 总耗时={}ms: {}",
                seriesId,
                seasonNumber,
                episodeNumber,
                elapsedMs(started),
                ex.message,
            )
            throw ex
        }
    }

    private fun season(seriesId: Long, seasonNumber: Int): CanonicalWork.SeasonDetail? = try {
        val root = getObject(
            "拉取季详情 seriesId=$seriesId season=$seasonNumber",
            "/tv/$seriesId/season/$seasonNumber",
            mapOf("language" to settings.tmdbLanguage),
        )
        val episodes = JsonBodies.maps(root["episodes"]).mapNotNull { item ->
            val number = JsonBodies.integer(item, "episode_number") ?: return@mapNotNull null
            val primary = image(JsonBodies.text(item, "still_path"))
            val stills = if (primary == null) {
                emptyList()
            } else {
                listOf(CanonicalWork.ArtworkRef(ExternalProvider.tmdb, ArtworkKind.still, null, primary))
            }
            CanonicalWork.EpisodeDetail(
                number,
                null,
                JsonBodies.text(item, "name"),
                JsonBodies.text(item, "overview"),
                Dates.parse(JsonBodies.text(item, "air_date")),
                JsonBodies.integer(item, "runtime"),
                stills,
                JsonBodies.decimal(item, "vote_average"),
                JsonBodies.integer(item, "vote_count"),
            )
        }
        CanonicalWork.SeasonDetail(
            seasonNumber,
            JsonBodies.text(root, "name"),
            episodes.size,
            Dates.parse(JsonBodies.text(root, "air_date")),
            JsonBodies.text(root, "overview"),
            image(JsonBodies.text(root, "poster_path")),
            episodes,
        )
    } catch (ex: ProviderException) {
        if (ex.status == 404) null else throw ex
    }

    private fun assemble(
        kind: String,
        id: Long,
        originalTitle: String?,
        originalLanguage: String?,
        premiere: java.time.LocalDate?,
        runtime: Int?,
        status: String?,
        snapshotKey: String,
        snapshotBody: String,
        root: Map<String, Any?>,
        displayTitle: String?,
        seasons: List<CanonicalWork.SeasonShell>,
        fetchedSeasons: List<CanonicalWork.SeasonDetail>,
    ): CanonicalWork {
        val collection = JsonBodies.map(root["belongs_to_collection"])
        val creditList = credits(root)
        return CanonicalWork(
            ExternalProvider.tmdb,
            kind,
            originalTitle ?: displayTitle,
            originalLanguage,
            premiere?.year,
            premiere,
            runtime,
            status,
            snapshotKey,
            snapshotBody,
            translations(root, displayTitle, JsonBodies.text(root, "overview"), JsonBodies.text(root, "tagline")),
            externalRefs(id, root),
            ratings(root),
            artworks(root),
            creditList,
            seasons,
            fetchedSeasons,
            JsonBodies.text(root, "homepage"),
            score(JsonBodies.decimal(root, "popularity")),
            JsonBodies.longValue(root, "budget"),
            JsonBodies.longValue(root, "revenue"),
            JsonBodies.bool(root, "adult"),
            JsonBodies.text(root, "type"),
            JsonBodies.bool(root, "in_production"),
            Dates.parse(JsonBodies.text(root, "last_air_date")),
            JsonBodies.integer(root, "number_of_seasons"),
            JsonBodies.integer(root, "number_of_episodes"),
            JsonBodies.longValue(collection, "id")?.toString(),
            JsonBodies.text(collection, "name"),
            namedRefs(JsonBodies.maps(root["genres"])),
            companies(root),
            countries(root),
            spokenLanguages(root),
            keywords(root),
            videos(root),
            creditPersonImages(creditList),
        )
    }

    private fun translations(
        root: Map<String, Any?>,
        fallbackTitle: String?,
        fallbackOverview: String?,
        fallbackTagline: String?,
    ): List<CanonicalWork.Translation> {
        // 固定只用配置语言（默认 zh-CN），不落库其它语种/繁体
        if (fallbackTitle.isNullOrBlank()) return emptyList()
        return listOf(
            CanonicalWork.Translation(settings.tmdbLanguage, fallbackTitle, fallbackOverview, fallbackTagline),
        )
    }

    private fun externalRefs(id: Long, root: Map<String, Any?>): List<CanonicalWork.ExternalRef> {
        val refs = mutableListOf(CanonicalWork.ExternalRef(ExternalProvider.tmdb, id.toString()))
        val external = JsonBodies.map(root["external_ids"])
        val known = mapOf(
            "imdb_id" to ExternalProvider.imdb,
            "tvdb_id" to ExternalProvider.tvdb,
            "wikidata_id" to ExternalProvider.wikidata,
            "facebook_id" to ExternalProvider.facebook,
            "instagram_id" to ExternalProvider.instagram,
            "twitter_id" to ExternalProvider.twitter,
            "tvrage_id" to ExternalProvider.tvrage,
            "freebase_mid" to ExternalProvider.freebase,
            "freebase_id" to ExternalProvider.freebase,
        )
        known.forEach { (field, provider) ->
            val value = JsonBodies.text(external, field) ?: JsonBodies.longValue(external, field)?.toString()
            if (!value.isNullOrBlank()) {
                refs += CanonicalWork.ExternalRef(provider, value)
            }
        }
        return refs
    }

    private fun ratings(root: Map<String, Any?>): List<CanonicalWork.RatingValue> {
        val value = score(JsonBodies.decimal(root, "vote_average")) ?: return emptyList()
        return listOf(CanonicalWork.RatingValue(ExternalProvider.tmdb, value, JsonBodies.integer(root, "vote_count"), BigDecimal.TEN))
    }

    private fun artworks(root: Map<String, Any?>): List<CanonicalWork.ArtworkRef> {
        val artworks = mutableListOf<CanonicalWork.ArtworkRef>()
        addArtwork(artworks, ArtworkKind.poster, null, image(JsonBodies.text(root, "poster_path")))
        addArtwork(artworks, ArtworkKind.backdrop, null, image(JsonBodies.text(root, "backdrop_path")))
        val collection = JsonBodies.map(root["belongs_to_collection"])
        addArtwork(artworks, ArtworkKind.collection_poster, null, image(JsonBodies.text(collection, "poster_path")))
        addArtwork(artworks, ArtworkKind.collection_backdrop, null, image(JsonBodies.text(collection, "backdrop_path")))
        val images = JsonBodies.map(root["images"])
        imageList(images["posters"], ArtworkKind.poster, artworks)
        imageList(images["backdrops"], ArtworkKind.backdrop, artworks)
        imageList(images["logos"], ArtworkKind.logo, artworks)
        return artworks
    }

    private fun imageList(value: Any?, kind: ArtworkKind, artworks: MutableList<CanonicalWork.ArtworkRef>) {
        for (item in JsonBodies.maps(value)) {
            addArtwork(artworks, kind, JsonBodies.text(item, "iso_639_1"), image(JsonBodies.text(item, "file_path")))
        }
    }

    private fun credits(root: Map<String, Any?>): List<CanonicalWork.CreditRef> {
        val credits = mutableListOf<CanonicalWork.CreditRef>()
        val creditNode = JsonBodies.map(root["credits"])
        var order = 0
        for (person in JsonBodies.maps(creditNode["cast"])) {
            credit(person, "cast", "actor", JsonBodies.text(person, "character"), order)?.let {
                credits += it
                order++
            }
        }
        for (person in JsonBodies.maps(creditNode["crew"])) {
            credit(person, "crew", JsonBodies.text(person, "job") ?: "crew", null, order)?.let {
                credits += it
                order++
            }
        }
        for (person in JsonBodies.maps(root["created_by"])) {
            credit(person, "crew", "creator", null, order)?.let {
                credits += it
                order++
            }
        }
        return credits
    }

    private fun episodeCredits(root: Map<String, Any?>): List<CanonicalWork.CreditRef> {
        val credits = mutableListOf<CanonicalWork.CreditRef>()
        val creditNode = JsonBodies.map(root["credits"])
        val cast = JsonBodies.maps(creditNode["cast"])
        val guests = JsonBodies.maps(creditNode["guest_stars"]).ifEmpty { JsonBodies.maps(root["guest_stars"]) }
        val crew = JsonBodies.maps(creditNode["crew"]).ifEmpty { JsonBodies.maps(root["crew"]) }
        var order = 0
        val seen = linkedSetOf<String>()
        fun add(person: Map<String, Any?>, department: String, job: String, character: String?) {
            val id = JsonBodies.longValue(person, "id")?.toString() ?: return
            val key = "$department:$id:${character.orEmpty()}:$job"
            if (!seen.add(key)) return
            credit(person, department, job, character, order)?.let {
                credits += it
                order++
            }
        }
        for (person in cast) {
            add(person, "cast", "actor", JsonBodies.text(person, "character"))
        }
        for (person in guests) {
            add(person, "cast", "guest_star", JsonBodies.text(person, "character"))
        }
        for (person in crew) {
            add(person, "crew", JsonBodies.text(person, "job") ?: "crew", null)
        }
        return credits
    }

    private fun episodeStills(root: Map<String, Any?>): List<CanonicalWork.ArtworkRef> {
        val stills = mutableListOf<CanonicalWork.ArtworkRef>()
        addArtwork(stills, ArtworkKind.still, null, image(JsonBodies.text(root, "still_path")))
        imageList(JsonBodies.map(root["images"])["stills"], ArtworkKind.still, stills)
        return stills.distinctBy { it.remoteUrl }.take(40)
    }

    private fun episodeExternalRefs(root: Map<String, Any?>): List<CanonicalWork.ExternalRef> {
        val refs = mutableListOf<CanonicalWork.ExternalRef>()
        JsonBodies.longValue(root, "id")?.let { refs += CanonicalWork.ExternalRef(ExternalProvider.tmdb, it.toString()) }
        val external = JsonBodies.map(root["external_ids"])
        val known = mapOf(
            "imdb_id" to ExternalProvider.imdb,
            "tvdb_id" to ExternalProvider.tvdb,
            "wikidata_id" to ExternalProvider.wikidata,
            "facebook_id" to ExternalProvider.facebook,
            "instagram_id" to ExternalProvider.instagram,
            "twitter_id" to ExternalProvider.twitter,
            "tvrage_id" to ExternalProvider.tvrage,
            "freebase_mid" to ExternalProvider.freebase,
            "freebase_id" to ExternalProvider.freebase,
        )
        known.forEach { (field, provider) ->
            val value = JsonBodies.text(external, field) ?: JsonBodies.longValue(external, field)?.toString()
            if (!value.isNullOrBlank()) {
                refs += CanonicalWork.ExternalRef(provider, value)
            }
        }
        return refs.distinctBy { it.provider to it.externalId }
    }

    private fun credit(person: Map<String, Any?>, department: String, job: String, character: String?, order: Int): CanonicalWork.CreditRef? {
        val id = JsonBodies.longValue(person, "id") ?: return null
        val name = JsonBodies.text(person, "name") ?: return null
        return CanonicalWork.CreditRef(
            ExternalProvider.tmdb,
            id.toString(),
            name,
            department,
            job,
            character,
            order,
            image(JsonBodies.text(person, "profile_path")),
        )
    }

    private fun creditPersonImages(credits: List<CanonicalWork.CreditRef>): List<CanonicalWork.PersonImages> =
        credits.mapNotNull { ref ->
            val url = ref.profileUrl?.takeIf { it.isNotBlank() } ?: return@mapNotNull null
            CanonicalWork.PersonImages(
                ref.personId,
                listOf(CanonicalWork.ArtworkRef(ExternalProvider.tmdb, ArtworkKind.poster, null, url)),
            )
        }.distinctBy { it.personId }

    private fun hits(kind: String, titleKey: String, originalKey: String, dateKey: String, results: List<Map<String, Any?>>): List<MediaHit> =
        results.take(RESULT_LIMIT).mapNotNull { item ->
            val id = JsonBodies.longValue(item, "id") ?: return@mapNotNull null
            val date = Dates.parse(JsonBodies.text(item, dateKey))
            MediaHit(kind, id, JsonBodies.text(item, titleKey), JsonBodies.text(item, originalKey), date?.year, null, null)
        }

    private fun candidates(
        kind: String,
        titleKey: String,
        originalKey: String,
        dateKey: String,
        results: List<Map<String, Any?>>,
    ): List<SearchCandidate> =
        results.take(RESULT_LIMIT).mapNotNull { item ->
            val id = JsonBodies.longValue(item, "id") ?: return@mapNotNull null
            val date = Dates.parse(JsonBodies.text(item, dateKey))
            SearchCandidate(
                kind,
                id,
                JsonBodies.text(item, titleKey),
                JsonBodies.text(item, originalKey),
                date?.year,
                JsonBodies.text(item, "overview"),
                image(JsonBodies.text(item, "poster_path")),
            )
        }

    private fun getObject(purpose: String, path: String, query: Map<String, Any?>): Map<String, Any?> =
        JsonBodies.read("tmdb", get(purpose, path, query))

    private fun get(purpose: String, path: String, query: Map<String, Any?>): String {
        val target = describe(path, query)
        log.info("TMDB {} 开始 {}", purpose, target)
        val started = System.nanoTime()
        return try {
            val body = ProviderHttp.get(
                client,
                pacer,
                "tmdb",
                uri = { builder ->
                    var uri = builder.path(path).queryParam("api_key", settings.tmdbApiKey)
                    query.forEach { (key, value) ->
                        if (value != null) {
                            uri = uri.queryParam(key, value)
                        }
                    }
                    uri.build()
                },
            )
            log.info("TMDB {} 结束 {} 耗时={}ms size={}bytes", purpose, target, elapsedMs(started), body.length)
            body
        } catch (ex: RuntimeException) {
            log.warn("TMDB {} 失败 {} 耗时={}ms: {}", purpose, target, elapsedMs(started), ex.message)
            throw ex
        }
    }

    private fun describe(path: String, query: Map<String, Any?>): String {
        val parts = query.mapNotNull { (key, value) ->
            if (value == null) null else "$key=$value"
        }
        return if (parts.isEmpty()) path else path + "?" + parts.joinToString("&")
    }

    private fun elapsedMs(started: Long): Long = (System.nanoTime() - started) / 1_000_000

    private fun queryParams(
        query: String,
        year: Int?,
        yearParam: String,
        language: String = settings.tmdbSearchLanguage,
    ): Map<String, Any?> {
        val params = linkedMapOf<String, Any?>(
            "query" to query,
            "language" to language,
            "include_adult" to "false",
        )
        if (year != null) {
            params[yearParam] = year
        }
        return params
    }

    private fun namedRefs(items: List<Map<String, Any?>>): List<CanonicalWork.NamedRef> =
        items.mapNotNull { item ->
            val id = JsonBodies.longValue(item, "id")?.toString() ?: return@mapNotNull null
            val name = JsonBodies.text(item, "name") ?: return@mapNotNull null
            CanonicalWork.NamedRef(id, name)
        }

    private fun companies(root: Map<String, Any?>): List<CanonicalWork.CompanyRef> {
        val companies = mutableListOf<CanonicalWork.CompanyRef>()
        companies += companyRefs(JsonBodies.maps(root["production_companies"]), "production")
        companies += companyRefs(JsonBodies.maps(root["networks"]), "network")
        return companies
    }

    private fun companyRefs(items: List<Map<String, Any?>>, role: String): List<CanonicalWork.CompanyRef> =
        items.mapNotNull { item ->
            val id = JsonBodies.longValue(item, "id")?.toString() ?: return@mapNotNull null
            val name = JsonBodies.text(item, "name") ?: return@mapNotNull null
            CanonicalWork.CompanyRef(
                id,
                name,
                JsonBodies.text(item, "origin_country"),
                image(JsonBodies.text(item, "logo_path")),
                role,
            )
        }

    private fun countries(root: Map<String, Any?>): List<CanonicalWork.CountryRef> {
        val countries = JsonBodies.maps(root["production_countries"]).mapNotNull { item ->
            val code = JsonBodies.text(item, "iso_3166_1") ?: return@mapNotNull null
            CanonicalWork.CountryRef(code, JsonBodies.text(item, "name"), "production")
        }.toMutableList()
        val origin = root["origin_country"]
        if (origin is List<*>) {
            origin.filterIsInstance<String>().forEach { code ->
                if (countries.none { it.code == code && it.kind == "origin" }) {
                    countries += CanonicalWork.CountryRef(code, null, "origin")
                }
            }
        }
        return countries
    }

    private fun spokenLanguages(root: Map<String, Any?>): List<CanonicalWork.LanguageRef> {
        val languages = JsonBodies.maps(root["spoken_languages"]).mapNotNull { item ->
            val code = JsonBodies.text(item, "iso_639_1") ?: return@mapNotNull null
            CanonicalWork.LanguageRef(code, firstNonBlank(JsonBodies.text(item, "english_name"), JsonBodies.text(item, "name")))
        }.toMutableList()
        val codes = root["languages"]
        if (codes is List<*>) {
            codes.filterIsInstance<String>().forEach { code ->
                if (languages.none { it.code == code }) {
                    languages += CanonicalWork.LanguageRef(code, null)
                }
            }
        }
        return languages
    }

    private fun keywords(root: Map<String, Any?>): List<CanonicalWork.NamedRef> {
        val node = JsonBodies.map(root["keywords"])
        val items = JsonBodies.maps(node["keywords"]).ifEmpty { JsonBodies.maps(node["results"]) }
        return namedRefs(items)
    }

    private fun videos(root: Map<String, Any?>): List<CanonicalWork.VideoRef> =
        JsonBodies.maps(JsonBodies.map(root["videos"])["results"]).mapNotNull { item ->
            val id = JsonBodies.text(item, "id") ?: return@mapNotNull null
            CanonicalWork.VideoRef(
                id,
                JsonBodies.text(item, "site"),
                JsonBodies.text(item, "type"),
                JsonBodies.text(item, "name"),
                JsonBodies.text(item, "key"),
                JsonBodies.text(item, "iso_639_1"),
                JsonBodies.bool(item, "official"),
            )
        }

    private fun addArtwork(artworks: MutableList<CanonicalWork.ArtworkRef>, kind: ArtworkKind, locale: String?, url: String?) {
        if (url != null) {
            artworks += CanonicalWork.ArtworkRef(ExternalProvider.tmdb, kind, locale, url)
        }
    }

    private fun image(path: String?): String? = TmdbImageUrls.store(path)

    private fun firstInteger(value: Any?): Int? {
        val list = value as? List<*> ?: return null
        return list.filterIsInstance<Number>().firstOrNull()?.toInt()
    }

    private fun score(value: Double?): BigDecimal? =
        value?.let { BigDecimal.valueOf(it).setScale(2, RoundingMode.HALF_UP) }

    companion object {
        private const val RESULT_LIMIT = 8

        private fun firstNonBlank(first: String?, second: String?): String? =
            if (!first.isNullOrBlank()) first else second

        private fun trimSlash(value: String?): String =
            if (value.isNullOrBlank()) "" else value.removeSuffix("/")
    }
}
