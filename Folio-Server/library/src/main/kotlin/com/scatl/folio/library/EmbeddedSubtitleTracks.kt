package com.scatl.folio.library

import com.scatl.folio.dto.EmbeddedSubtitleView
import org.springframework.boot.json.JsonParserFactory

internal val TEXT_SUBTITLE_CODECS = setOf(
    "ass",
    "ssa",
    "subrip",
    "srt",
    "text",
    "mov_text",
    "webvtt",
    "subviewer",
    "subviewer1",
    "microdvd",
    "mpl2",
    "sami",
    "realtext",
    "jacosub",
    "stl",
    "pjs",
    "vplayer",
    "aqt",
    "ttml",
    "lrc",
)

internal fun isTextSubtitleCodec(codec: String?): Boolean {
    val name = codec?.trim()?.lowercase().orEmpty()
    return name in TEXT_SUBTITLE_CODECS
}

/** 只保留 ffmpeg 能转成 ASS 的文本轨。index 是字幕流序号，对应 `-map 0:s:N`。 */
internal fun parseEmbeddedSubtitles(body: String): List<EmbeddedSubtitleView> {
    val root = parseMap(body)
    val streams = mapsValue(root["streams"])
    val out = mutableListOf<EmbeddedSubtitleView>()
    streams.forEachIndexed { ordinal, stream ->
        val type = text(stream, "codec_type")
        if (type != null && type != "subtitle") return@forEachIndexed
        val codec = text(stream, "codec_name")
        if (!isTextSubtitleCodec(codec)) return@forEachIndexed
        val tags = map(stream["tags"])
        out += EmbeddedSubtitleView(
            index = ordinal,
            codec = codec,
            language = language(tags),
            title = text(tags, "title") ?: text(tags, "TITLE"),
        )
    }
    return out
}

private fun language(tags: Map<String, Any?>): String? {
    val value = text(tags, "language") ?: text(tags, "LANGUAGE")
    return value?.takeIf { !it.equals("und", ignoreCase = true) }
}

private fun parseMap(body: String): Map<String, Any?> = try {
    @Suppress("UNCHECKED_CAST")
    JsonParserFactory.getJsonParser().parseMap(body) as Map<String, Any?>
} catch (_: RuntimeException) {
    emptyMap()
}

private fun mapsValue(value: Any?): List<Map<String, Any?>> {
    val list = value as? List<*> ?: return emptyList()
    return list.mapNotNull { item ->
        if (item is Map<*, *>) item.entries.associate { it.key.toString() to it.value } else null
    }
}

private fun map(value: Any?): Map<String, Any?> {
    val raw = value as? Map<*, *> ?: return emptyMap()
    return raw.entries.associate { it.key.toString() to it.value }
}

private fun text(map: Map<String, Any?>, key: String): String? {
    val value = map[key] ?: return null
    val text = value.toString().trim()
    return if (text.isEmpty() || text == "null") null else text
}
