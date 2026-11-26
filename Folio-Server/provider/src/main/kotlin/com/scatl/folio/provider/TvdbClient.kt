package com.scatl.folio.provider

import com.scatl.folio.catalog.ArtworkKind
import com.scatl.folio.catalog.ExternalProvider
import com.scatl.folio.parse.TitleScore
import com.scatl.folio.settings.AppSettingsChangedEvent
import com.scatl.folio.settings.FolioSettings
import org.slf4j.LoggerFactory
import org.springframework.context.event.EventListener
import org.springframework.stereotype.Component
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.Duration
import java.time.Instant

@Component
class TvdbClient(
    private val appSettings: FolioSettings,
    private val providers: ProviderClients,
) {
    private val log = LoggerFactory.getLogger(javaClass)
    private val settings get() = appSettings.current()
    private val client get() = providers.tvdb.client
    private val pacer get() = providers.tvdb.pacer
    private var token: String? = null
    private var tokenUntil: Instant = Instant.EPOCH
    private var loginFailedUntil: Instant = Instant.EPOCH

    fun configured(): Boolean = settings.tvdbConfigured()

    @EventListener
    fun onSettingsChanged(event: AppSettingsChangedEvent) {
        val previous = event.previous
        val current = event.current
        if (
            previous == null ||
            previous.tvdbApiKey != current.tvdbApiKey ||
            previous.tvdbPin != current.tvdbPin ||
            previous.tvdbBaseUrl != current.tvdbBaseUrl
        ) {
            token = null
            tokenUntil = Instant.EPOCH
            loginFailedUntil = Instant.EPOCH
        }
    }

    fun enrich(kind: String, title: String?, year: Int?, originalTitle: String?, seasonNumber: Int?): SeriesEnrichment {
        log.info("TVDB 补充 开始 kind={} title={} year={}", kind, title, year)
        val started = System.nanoTime()
        return try {
            val type = if (kind == "movie") "movie" else "series"
            var best = searchBest(type, title, year, originalTitle)
            if ((best == null || best.score < settings.matchAutoThreshold) && originalTitle != null && originalTitle != title) {
                val alternate = searchBest(type, originalTitle, year, originalTitle)
                if (alternate != null && (best == null || alternate.score > best.score)) {
                    best = alternate
                }
            }
            if (best == null || best.score < settings.matchAutoThreshold) {
                log.info("TVDB 补充 结束 result=无匹配 总耗时={}ms", elapsedMs(started))
                return SeriesEnrichment.empty()
            }
            val resource = (if (kind == "movie") "movies/" else "series/") + best.id
            val body = authorizedGet("补充拉取扩展详情 id=${best.id}", "/$resource/extended", emptyMap())
            val data = dataObject(body)
            val translations = mutableListOf<CanonicalWork.Translation>()
            addTranslation(translations, "en-US", JsonBodies.text(data, "name"), JsonBodies.text(data, "overview"))
            val chinese = translation(resource)
            if (chinese.isNotEmpty()) {
                addTranslation(
                    translations,
                    "zh-CN",
                    firstNonBlank(JsonBodies.text(chinese, "name"), JsonBodies.text(chinese, "title")),
                    JsonBodies.text(chinese, "overview"),
                )
            }
            val externalIds = mutableListOf(CanonicalWork.ExternalRef(ExternalProvider.tvdb, best.id))
            for (remote in JsonBodies.maps(firstList(data, "remoteIds", "remote_ids"))) {
                val source = firstNonBlank(JsonBodies.text(remote, "sourceName"), JsonBodies.text(remote, "source"))
                val remoteId = JsonBodies.text(remote, "id")
                if (remoteId != null && source != null && source.lowercase().contains("imdb")) {
                    externalIds += CanonicalWork.ExternalRef(ExternalProvider.imdb, remoteId)
                }
            }
            val ratings = mutableListOf<CanonicalWork.RatingValue>()
            val score = JsonBodies.decimal(data, "score")
            if (score != null && score > 0) {
                ratings += SeriesEnrichment.rating(score, null)
            }
            val episodes = if (kind == "series" && seasonNumber != null) episodes(best.id, seasonNumber) else emptyList()
            val enrichment = SeriesEnrichment(resource + "/extended", body, translations, externalIds, ratings, artworks(data), episodes)
            log.info("TVDB 补充 结束 id={} 总耗时={}ms", best.id, elapsedMs(started))
            enrichment
        } catch (ex: TvdbLoginCoolingDown) {
            throw ex
        } catch (ex: RuntimeException) {
            log.warn("TVDB 补充 失败 总耗时={}ms: {}", elapsedMs(started), ex.message)
            throw ex
        }
    }

    fun catalog(kind: String, title: String?, year: Int?, originalTitle: String?, seasonNumber: Int?): CanonicalWork? {
        log.info("TVDB 拉取目录 开始 kind={} title={} year={}", kind, title, year)
        val started = System.nanoTime()
        return try {
            val best = choose(kind, title, year, originalTitle)
            if (best == null) {
                log.info("TVDB 拉取目录 结束 result=无匹配 总耗时={}ms", elapsedMs(started))
                return null
            }
            val resource = (if (kind == "movie") "movies/" else "series/") + best.id
            val body = authorizedGet("拉取扩展详情 id=${best.id}", "/$resource/extended", emptyMap())
            val data = dataObject(body)
            val premiere = Dates.parse(firstNonBlank(JsonBodies.text(data, "firstAired"), JsonBodies.text(data, "first_aired")))
            val originalTitleValue = firstNonBlank(JsonBodies.text(data, "name"), JsonBodies.text(data, "title"))
            val translations = mutableListOf<CanonicalWork.Translation>()
            addTranslation(translations, "en-US", originalTitleValue, JsonBodies.text(data, "overview"))
            val chinese = translation(resource)
            if (chinese.isNotEmpty()) {
                addTranslation(
                    translations,
                    "zh-CN",
                    firstNonBlank(JsonBodies.text(chinese, "name"), JsonBodies.text(chinese, "title")),
                    JsonBodies.text(chinese, "overview"),
                )
            }
            val seasons = seasonShells(data)
            val fetched = if (kind == "series") seasonDetails(best.id, seasons.map { it.seasonNumber }, seasonNumber) else emptyList()
            val credits = credits(data)
            val work = CanonicalWork(
                sourceProvider = ExternalProvider.tvdb,
                kind = kind,
                originalTitle = originalTitleValue,
                originalLanguage = JsonBodies.text(data, "originalLanguage"),
                year = JsonBodies.integer(data, "year") ?: premiere?.year,
                premiereDate = premiere,
                runtimeMinutes = JsonBodies.integer(data, "averageRuntime"),
                status = statusName(data["status"]),
                snapshotKey = "$resource/extended",
                snapshotBody = body,
                translations = translations,
                externalIds = externalIds(best.id, data),
                ratings = scoreRating(data),
                artworks = allArtworks(data),
                credits = credits,
                seasons = seasons,
                fetchedSeasons = fetched,
                homepage = null,
                popularity = null,
                budget = null,
                revenue = null,
                adult = null,
                showType = JsonBodies.text(data, "type"),
                inProduction = null,
                lastAirDate = Dates.parse(firstNonBlank(JsonBodies.text(data, "lastAired"), JsonBodies.text(data, "last_aired"))),
                numberOfSeasons = seasons.size.takeIf { it > 0 },
                numberOfEpisodes = fetched.sumOf { it.episodes.size }.takeIf { it > 0 },
                collectionExternalId = null,
                collectionName = null,
                genres = namedList(data["genres"]),
                companies = companies(data),
                countries = countries(data),
                spokenLanguages = languages(data),
                keywords = emptyList(),
                videos = emptyList(),
                personImages = personImages(credits),
            )
            log.info("TVDB 拉取目录 结束 id={} title={} 总耗时={}ms", best.id, work.originalTitle, elapsedMs(started))
            work
        } catch (ex: TvdbLoginCoolingDown) {
            throw ex
        } catch (ex: RuntimeException) {
            log.warn("TVDB 拉取目录 失败 总耗时={}ms: {}", elapsedMs(started), ex.message)
            throw ex
        }
    }

    private fun choose(kind: String, title: String?, year: Int?, originalTitle: String?): Candidate? {
        val type = if (kind == "movie") "movie" else "series"
        var best = searchBest(type, title, year, originalTitle)
        if ((best == null || best.score < settings.matchAutoThreshold) && originalTitle != null && originalTitle != title) {
            val alternate = searchBest(type, originalTitle, year, originalTitle)
            if (alternate != null && (best == null || alternate.score > best.score)) {
                best = alternate
            }
        }
        return best?.takeIf { it.score >= settings.matchAutoThreshold }
    }

    private fun searchBest(type: String, query: String?, year: Int?, originalTitle: String?): Candidate? {
        if (query.isNullOrBlank()) return null
        val params = linkedMapOf<String, Any?>("query" to query, "type" to type)
        if (year != null) params["year"] = year.toString()
        val body = authorizedGet("搜索$type query=$query year=$year", "/search", params)
        var best: Candidate? = null
        for (item in JsonBodies.maps(dataValue(body))) {
            val id = firstNonBlank(JsonBodies.text(item, "tvdb_id"), JsonBodies.text(item, "id")) ?: continue
            val name = firstNonBlank(JsonBodies.text(item, "name"), JsonBodies.text(item, "title")) ?: continue
            val translated = translatedName(item["translations"])
            val itemYear = JsonBodies.integer(item, "year")
            val compared = originalTitle ?: query
            val score = maxOf(
                TitleScore.of(query, year, name, translated, itemYear),
                TitleScore.of(compared, year, name, translated, itemYear),
            )
            if (best == null || score > best.score) {
                best = Candidate(id, score)
            }
        }
        return best
    }

    private fun translation(resource: String): Map<String, Any?> = try {
        dataObject(authorizedGet("拉取中文翻译 resource=$resource", "/$resource/translations/zho", emptyMap()))
    } catch (ex: ProviderException) {
        if (ex.status == 404) emptyMap() else throw ex
    }

    private fun seasonDetails(seriesId: String, seasonNumbers: List<Int>, requested: Int?): List<CanonicalWork.SeasonDetail> {
        val numbers = (seasonNumbers + listOfNotNull(requested)).filter { it >= 0 }.distinct().sorted()
        val rows = if (numbers.isEmpty()) loadEpisodes(seriesId, null) else numbers.flatMap { loadEpisodes(seriesId, it) }
        return rows.groupBy { firstInteger(it, "seasonNumber", "season") ?: requested ?: 1 }
            .toSortedMap()
            .map { (seasonNumber, items) ->
                CanonicalWork.SeasonDetail(
                    seasonNumber,
                    "第 $seasonNumber 季",
                    items.size,
                    null,
                    null,
                    null,
                    items.mapNotNull { episodeDetail(it) },
                )
            }
    }

    private fun loadEpisodes(seriesId: String, seasonNumber: Int?): List<Map<String, Any?>> {
        val rows = mutableListOf<Map<String, Any?>>()
        var page = 0
        while (page < 20) {
            val query = linkedMapOf<String, Any?>("page" to page)
            if (seasonNumber != null) query["season"] = seasonNumber
            val items = try {
                episodeItems(
                    authorizedGet(
                        "拉取分集列表 seriesId=$seriesId season=$seasonNumber page=$page",
                        "/series/$seriesId/episodes/official",
                        query,
                    ),
                )
            } catch (ex: ProviderException) {
                if (ex.status == 404) emptyList() else throw ex
            }
            if (items.isEmpty()) break
            rows += items
            if (items.size < 50) break
            page++
        }
        return rows
    }

    private fun episodeDetail(item: Map<String, Any?>): CanonicalWork.EpisodeDetail? {
        val number = firstInteger(item, "number", "episodeNumber") ?: return null
        val image = firstNonBlank(JsonBodies.text(item, "image"), JsonBodies.text(item, "thumbnail"))
        val stills = if (image.isNullOrBlank()) {
            emptyList()
        } else {
            listOf(CanonicalWork.ArtworkRef(ExternalProvider.tvdb, ArtworkKind.still, null, image))
        }
        return CanonicalWork.EpisodeDetail(
            number,
            JsonBodies.integer(item, "absoluteNumber"),
            firstNonBlank(JsonBodies.text(item, "name"), JsonBodies.text(item, "translatedName")),
            JsonBodies.text(item, "overview"),
            Dates.parse(firstNonBlank(JsonBodies.text(item, "aired"), JsonBodies.text(item, "firstAired"))),
            JsonBodies.integer(item, "runtime"),
            stills,
            null,
            null,
        )
    }

    private fun seasonShells(data: Map<String, Any?>): List<CanonicalWork.SeasonShell> =
        JsonBodies.maps(firstList(data, "seasons", "season")).mapNotNull { item ->
            val number = firstInteger(item, "number", "seasonNumber") ?: return@mapNotNull null
            CanonicalWork.SeasonShell(
                number,
                JsonBodies.text(item, "name"),
                JsonBodies.integer(item, "numberOfEpisodes") ?: JsonBodies.integer(item, "episodeCount"),
                Dates.parse(JsonBodies.text(item, "firstAired")),
                JsonBodies.text(item, "overview"),
                firstNonBlank(JsonBodies.text(item, "image"), JsonBodies.text(item, "poster")),
            )
        }

    private fun externalIds(tvdbId: String, data: Map<String, Any?>): List<CanonicalWork.ExternalRef> {
        val refs = mutableListOf(CanonicalWork.ExternalRef(ExternalProvider.tvdb, tvdbId))
        for (remote in JsonBodies.maps(firstList(data, "remoteIds", "remote_ids"))) {
            val source = firstNonBlank(JsonBodies.text(remote, "sourceName"), JsonBodies.text(remote, "source"))?.lowercase()
                ?: continue
            val remoteId = JsonBodies.text(remote, "id") ?: continue
            val provider = when {
                "imdb" in source -> ExternalProvider.imdb
                "themoviedb" in source || source == "tmdb" -> ExternalProvider.tmdb
                "tvdb" in source -> ExternalProvider.tvdb
                else -> null
            } ?: continue
            refs += CanonicalWork.ExternalRef(provider, remoteId)
        }
        return refs.distinctBy { it.provider to it.externalId }
    }

    private fun scoreRating(data: Map<String, Any?>): List<CanonicalWork.RatingValue> {
        val score = JsonBodies.decimal(data, "score") ?: return emptyList()
        if (score <= 0) return emptyList()
        return listOf(
            CanonicalWork.RatingValue(
                ExternalProvider.tvdb,
                BigDecimal.valueOf(score).setScale(2, RoundingMode.HALF_UP),
                null,
                BigDecimal.TEN,
            ),
        )
    }

    private fun namedList(value: Any?): List<CanonicalWork.NamedRef> {
        val objects = JsonBodies.maps(value)
        if (objects.isNotEmpty()) {
            return objects.mapNotNull { item ->
                val name = JsonBodies.text(item, "name") ?: return@mapNotNull null
                val id = JsonBodies.text(item, "id") ?: JsonBodies.longValue(item, "id")?.toString() ?: name
                CanonicalWork.NamedRef(id, name)
            }
        }
        val list = value as? List<*> ?: return emptyList()
        return list.mapNotNull { item ->
            val name = item as? String ?: return@mapNotNull null
            if (name.isBlank()) null else CanonicalWork.NamedRef(name, name)
        }
    }

    private fun companies(data: Map<String, Any?>): List<CanonicalWork.CompanyRef> {
        val companies = companyRefs(JsonBodies.maps(data["companies"]), "production").toMutableList()
        companies += companyRefs(JsonBodies.maps(data["networks"]), "network")
        return companies.distinctBy { it.externalId to it.role }
    }

    private fun companyRefs(items: List<Map<String, Any?>>, fallbackRole: String): List<CanonicalWork.CompanyRef> =
        items.mapNotNull { item ->
            val name = JsonBodies.text(item, "name") ?: return@mapNotNull null
            val id = JsonBodies.text(item, "id") ?: JsonBodies.longValue(item, "id")?.toString() ?: name
            val type = JsonBodies.map(item["companyType"])
            CanonicalWork.CompanyRef(
                id,
                name,
                JsonBodies.text(item, "country") ?: JsonBodies.text(item, "originCountry"),
                firstNonBlank(JsonBodies.text(item, "logo"), JsonBodies.text(item, "image")),
                JsonBodies.text(type, "name") ?: fallbackRole,
            )
        }

    private fun countries(data: Map<String, Any?>): List<CanonicalWork.CountryRef> {
        val code = JsonBodies.text(data, "originalCountry") ?: return emptyList()
        return listOf(CanonicalWork.CountryRef(code, null, "origin"))
    }

    private fun languages(data: Map<String, Any?>): List<CanonicalWork.LanguageRef> {
        val code = JsonBodies.text(data, "originalLanguage") ?: return emptyList()
        return listOf(CanonicalWork.LanguageRef(code, null))
    }

    private fun statusName(value: Any?): String? = when (value) {
        is String -> value
        is Map<*, *> -> JsonBodies.text(JsonBodies.map(value), "name")
        else -> null
    }

    private fun allArtworks(data: Map<String, Any?>): List<CanonicalWork.ArtworkRef> =
        JsonBodies.maps(data["artworks"]).mapNotNull { item ->
            val url = firstNonBlank(JsonBodies.text(item, "image"), JsonBodies.text(item, "thumbnail")) ?: return@mapNotNull null
            val kind = artworkKind(item["type"]) ?: return@mapNotNull null
            val language = JsonBodies.text(item, "language")
            CanonicalWork.ArtworkRef(
                ExternalProvider.tvdb,
                kind,
                if (language.equals("zho", ignoreCase = true)) "zh-CN" else language,
                url,
            )
        }.distinctBy { it.kind to it.remoteUrl }

    private fun personImages(credits: List<CanonicalWork.CreditRef>): List<CanonicalWork.PersonImages> =
        credits.groupBy { it.personId }.map { (personId, refs) ->
            val images = refs.mapNotNull { it.profileUrl }.distinct().map { url ->
                CanonicalWork.ArtworkRef(ExternalProvider.tvdb, ArtworkKind.poster, null, url)
            }
            CanonicalWork.PersonImages(personId, images)
        }

    private fun credits(data: Map<String, Any?>): List<CanonicalWork.CreditRef> {
        val credits = mutableListOf<CanonicalWork.CreditRef>()
        JsonBodies.maps(firstList(data, "characters", "people")).forEachIndexed { index, item ->
            val personId = JsonBodies.text(item, "peopleId")
                ?: JsonBodies.longValue(item, "peopleId")?.toString()
                ?: JsonBodies.text(item, "id")
                ?: return@forEachIndexed
            val name = firstNonBlank(JsonBodies.text(item, "personName"), JsonBodies.text(item, "name")) ?: return@forEachIndexed
            val profile = firstNonBlank(JsonBodies.text(item, "personImgURL"), JsonBodies.text(item, "image"))
            credits += CanonicalWork.CreditRef(
                ExternalProvider.tvdb,
                personId,
                name,
                JsonBodies.text(item, "peopleType") ?: "cast",
                JsonBodies.text(item, "peopleType") ?: "actor",
                JsonBodies.text(item, "name"),
                index,
                profile,
            )
        }
        return credits
    }

    private fun episodes(seriesId: String, seasonNumber: Int): List<SeriesEnrichment.EpisodePatch> = try {
        val body = authorizedGet(
            "补充拉取分集 seriesId=$seriesId season=$seasonNumber",
            "/series/$seriesId/episodes/official",
            mapOf("season" to seasonNumber, "page" to 0),
        )
        episodeItems(body).mapNotNull { item ->
            val episodeNumber = firstInteger(item, "number", "episodeNumber") ?: return@mapNotNull null
            SeriesEnrichment.EpisodePatch(
                seasonNumber,
                episodeNumber,
                JsonBodies.integer(item, "absoluteNumber"),
                firstNonBlank(JsonBodies.text(item, "name"), JsonBodies.text(item, "translatedName")),
                JsonBodies.text(item, "overview"),
            )
        }
    } catch (ex: ProviderException) {
        if (ex.status == 404) emptyList() else throw ex
    }

    private fun artworks(data: Map<String, Any?>): List<CanonicalWork.ArtworkRef> {
        val artworks = mutableListOf<CanonicalWork.ArtworkRef>()
        var poster = false
        var backdrop = false
        for (item in JsonBodies.maps(data["artworks"])) {
            val url = firstNonBlank(JsonBodies.text(item, "image"), JsonBodies.text(item, "thumbnail")) ?: continue
            val kind = artworkKind(item["type"]) ?: continue
            if ((kind == ArtworkKind.poster && poster) || (kind == ArtworkKind.backdrop && backdrop)) continue
            val language = JsonBodies.text(item, "language")
            artworks += SeriesEnrichment.artwork(kind, if (language.equals("zho", ignoreCase = true)) "zh-CN" else language, url)
            poster = poster || kind == ArtworkKind.poster
            backdrop = backdrop || kind == ArtworkKind.backdrop
        }
        return artworks
    }

    private fun authorizedGet(purpose: String, path: String, query: Map<String, Any?>): String = try {
        exchange(purpose, path, query, bearer())
    } catch (ex: ProviderException) {
        if (ex.status != 401) throw ex
        invalidate()
        exchange(purpose, path, query, bearer())
    }

    private fun exchange(purpose: String, path: String, query: Map<String, Any?>, authorization: String): String {
        val target = describe(path, query)
        log.info("TVDB {} 开始 {}", purpose, target)
        val started = System.nanoTime()
        return try {
            val body = ProviderHttp.get(
                client,
                pacer,
                "tvdb",
                uri = { builder ->
                    var uri = builder.path(path)
                    query.forEach { (key, value) ->
                        if (value != null) {
                            uri = uri.queryParam(key, value)
                        }
                    }
                    uri.build()
                },
                authorization = authorization,
            )
            log.info("TVDB {} 结束 {} 耗时={}ms size={}bytes", purpose, target, elapsedMs(started), body.length)
            body
        } catch (ex: RuntimeException) {
            log.warn("TVDB {} 失败 {} 耗时={}ms: {}", purpose, target, elapsedMs(started), ex.message)
            throw ex
        }
    }

    @Synchronized
    private fun bearer(): String {
        val now = Instant.now()
        val current = token
        if (current != null && now.isBefore(tokenUntil)) {
            return "Bearer $current"
        }
        if (now.isBefore(loginFailedUntil)) {
            val remaining = Duration.between(now, loginFailedUntil).seconds
            log.info("TVDB 登录冷却中，跳过本次 剩余{}秒", remaining)
            throw TvdbLoginCoolingDown("TheTVDB 登录失败，${LOGIN_COOLDOWN.toMinutes()} 分钟内不再重试")
        }
        val apiKey = settings.tvdbApiKey
        val pin = settings.tvdbPin
        val json = if (pin.isBlank()) {
            "{\"apikey\":${quote(apiKey)}}"
        } else {
            "{\"apikey\":${quote(apiKey)},\"pin\":${quote(pin)}}"
        }
        log.info("TVDB 登录获取 token 开始")
        val started = System.nanoTime()
        val body = try {
            ProviderHttp.postJson(client, pacer, "tvdb", "/login", json)
        } catch (ex: RuntimeException) {
            loginFailedUntil = Instant.now().plus(LOGIN_COOLDOWN)
            log.warn(
                "TVDB 登录获取 token 失败 耗时={}ms，{} 分钟内不再重试: {}",
                elapsedMs(started),
                LOGIN_COOLDOWN.toMinutes(),
                ex.message,
            )
            throw ex
        }
        val issued = JsonBodies.text(dataObject(body), "token")
            ?: throw ProviderException("tvdb", 200, "TheTVDB 登录没有返回 token").also {
                loginFailedUntil = Instant.now().plus(LOGIN_COOLDOWN)
            }
        token = issued
        tokenUntil = Instant.now().plusSeconds(12 * 60 * 60)
        loginFailedUntil = Instant.EPOCH
        log.info("TVDB 登录获取 token 结束 耗时={}ms", elapsedMs(started))
        return "Bearer $issued"
    }

    private fun describe(path: String, query: Map<String, Any?>): String {
        val parts = query.mapNotNull { (key, value) ->
            if (value == null) null else "$key=$value"
        }
        return if (parts.isEmpty()) path else path + "?" + parts.joinToString("&")
    }

    private fun elapsedMs(started: Long): Long = (System.nanoTime() - started) / 1_000_000

    @Synchronized
    private fun invalidate() {
        token = null
        tokenUntil = Instant.EPOCH
    }

    private fun dataObject(body: String): Map<String, Any?> = JsonBodies.map(JsonBodies.read("tvdb", body)["data"])

    private fun dataValue(body: String): Any = JsonBodies.read("tvdb", body)["data"] ?: emptyList<Any>()

    private fun episodeItems(body: String): List<Map<String, Any?>> {
        val data = dataValue(body)
        return if (data is List<*>) JsonBodies.maps(data) else JsonBodies.maps(JsonBodies.map(data)["episodes"])
    }

    private fun firstList(data: Map<String, Any?>, primary: String, alternate: String): Any? =
        data[primary] ?: data[alternate]

    private fun firstInteger(item: Map<String, Any?>, primary: String, alternate: String): Int? =
        JsonBodies.integer(item, primary) ?: JsonBodies.integer(item, alternate)

    private fun translatedName(translations: Any?): String? {
        val raw = translations as? Map<*, *> ?: return null
        val chinese = raw["zho"] ?: raw["zh"] ?: return null
        val text = chinese.toString().trim()
        return if (text.isEmpty() || text == "null") null else text
    }

    private fun artworkKind(type: Any?): ArtworkKind? = when (type) {
        is Number -> when (type.toInt()) {
            2 -> ArtworkKind.poster
            3 -> ArtworkKind.backdrop
            else -> null
        }
        is String -> when {
            type.contains("poster", ignoreCase = true) -> ArtworkKind.poster
            type.contains("background", ignoreCase = true) || type.contains("fanart", ignoreCase = true) -> ArtworkKind.backdrop
            else -> null
        }
        else -> null
    }

    private fun addTranslation(translations: MutableList<CanonicalWork.Translation>, locale: String, title: String?, overview: String?) {
        if (!title.isNullOrBlank()) {
            translations += CanonicalWork.Translation(locale, title, overview, null)
        }
    }

    private fun quote(value: String): String = "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"") + "\""

    private fun firstNonBlank(first: String?, second: String?): String? = if (!first.isNullOrBlank()) first else second

    private data class Candidate(val id: String, val score: Double)

    private companion object {
        val LOGIN_COOLDOWN: Duration = Duration.ofMinutes(15)
    }
}

class TvdbLoginCoolingDown(message: String) : RuntimeException(message)
