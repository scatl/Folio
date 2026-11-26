package com.scatl.folio.library

import com.scatl.folio.catalog.ExternalProvider
import com.scatl.folio.dto.FacetOption
import com.scatl.folio.dto.WorkBrowseQuery
import com.scatl.folio.dto.WorkFacets
import jakarta.persistence.EntityManager
import org.springframework.http.HttpStatus
import org.springframework.stereotype.Component
import org.springframework.web.server.ResponseStatusException
import java.math.BigDecimal

@Component
class WorkBrowse(private val em: EntityManager) {
    fun page(request: PageRequest): PageHit {
        if (request.listRestrict && request.listLibraryIds.isEmpty()) {
            return PageHit(emptyList(), 0)
        }
        val sql = Sql()
        val where = StringBuilder(" WHERE EXISTS (SELECT 1 FROM library_files listed WHERE listed.work_id = w.id")
        appendLibrary(where, sql, "listed", request.listRestrict, request.listLibraryIds, "listLibraryIds")
        where.append(')')
        appendFilters(where, sql, request)
        val countSql = "SELECT COUNT(*) FROM works w$where"
        val total = bind(em.createNativeQuery(countSql), sql).singleResult.asLong()
        if (total == 0L || request.offset >= total) {
            return PageHit(emptyList(), total)
        }
        val order = orderBy(request.sort, sql, request.ratingProvider)
        val idSql = "SELECT w.id FROM works w$where ORDER BY $order"
        val query = bind(em.createNativeQuery(idSql), sql)
        query.firstResult = request.offset
        query.maxResults = request.limit
        val ids = query.resultList.map { (it as Number).toLong() }
        return PageHit(ids, total)
    }

    fun states(userId: Long, workIds: Collection<Long>, restrict: Boolean, libraryIds: Collection<Long>): Map<Long, String> {
        if (workIds.isEmpty() || (restrict && libraryIds.isEmpty())) return emptyMap()
        val sql = Sql()
        sql["userId"] = userId
        sql["workIds"] = workIds
        val where = StringBuilder(
            """
            SELECT w.id, w.kind, f.id, p.completed, p.position_ms
            FROM works w
            JOIN library_files f ON f.work_id = w.id
            LEFT JOIN playback_progress p ON p.library_file_id = f.id AND p.user_id = :userId
            WHERE w.id IN (:workIds)
            """.trimIndent(),
        )
        appendLibrary(where, sql, "f", restrict, libraryIds, "watchLibraryIds")
        val rows = bind(em.createNativeQuery(where.toString()), sql).resultList
        data class Acc(var files: Int = 0, var completed: Int = 0, var started: Int = 0, var kind: String = "movie")
        val acc = linkedMapOf<Long, Acc>()
        for (row in rows) {
            val cols = row as Array<*>
            val workId = (cols[0] as Number).toLong()
            val kind = cols[1]?.toString() ?: "movie"
            val completed = cols[3].asBool()
            val position = (cols[4] as? Number)?.toLong() ?: 0L
            val item = acc.getOrPut(workId) { Acc(kind = kind) }
            item.kind = kind
            item.files += 1
            if (completed) item.completed += 1
            else if (position > 0L) item.started += 1
        }
        return acc.mapValues { (_, item) -> WatchStates.of(item.kind, item.files, item.completed, item.started) }
    }

    fun facets(listRestrict: Boolean, listLibraryIds: Collection<Long>, personQ: String?): WorkFacets {
        if (listRestrict && listLibraryIds.isEmpty()) return emptyFacets()
        return WorkFacets(
            genres = genreFacets(listRestrict, listLibraryIds),
            countries = countryFacets(listRestrict, listLibraryIds),
            languages = languageFacets(listRestrict, listLibraryIds),
            keywords = keywordFacets(listRestrict, listLibraryIds),
            companies = companyFacets(listRestrict, listLibraryIds),
            collections = collectionFacets(listRestrict, listLibraryIds),
            videoCodecs = codecFacets(listRestrict, listLibraryIds),
            dynamicRanges = rangeFacets(listRestrict, listLibraryIds),
            audioCodecs = audioCodecFacets(listRestrict, listLibraryIds),
            yearMin = yearBound(listRestrict, listLibraryIds, "MIN"),
            yearMax = yearBound(listRestrict, listLibraryIds, "MAX"),
            people = peopleFacets(listRestrict, listLibraryIds, personQ),
        )
    }

    private fun appendFilters(where: StringBuilder, sql: Sql, request: PageRequest) {
        request.kind?.let {
            where.append(" AND w.kind = :kind")
            sql["kind"] = it
        }
        appendSearch(where, sql, request.raw, request.text, request.searchYear)
        if (request.genreIds.isNotEmpty()) {
            where.append(" AND EXISTS (SELECT 1 FROM work_genres wg WHERE wg.work_id = w.id AND wg.genre_id IN (:genreIds))")
            sql["genreIds"] = request.genreIds
        }
        request.yearFrom?.let {
            where.append(" AND w.release_year >= :yearFrom")
            sql["yearFrom"] = it
        }
        request.yearTo?.let {
            where.append(" AND w.release_year <= :yearTo")
            sql["yearTo"] = it
        }
        if (request.ratingMin != null) {
            where.append(
                """
                 AND EXISTS (
                   SELECT 1 FROM ratings r
                   WHERE r.owner_type = 'work' AND r.owner_id = w.id
                     AND r.provider = :ratingProvider AND r.score_value >= :ratingMin
                 )
                """.trimIndent(),
            )
            sql["ratingProvider"] = request.ratingProvider ?: ExternalProvider.tmdb.name
            sql["ratingMin"] = request.ratingMin
        }
        if (request.countries.isNotEmpty()) {
            where.append(" AND EXISTS (SELECT 1 FROM work_countries wc WHERE wc.work_id = w.id AND wc.country_code IN (:countries))")
            sql["countries"] = request.countries
        }
        if (request.languages.isNotEmpty()) {
            where.append(" AND w.original_language IN (:languages)")
            sql["languages"] = request.languages
        }
        if (request.runtimes.isNotEmpty()) {
            where.append(" AND (")
            where.append(request.runtimes.joinToString(" OR ") { runtimeClause(it) })
            where.append(')')
        }
        if (request.keywordIds.isNotEmpty()) {
            where.append(" AND EXISTS (SELECT 1 FROM work_keywords wk WHERE wk.work_id = w.id AND wk.keyword_id IN (:keywordIds))")
            sql["keywordIds"] = request.keywordIds
        }
        request.personId?.let {
            where.append(
                """
                 AND EXISTS (
                   SELECT 1 FROM credits credit
                   WHERE credit.owner_type = 'work' AND credit.owner_id = w.id AND credit.person_id = :personId
                 )
                """.trimIndent(),
            )
            sql["personId"] = it
        }
        if (request.companyIds.isNotEmpty()) {
            where.append(
                """
                 AND EXISTS (
                   SELECT 1 FROM work_companies company_link
                   WHERE company_link.work_id = w.id AND company_link.company_id IN (:companyIds)
                     AND company_link.company_role = 'production'
                 )
                """.trimIndent(),
            )
            sql["companyIds"] = request.companyIds
        }
        if (request.collectionIds.isNotEmpty()) {
            where.append(" AND w.collection_external_id IN (:collectionIds)")
            sql["collectionIds"] = request.collectionIds
        }
        if (request.inCollection) {
            where.append(" AND w.collection_external_id IS NOT NULL AND w.collection_external_id <> ''")
        }
        if (request.showStatuses.isNotEmpty()) {
            where.append(" AND (")
            where.append(request.showStatuses.joinToString(" OR ") { statusClause(it) })
            where.append(')')
        }
        if (request.resolutions.isNotEmpty()) {
            val clause = request.resolutions.joinToString(" OR ") { resolutionClause(it) }
            where.append(" AND ${fileExists(request, clause)}")
        }
        if (request.dynamicRanges.isNotEmpty()) {
            val clause = request.dynamicRanges.mapIndexed { index, value -> rangeClause(value, sql, index) }
                .joinToString(" OR ")
            where.append(" AND ${fileExists(request, clause)}")
        }
        if (request.videoCodecs.isNotEmpty()) {
            where.append(" AND ${fileExists(request, "ff.video_codec IN (:videoCodecs)")}")
            sql["videoCodecs"] = request.videoCodecs
        }
        if (request.audioCodecs.isNotEmpty()) {
            val clause = request.audioCodecs.mapIndexed { index, codec ->
                val name = "audioLike$index"
                sql[name] = "%\"codec\":\"$codec\"%"
                "ff.audio_tracks LIKE :$name"
            }.joinToString(" OR ")
            where.append(" AND ${fileExists(request, clause)}")
        }
        when (request.subtitle) {
            "embedded" -> where.append(
                " AND ${fileExists(request, "ff.subtitle_tracks IS NOT NULL AND ff.subtitle_tracks <> '' AND ff.subtitle_tracks <> '[]'")}",
            )
            "none" -> where.append(
                " AND NOT ${fileExists(request, "ff.subtitle_tracks IS NOT NULL AND ff.subtitle_tracks <> '' AND ff.subtitle_tracks <> '[]'")}",
            )
        }
        request.watch?.let { where.append(" AND ${watchClause(it, request, sql)}") }
    }

    private fun appendSearch(where: StringBuilder, sql: Sql, raw: String?, text: String?, year: Int?) {
        if (raw.isNullOrBlank()) return
        val parts = mutableListOf(likeGroup(":rawLike"))
        sql["rawLike"] = like(raw)
        if (year != null) {
            val textClause = if (text.isNullOrBlank()) "1 = 1" else likeGroup(":textLike")
            if (!text.isNullOrBlank()) sql["textLike"] = like(text)
            parts += "(w.release_year = :searchYear AND ($textClause))"
            sql["searchYear"] = year
        }
        where.append(" AND (")
        where.append(parts.joinToString(" OR "))
        where.append(')')
    }

    private fun watchClause(watch: String, request: PageRequest, sql: Sql): String {
        val userId = request.userId ?: return "1 = 0"
        sql["userId"] = userId
        if (request.watchRestrict) sql["watchLibraryIds"] = request.watchLibraryIds
        return when (watch) {
            WatchStates.UNWATCHED -> "NOT ${anyProgress(request)}"
            WatchStates.WATCHED -> "((w.kind = 'movie' AND ${completedExists(request)}) OR (${seriesComplete(request)}))"
            WatchStates.WATCHING ->
                """
                (
                  (w.kind = 'movie' AND ${startedExists(request)} AND NOT ${completedExists(request)})
                  OR (w.kind = 'series' AND ${anyProgress(request)} AND NOT (${seriesComplete(request)}))
                )
                """.trimIndent()
            else -> "1 = 1"
        }
    }

    private fun progressJoin(request: PageRequest, alias: String, predicate: String): String {
        val library = librarySql(alias, request.watchRestrict, "watchLibraryIds")
        return """
            EXISTS (
              SELECT 1 FROM library_files $alias
              JOIN playback_progress wp ON wp.library_file_id = $alias.id AND wp.user_id = :userId
              WHERE $alias.work_id = w.id$library AND ($predicate)
            )
        """.trimIndent()
    }

    private fun anyProgress(request: PageRequest) = progressJoin(request, "any_file", "wp.completed = 1 OR wp.position_ms > 0")

    private fun completedExists(request: PageRequest) = progressJoin(request, "done_file", "wp.completed = 1")

    private fun startedExists(request: PageRequest) =
        progressJoin(request, "open_file", "wp.completed = 0 AND wp.position_ms > 0")

    private fun seriesComplete(request: PageRequest): String {
        val library = librarySql("series_file", request.watchRestrict, "watchLibraryIds")
        return """
            w.kind = 'series'
            AND EXISTS (SELECT 1 FROM library_files series_file WHERE series_file.work_id = w.id$library)
            AND NOT EXISTS (
              SELECT 1 FROM library_files series_file
              WHERE series_file.work_id = w.id$library
                AND NOT EXISTS (
                  SELECT 1 FROM playback_progress wp
                  WHERE wp.library_file_id = series_file.id AND wp.user_id = :userId AND wp.completed = 1
                )
            )
        """.trimIndent()
    }

    private fun fileExists(request: PageRequest, predicate: String): String {
        val library = librarySql("ff", request.listRestrict, "listLibraryIds")
        return "EXISTS (SELECT 1 FROM library_files ff WHERE ff.work_id = w.id$library AND ($predicate))"
    }

    private fun librarySql(alias: String, restrict: Boolean, param: String): String =
        if (restrict) " AND $alias.media_library_id IN (:$param)" else ""

    private fun appendLibrary(
        sqlText: StringBuilder,
        sql: Sql,
        alias: String,
        restrict: Boolean,
        libraryIds: Collection<Long>,
        param: String,
    ) {
        if (!restrict) return
        sqlText.append(" AND $alias.media_library_id IN (:$param)")
        sql[param] = libraryIds
    }

    private fun orderBy(sort: String, sql: Sql, ratingProvider: String?): String = when (sort) {
        "year" -> "w.release_year DESC, w.popularity DESC, w.id DESC"
        "added" -> "w.created_at DESC, w.id DESC"
        "rating" -> {
            sql["sortProvider"] = ratingProvider ?: ExternalProvider.tmdb.name
            """
            (
              SELECT MAX(sort_rating.score_value) FROM ratings sort_rating
              WHERE sort_rating.owner_type = 'work' AND sort_rating.owner_id = w.id
                AND sort_rating.provider = :sortProvider
            ) DESC, w.popularity DESC, w.id DESC
            """.trimIndent()
        }
        else -> "w.popularity DESC, w.id DESC"
    }

    private fun genreFacets(restrict: Boolean, libraryIds: Collection<Long>): List<FacetOption> {
        val sql = Sql()
        val text = StringBuilder(
            """
            SELECT g.id, g.name, COUNT(DISTINCT wg.work_id)
            FROM genres g
            JOIN work_genres wg ON wg.genre_id = g.id
            JOIN library_files f ON f.work_id = wg.work_id
            WHERE 1 = 1
            """.trimIndent(),
        )
        appendLibrary(text, sql, "f", restrict, libraryIds, "listLibraryIds")
        text.append(" GROUP BY g.id, g.name ORDER BY COUNT(DISTINCT wg.work_id) DESC, g.name")
        return options(text.toString(), sql)
    }

    private fun countryFacets(restrict: Boolean, libraryIds: Collection<Long>): List<FacetOption> {
        val sql = Sql()
        val text = StringBuilder(
            """
            SELECT wc.country_code, MAX(wc.name), COUNT(DISTINCT wc.work_id)
            FROM work_countries wc
            JOIN library_files f ON f.work_id = wc.work_id
            WHERE wc.country_code <> ''
            """.trimIndent(),
        )
        appendLibrary(text, sql, "f", restrict, libraryIds, "listLibraryIds")
        text.append(" GROUP BY wc.country_code ORDER BY COUNT(DISTINCT wc.work_id) DESC, wc.country_code")
        return options(text.toString(), sql).map { item ->
            val label = item.label.trim().ifEmpty { item.id }
            item.copy(label = label)
        }
    }

    private fun languageFacets(restrict: Boolean, libraryIds: Collection<Long>): List<FacetOption> {
        val sql = Sql()
        val text = StringBuilder(
            """
            SELECT w.original_language, w.original_language, COUNT(DISTINCT w.id)
            FROM works w
            JOIN library_files f ON f.work_id = w.id
            WHERE w.original_language IS NOT NULL AND w.original_language <> ''
            """.trimIndent(),
        )
        appendLibrary(text, sql, "f", restrict, libraryIds, "listLibraryIds")
        text.append(" GROUP BY w.original_language ORDER BY COUNT(DISTINCT w.id) DESC, w.original_language")
        return options(text.toString(), sql).map { item ->
            item.copy(label = languageLabel(item.id))
        }
    }

    private fun keywordFacets(restrict: Boolean, libraryIds: Collection<Long>): List<FacetOption> {
        val sql = Sql()
        val text = StringBuilder(
            """
            SELECT k.id, k.name, COUNT(DISTINCT wk.work_id)
            FROM keywords k
            JOIN work_keywords wk ON wk.keyword_id = k.id
            JOIN library_files f ON f.work_id = wk.work_id
            WHERE 1 = 1
            """.trimIndent(),
        )
        appendLibrary(text, sql, "f", restrict, libraryIds, "listLibraryIds")
        text.append(" GROUP BY k.id, k.name ORDER BY COUNT(DISTINCT wk.work_id) DESC, k.name LIMIT 80")
        return options(text.toString(), sql)
    }

    private fun companyFacets(restrict: Boolean, libraryIds: Collection<Long>): List<FacetOption> {
        val sql = Sql()
        val text = StringBuilder(
            """
            SELECT c.id, c.name, COUNT(DISTINCT link.work_id)
            FROM companies c
            JOIN work_companies link ON link.company_id = c.id AND link.company_role = 'production'
            JOIN library_files f ON f.work_id = link.work_id
            WHERE 1 = 1
            """.trimIndent(),
        )
        appendLibrary(text, sql, "f", restrict, libraryIds, "listLibraryIds")
        text.append(" GROUP BY c.id, c.name ORDER BY COUNT(DISTINCT link.work_id) DESC, c.name LIMIT 80")
        return options(text.toString(), sql)
    }

    private fun collectionFacets(restrict: Boolean, libraryIds: Collection<Long>): List<FacetOption> {
        val sql = Sql()
        val text = StringBuilder(
            """
            SELECT w.collection_external_id, MAX(w.collection_name), COUNT(DISTINCT w.id)
            FROM works w
            JOIN library_files f ON f.work_id = w.id
            WHERE w.collection_external_id IS NOT NULL AND w.collection_external_id <> ''
            """.trimIndent(),
        )
        appendLibrary(text, sql, "f", restrict, libraryIds, "listLibraryIds")
        text.append(" GROUP BY w.collection_external_id ORDER BY MAX(w.collection_name)")
        return options(text.toString(), sql).map { item ->
            item.copy(label = item.label.trim().ifEmpty { item.id })
        }
    }

    private fun codecFacets(restrict: Boolean, libraryIds: Collection<Long>): List<String> {
        val sql = Sql()
        val text = StringBuilder(
            """
            SELECT f.video_codec
            FROM library_files f
            WHERE f.video_codec IS NOT NULL AND f.video_codec <> ''
            """.trimIndent(),
        )
        appendLibrary(text, sql, "f", restrict, libraryIds, "listLibraryIds")
        text.append(" GROUP BY f.video_codec ORDER BY COUNT(*) DESC, f.video_codec")
        return strings(text.toString(), sql)
    }

    private fun rangeFacets(restrict: Boolean, libraryIds: Collection<Long>): List<String> {
        val sql = Sql()
        val text = StringBuilder(
            """
            SELECT f.video_dynamic_range
            FROM library_files f
            WHERE f.video_dynamic_range IS NOT NULL AND f.video_dynamic_range <> ''
            """.trimIndent(),
        )
        appendLibrary(text, sql, "f", restrict, libraryIds, "listLibraryIds")
        text.append(" GROUP BY f.video_dynamic_range ORDER BY COUNT(*) DESC, f.video_dynamic_range")
        return strings(text.toString(), sql)
    }

    private fun audioCodecFacets(restrict: Boolean, libraryIds: Collection<Long>): List<String> {
        val sql = Sql()
        val text = StringBuilder(
            """
            SELECT f.audio_tracks
            FROM library_files f
            WHERE f.audio_tracks IS NOT NULL AND f.audio_tracks <> '' AND f.audio_tracks <> '[]'
            """.trimIndent(),
        )
        appendLibrary(text, sql, "f", restrict, libraryIds, "listLibraryIds")
        val found = linkedSetOf<String>()
        for (row in bind(em.createNativeQuery(text.toString()), sql).resultList) {
            val raw = row?.toString() ?: continue
            for (match in AUDIO_CODEC.findAll(raw)) {
                val codec = match.groupValues[1].trim()
                if (codec.isNotEmpty()) found += codec
            }
        }
        return found.sorted()
    }

    private fun yearBound(restrict: Boolean, libraryIds: Collection<Long>, fn: String): Int? {
        val sql = Sql()
        val text = StringBuilder(
            """
            SELECT $fn(w.release_year)
            FROM works w
            WHERE w.release_year IS NOT NULL
              AND EXISTS (SELECT 1 FROM library_files f WHERE f.work_id = w.id
            """.trimIndent(),
        )
        appendLibrary(text, sql, "f", restrict, libraryIds, "listLibraryIds")
        text.append(')')
        val value = bind(em.createNativeQuery(text.toString()), sql).singleResult ?: return null
        return (value as Number).toInt()
    }

    private fun peopleFacets(restrict: Boolean, libraryIds: Collection<Long>, personQ: String?): List<FacetOption> {
        val q = personQ?.trim().orEmpty()
        if (q.isEmpty()) return emptyList()
        val sql = Sql()
        sql["personLike"] = like(q)
        val text = StringBuilder(
            """
            SELECT p.id, p.name, COUNT(DISTINCT c.owner_id)
            FROM people p
            JOIN credits c ON c.person_id = p.id AND c.owner_type = 'work'
            JOIN library_files f ON f.work_id = c.owner_id
            WHERE LOWER(p.name) LIKE :personLike
            """.trimIndent(),
        )
        appendLibrary(text, sql, "f", restrict, libraryIds, "listLibraryIds")
        text.append(" GROUP BY p.id, p.name ORDER BY COUNT(DISTINCT c.owner_id) DESC, p.name LIMIT 20")
        return options(text.toString(), sql)
    }

    private fun options(text: String, sql: Sql): List<FacetOption> =
        bind(em.createNativeQuery(text), sql).resultList.map { row ->
            val cols = row as Array<*>
            FacetOption(
                id = cols[0]?.toString().orEmpty(),
                label = cols[1]?.toString().orEmpty(),
                count = (cols[2] as Number).toInt(),
            )
        }.filter { it.id.isNotEmpty() }

    private fun strings(text: String, sql: Sql): List<String> =
        bind(em.createNativeQuery(text), sql).resultList.mapNotNull { it?.toString()?.trim()?.ifEmpty { null } }

    private fun bind(query: jakarta.persistence.Query, sql: Sql): jakarta.persistence.Query {
        for ((name, value) in sql.params) query.setParameter(name, value)
        return query
    }

    private class Sql {
        val params = linkedMapOf<String, Any>()
        operator fun set(name: String, value: Any) {
            params[name] = value
        }
    }

    data class PageHit(val ids: List<Long>, val total: Long)

    data class PageRequest(
        val kind: String?,
        val listRestrict: Boolean,
        val listLibraryIds: Collection<Long>,
        val watchRestrict: Boolean,
        val watchLibraryIds: Collection<Long>,
        val userId: Long?,
        val raw: String?,
        val text: String?,
        val searchYear: Int?,
        val sort: String,
        val watch: String?,
        val genreIds: List<Long>,
        val yearFrom: Int?,
        val yearTo: Int?,
        val ratingProvider: String?,
        val ratingMin: BigDecimal?,
        val countries: List<String>,
        val languages: List<String>,
        val runtimes: List<String>,
        val keywordIds: List<Long>,
        val personId: Long?,
        val companyIds: List<Long>,
        val collectionIds: List<String>,
        val inCollection: Boolean,
        val showStatuses: List<String>,
        val resolutions: List<String>,
        val dynamicRanges: List<String>,
        val videoCodecs: List<String>,
        val audioCodecs: List<String>,
        val subtitle: String?,
        val offset: Int,
        val limit: Int,
    )

    companion object {
        private val AUDIO_CODEC = Regex(""""codec"\s*:\s*"([^"]+)"""")
        private val TOKEN = Regex("^[A-Za-z0-9][A-Za-z0-9._+-]{0,31}$")
        private val CODE = Regex("^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})?$")
        private val COLLECTION = Regex("^[A-Za-z0-9_-]{1,64}$")
        private val LABEL = Regex("^[A-Za-z0-9 .+-]{1,32}$")
        private val RATING_PROVIDERS = setOf("tmdb", "imdb", "rottentomatoes", "metacritic")
        private val SORTS = setOf("popularity", "year", "rating", "added")
        private val WATCH = setOf(WatchStates.UNWATCHED, WatchStates.WATCHING, WatchStates.WATCHED)
        private val RUNTIME = setOf("lt90", "m90", "m120", "m150")
        private val STATUS = setOf("airing", "ended", "canceled")
        private val RESOLUTION = setOf("2160", "1080", "720", "sd")
        private val SUBTITLE = setOf("embedded", "none")

        private val LANGUAGES = mapOf(
            "zh" to "汉语",
            "cn" to "汉语",
            "en" to "英语",
            "ja" to "日语",
            "ko" to "韩语",
            "fr" to "法语",
            "de" to "德语",
            "es" to "西班牙语",
            "it" to "意大利语",
            "ru" to "俄语",
            "pt" to "葡萄牙语",
            "hi" to "印地语",
            "th" to "泰语",
            "vi" to "越南语",
            "id" to "印尼语",
            "ar" to "阿拉伯语",
            "tr" to "土耳其语",
            "pl" to "波兰语",
            "nl" to "荷兰语",
            "sv" to "瑞典语",
            "da" to "丹麦语",
            "no" to "挪威语",
            "fi" to "芬兰语",
            "cs" to "捷克语",
            "hu" to "匈牙利语",
            "el" to "希腊语",
            "he" to "希伯来语",
            "fa" to "波斯语",
            "uk" to "乌克兰语",
            "ro" to "罗马尼亚语",
            "ta" to "泰米尔语",
            "te" to "泰卢固语",
            "ml" to "马拉雅拉姆语",
            "xx" to "无对白",
        )

        fun languageLabel(code: String): String = LANGUAGES[code.lowercase()] ?: code

        fun normalize(query: WorkBrowseQuery, userId: Long?): Normalized {
            val page = query.page.coerceAtLeast(0)
            val size = query.size.coerceIn(1, 100)
            return Normalized(
                kind = enumOrNull(query.kind, setOf("movie", "series"), "kind"),
                sort = enumOrNull(query.sort, SORTS, "sort") ?: "popularity",
                watch = enumOrNull(query.watch, WATCH, "watch"),
                genreIds = positives(query.genreId, "genreId"),
                yearFrom = year(query.yearFrom, "yearFrom"),
                yearTo = year(query.yearTo, "yearTo"),
                ratingProvider = enumOrNull(query.ratingProvider, RATING_PROVIDERS, "ratingProvider"),
                ratingMin = ratingMin(query.ratingMin),
                countries = tokens(query.country, CODE, "country"),
                languages = tokens(query.language, CODE, "language"),
                runtimes = enums(query.runtime, RUNTIME, "runtime"),
                keywordIds = positives(query.keywordId, "keywordId"),
                personId = positive(query.personId, "personId"),
                companyIds = positives(query.companyId, "companyId"),
                collectionIds = tokens(query.collectionId, COLLECTION, "collectionId"),
                inCollection = query.inCollection == true,
                showStatuses = enums(query.showStatus, STATUS, "showStatus"),
                resolutions = enums(query.resolution, RESOLUTION, "resolution"),
                dynamicRanges = tokens(query.dynamicRange, LABEL, "dynamicRange").map { if (it.equals("sdr", true)) "sdr" else it }.distinct(),
                videoCodecs = tokens(query.videoCodec, TOKEN, "videoCodec"),
                audioCodecs = tokens(query.audioCodec, TOKEN, "audioCodec"),
                subtitle = enumOrNull(query.subtitle, SUBTITLE, "subtitle"),
                userId = userId,
                offset = page * size,
                limit = size,
                page = page,
                size = size,
            )
        }

        private fun enumOrNull(raw: String?, allowed: Set<String>, name: String): String? {
            val value = raw?.trim()?.ifEmpty { null } ?: return null
            if (value !in allowed) throw ResponseStatusException(HttpStatus.BAD_REQUEST, "$name 无效")
            return value
        }

        private fun pieces(raw: String?) =
            raw?.split(',')?.map { it.trim() }?.filter { it.isNotEmpty() }?.distinct().orEmpty()

        private fun enums(raw: String?, allowed: Set<String>, name: String): List<String> {
            val values = pieces(raw)
            if (values.size > 24) throw ResponseStatusException(HttpStatus.BAD_REQUEST, "$name 过多")
            values.forEach { if (it !in allowed) throw ResponseStatusException(HttpStatus.BAD_REQUEST, "$name 无效") }
            return values
        }

        private fun tokens(raw: String?, pattern: Regex, name: String): List<String> {
            val values = pieces(raw)
            if (values.size > 24) throw ResponseStatusException(HttpStatus.BAD_REQUEST, "$name 过多")
            values.forEach { if (!pattern.matches(it)) throw ResponseStatusException(HttpStatus.BAD_REQUEST, "$name 无效") }
            return values
        }

        private fun positives(raw: String?, name: String): List<Long> {
            val values = pieces(raw)
            if (values.size > 24) throw ResponseStatusException(HttpStatus.BAD_REQUEST, "$name 过多")
            return values.map { piece ->
                val value = piece.toLongOrNull()
                if (value == null || value <= 0L) throw ResponseStatusException(HttpStatus.BAD_REQUEST, "$name 无效")
                value
            }
        }

        private fun positive(value: Long?, name: String): Long? {
            if (value == null) return null
            if (value <= 0L) throw ResponseStatusException(HttpStatus.BAD_REQUEST, "$name 无效")
            return value
        }

        private fun year(value: Int?, name: String): Int? {
            if (value == null) return null
            if (value !in 1800..2200) throw ResponseStatusException(HttpStatus.BAD_REQUEST, "$name 无效")
            return value
        }

        private fun ratingMin(value: Double?): BigDecimal? {
            if (value == null) return null
            if (value < 0.0 || value > 100.0) throw ResponseStatusException(HttpStatus.BAD_REQUEST, "ratingMin 无效")
            return BigDecimal.valueOf(value)
        }

        private fun like(raw: String) = "%${raw.lowercase()}%"

        private fun likeGroup(param: String) = """
            LOWER(w.original_title) LIKE $param
            OR LOWER(w.collection_name) LIKE $param
            OR EXISTS (
              SELECT 1 FROM work_translations translation
              WHERE translation.work_id = w.id AND LOWER(translation.title) LIKE $param
            )
            OR EXISTS (
              SELECT 1 FROM library_files named
              WHERE named.work_id = w.id AND LOWER(named.file_name) LIKE $param
            )
            OR EXISTS (
              SELECT 1 FROM work_genres link
              JOIN genres genre ON genre.id = link.genre_id
              WHERE link.work_id = w.id AND LOWER(genre.name) LIKE $param
            )
            OR EXISTS (
              SELECT 1 FROM credits credit
              JOIN people person ON person.id = credit.person_id
              WHERE credit.owner_type = 'work' AND credit.owner_id = w.id AND LOWER(person.name) LIKE $param
            )
        """.trimIndent()

        private fun runtimeClause(bucket: String) = when (bucket) {
            "lt90" -> "w.runtime_minutes IS NOT NULL AND w.runtime_minutes < 90"
            "m90" -> "w.runtime_minutes >= 90 AND w.runtime_minutes < 120"
            "m120" -> "w.runtime_minutes >= 120 AND w.runtime_minutes < 150"
            else -> "w.runtime_minutes >= 150"
        }

        private fun statusClause(status: String) = when (status) {
            "airing" -> "(w.work_status IN ('Returning', 'Returning Series') OR w.in_production = 1)"
            "ended" -> "w.work_status = 'Ended'"
            else -> "w.work_status IN ('Canceled', 'Cancelled')"
        }

        private fun resolutionClause(resolution: String) = when (resolution) {
            "2160" -> "(ff.video_height >= 1400 OR ff.video_width >= 3000)"
            "1080" -> "((ff.video_height >= 900 AND ff.video_height < 1400) OR (ff.video_width >= 1600 AND ff.video_width < 3000 AND (ff.video_height IS NULL OR ff.video_height < 1400)))"
            "720" -> "((ff.video_height >= 500 AND ff.video_height < 900) OR (ff.video_width >= 1000 AND ff.video_width < 1600 AND (ff.video_height IS NULL OR ff.video_height < 900)))"
            else -> "((ff.video_height > 0 AND ff.video_height < 500) OR (ff.video_width > 0 AND ff.video_width < 1000 AND (ff.video_height IS NULL OR ff.video_height < 500)))"
        }

        private fun rangeClause(value: String, sql: Sql, index: Int): String {
            if (value.equals("sdr", true)) {
                return "ff.probed_at IS NOT NULL AND (ff.video_dynamic_range IS NULL OR ff.video_dynamic_range = '')"
            }
            val name = "dynamicRange$index"
            sql[name] = value
            return "ff.video_dynamic_range = :$name"
        }

        private fun emptyFacets() = WorkFacets(
            emptyList(), emptyList(), emptyList(), emptyList(), emptyList(), emptyList(),
            emptyList(), emptyList(), emptyList(), null, null, emptyList(),
        )

        private fun Any?.asLong() = (this as Number).toLong()

        private fun Any?.asBool(): Boolean = when (this) {
            null -> false
            is Boolean -> this
            is Number -> this.toInt() != 0
            else -> this.toString() == "1" || this.toString().equals("true", true)
        }
    }

    data class Normalized(
        val kind: String?,
        val sort: String,
        val watch: String?,
        val genreIds: List<Long>,
        val yearFrom: Int?,
        val yearTo: Int?,
        val ratingProvider: String?,
        val ratingMin: BigDecimal?,
        val countries: List<String>,
        val languages: List<String>,
        val runtimes: List<String>,
        val keywordIds: List<Long>,
        val personId: Long?,
        val companyIds: List<Long>,
        val collectionIds: List<String>,
        val inCollection: Boolean,
        val showStatuses: List<String>,
        val resolutions: List<String>,
        val dynamicRanges: List<String>,
        val videoCodecs: List<String>,
        val audioCodecs: List<String>,
        val subtitle: String?,
        val userId: Long?,
        val offset: Int,
        val limit: Int,
        val page: Int,
        val size: Int,
    )
}
