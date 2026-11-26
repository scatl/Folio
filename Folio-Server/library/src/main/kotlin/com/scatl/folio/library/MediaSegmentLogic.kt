package com.scatl.folio.library

data class MediaSegment(
    val kind: String,
    val startMs: Long,
    val endMs: Long?,
)

object MediaSegmentLogic {
    const val INTRO = "intro"
    const val RECAP = "recap"
    const val CREDITS = "credits"
    const val PREVIEW = "preview"
    const val POST_CREDITS = "post_credits"

    private val kindOrder = listOf(INTRO, RECAP, CREDITS, PREVIEW, POST_CREDITS)
    private const val MIN_MS = 5_000L
    private const val INTRO_MAX_MS = 10 * 60_000L
    private const val CREDITS_MAX_MS = 20 * 60_000L
    private const val POST_MAX_MS = 15 * 60_000L
    private const val LATE_START_MS = 60_000L

    /** TheIntroDB v4 的查询名是蛇形。驼峰的 tmdbId / imdbId 会直接 400。 */
    fun theIntroDbQuery(
        movie: Boolean,
        tmdbId: Long?,
        imdbId: String?,
        season: Int?,
        episode: Int?,
        durationMs: Long?,
    ): Map<String, Any?>? {
        val query = linkedMapOf<String, Any?>()
        when {
            tmdbId != null -> query["tmdb_id"] = tmdbId
            !imdbId.isNullOrBlank() -> query["imdb_id"] = imdbId
            else -> return null
        }
        if (!movie && season != null && episode != null) {
            query["season"] = season
            query["episode"] = episode
        }
        if (durationMs != null && durationMs > 0) query["duration_ms"] = durationMs
        return query
    }

    fun durationBucket(durationMs: Long?): Int {
        if (durationMs == null || durationMs <= 0) return 0
        return ((durationMs + 30_000L) / 60_000L).toInt().coerceIn(1, 100_000)
    }

    fun fromTheIntroDb(root: Map<String, Any?>): List<MediaSegment> {
        return listOf(
            ranges(root["intro"], INTRO, requireEnd = true),
            ranges(root["recap"], RECAP, requireEnd = true),
            ranges(root["credits"], CREDITS, requireEnd = false),
            ranges(root["preview"], PREVIEW, requireEnd = false),
        ).flatten()
    }

    fun fromIntroDb(root: Map<String, Any?>): List<MediaSegment> {
        return listOfNotNull(
            one(root["intro"], INTRO, requireEnd = true),
            one(root["recap"], RECAP, requireEnd = true),
            one(root["outro"], CREDITS, requireEnd = false),
            one(root["post_credits"], POST_CREDITS, requireEnd = true),
        )
    }

    /** 同一段以先到的来源为准，缺的段用后一个来源补。 */
    fun merge(primary: List<MediaSegment>, extra: List<MediaSegment>): List<MediaSegment> {
        val have = primary.map { it.kind }.toSet()
        return (primary + extra.filter { it.kind !in have })
            .sortedWith(compareBy({ kindOrder.indexOf(it.kind).let { index -> if (index < 0) kindOrder.size else index } }, { it.startMs }))
    }

    private fun ranges(value: Any?, kind: String, requireEnd: Boolean): List<MediaSegment> {
        val list = value as? List<*> ?: return emptyList()
        return list.mapNotNull { item ->
            val row = asMap(item) ?: return@mapNotNull null
            accept(kind, millis(row, "start_ms") ?: 0L, endMillis(row, "end_ms"), requireEnd)
        }
    }

    private fun one(value: Any?, kind: String, requireEnd: Boolean): MediaSegment? {
        val row = asMap(value) ?: return null
        if (row.isEmpty()) return null
        val start = millis(row, "start_ms") ?: seconds(row, "start_sec") ?: return null
        val end = if (row.containsKey("end_ms") || row.containsKey("end_sec")) {
            millis(row, "end_ms") ?: seconds(row, "end_sec")
        } else {
            null
        }
        return accept(kind, start, end, requireEnd)
    }

    private fun accept(kind: String, start: Long, end: Long?, requireEnd: Boolean): MediaSegment? {
        if (start < 0) return null
        if (requireEnd && end == null) return null
        if (end != null && end <= start) return null
        val length = if (end == null) null else end - start
        if (length != null && length < MIN_MS) return null
        when (kind) {
            INTRO, RECAP -> if (length == null || length > INTRO_MAX_MS) return null
            CREDITS, PREVIEW -> {
                if (start < LATE_START_MS) return null
                if (length != null && length > CREDITS_MAX_MS) return null
            }
            POST_CREDITS -> {
                if (start < LATE_START_MS || length == null || length > POST_MAX_MS) return null
            }
            else -> return null
        }
        return MediaSegment(kind, start, end)
    }

    private fun endMillis(row: Map<String, Any?>, key: String): Long? {
        if (!row.containsKey(key) || row[key] == null) return null
        return millis(row, key)
    }

    private fun asMap(value: Any?): Map<String, Any?>? {
        val raw = value as? Map<*, *> ?: return null
        return raw.entries.associate { it.key.toString() to it.value }
    }

    private fun millis(map: Map<String, Any?>, key: String): Long? = when (val value = map[key]) {
        is Number -> value.toLong()
        is String -> value.trim().toLongOrNull()
        else -> null
    }

    private fun seconds(map: Map<String, Any?>, key: String): Long? = when (val value = map[key]) {
        is Number -> (value.toDouble() * 1000.0).toLong()
        is String -> value.trim().toDoubleOrNull()?.let { (it * 1000.0).toLong() }
        else -> null
    }
}
