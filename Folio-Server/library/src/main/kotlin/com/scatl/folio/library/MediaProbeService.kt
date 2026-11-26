package com.scatl.folio.library

import com.scatl.folio.config.FolioProperties
import com.scatl.folio.dto.AudioTrackView
import com.scatl.folio.dto.SubtitleTrackView
import com.scatl.folio.entity.LibraryFile
import com.scatl.folio.repository.LibraryFileRepository
import org.slf4j.LoggerFactory
import org.springframework.boot.json.JsonParserFactory
import org.springframework.stereotype.Service
import org.springframework.transaction.PlatformTransactionManager
import org.springframework.transaction.support.TransactionTemplate
import java.math.BigDecimal
import java.math.RoundingMode
import java.io.ByteArrayOutputStream
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.Path
import java.time.Instant
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

@Service
open class MediaProbeService(
    private val files: LibraryFileRepository,
    private val properties: FolioProperties,
    transactionManager: PlatformTransactionManager,
) {
    private val log = LoggerFactory.getLogger(javaClass)
    private val missingBinaryLogged = AtomicBoolean(false)
    private val tx = TransactionTemplate(transactionManager)

    fun containerOf(fileName: String): String? {
        val ext = fileName.substringAfterLast('.', missingDelimiterValue = "").trim().lowercase()
        return ext.takeIf { it.isNotEmpty() }
    }

    fun probeAndSave(fileId: Long) {
        val snapshot = files.findById(fileId).orElse(null) ?: return
        val result = probe(snapshot.locator)
        tx.executeWithoutResult {
            val file = files.findById(fileId).orElse(null) ?: return@executeWithoutResult
            applyProbe(file, result)
        }
    }

    fun decodeAudio(raw: String?): List<AudioTrackView> =
        maps(raw).map { item ->
            AudioTrackView(
                text(item, "codec"),
                integer(item, "channels"),
                text(item, "language"),
                longValue(item, "bitrate"),
                integer(item, "sampleRate") ?: integer(item, "sample_rate"),
                text(item, "channelLayout") ?: text(item, "channel_layout"),
                text(item, "profile"),
            )
        }

    fun decodeSubtitles(raw: String?): List<SubtitleTrackView> =
        maps(raw).map { item ->
            SubtitleTrackView(text(item, "codec"), text(item, "language"))
        }

    private fun applyProbe(file: LibraryFile, result: ProbeResult?) {
        val fromName = containerOf(file.fileName)
        file.mediaContainer = result?.container ?: fromName
        file.durationMs = result?.durationMs
        file.videoCodec = result?.videoCodec
        file.videoWidth = result?.videoWidth
        file.videoHeight = result?.videoHeight
        file.videoFrameRate = result?.videoFrameRate
        file.videoBitrate = result?.videoBitrate
        file.videoBitDepth = result?.videoBitDepth
        file.videoDynamicRange = result?.videoDynamicRange
        file.videoProfile = result?.videoProfile
        file.videoPixelFormat = result?.videoPixelFormat
        file.audioTracks = encodeAudio(result?.audioTracks.orEmpty())
        file.subtitleTracks = encodeSubtitles(result?.subtitleTracks.orEmpty())
        if (result != null) {
            file.probedAt = Instant.now()
        }
        file.updatedAt = Instant.now()
    }

    private fun probe(locator: String): ProbeResult? {
        val path = Path.of(locator)
        if (!Files.isRegularFile(path)) {
            log.warn("探测跳过，文件不存在 locator={}", locator)
            return null
        }
        if (missingBinaryLogged.get()) return null
        val binary = properties.library.ffprobe.trim().ifBlank { "ffprobe" }
        val process = try {
            ProcessBuilder(
                binary,
                "-v", "error",
                "-probesize", "5M",
                "-analyzeduration", "5M",
                "-print_format", "json",
                "-show_format",
                "-show_streams",
                path.toString(),
            ).redirectError(ProcessBuilder.Redirect.DISCARD).start()
        } catch (ex: Exception) {
            if (missingBinaryLogged.compareAndSet(false, true)) {
                log.warn("未找到 ffprobe（{}），视频信息只保存容器和文件大小", binary)
            }
            return null
        }
        val output = ByteArrayOutputStream()
        val reader = Thread({
            process.inputStream.copyTo(output)
        }, "ffprobe-stdout")
        reader.isDaemon = true
        reader.start()
        val finished = process.waitFor(PROBE_TIMEOUT_SECONDS, TimeUnit.SECONDS)
        if (!finished) {
            process.destroyForcibly()
            reader.join(1000)
            log.warn("ffprobe 超时 locator={}", locator)
            return ProbeResult(container = containerOf(path.fileName.toString()))
        }
        reader.join(2000)
        val body = output.toString(StandardCharsets.UTF_8)
        if (process.exitValue() != 0) {
            log.warn("ffprobe 失败 locator={} code={} output={}", locator, process.exitValue(), body.take(300))
            return ProbeResult(container = containerOf(path.fileName.toString()))
        }
        return parse(body, path.fileName.toString())
    }

    private fun parse(body: String, fileName: String): ProbeResult {
        val root = parseMap(body)
        val format = map(root["format"])
        val streams = mapsValue(root["streams"])
        val video = streams.firstOrNull { stream ->
            text(stream, "codec_type") == "video" && integer(map(stream["disposition"]), "attached_pic") != 1
        }
        val audio = streams.filter { text(it, "codec_type") == "audio" }
        val subs = streams.filter { text(it, "codec_type") == "subtitle" }
        val durationSec = decimal(format, "duration")
        val formatBitrate = longValue(format, "bit_rate")
        val videoBitrate = video?.let { longValue(it, "bit_rate") } ?: formatBitrate
        return ProbeResult(
            container = containerOf(fileName) ?: formatName(text(format, "format_name")),
            durationMs = durationSec?.let { (it * 1000).toLong() },
            videoCodec = video?.let { text(it, "codec_name") },
            videoWidth = video?.let { integer(it, "width") }?.takeIf { it > 0 },
            videoHeight = video?.let { integer(it, "height") }?.takeIf { it > 0 },
            videoFrameRate = frameRate(video?.let { text(it, "avg_frame_rate") } ?: video?.let { text(it, "r_frame_rate") }),
            videoBitrate = videoBitrate?.takeIf { it > 0 },
            videoBitDepth = video?.let { integer(it, "bits_per_raw_sample") ?: integer(it, "bits_per_sample") }?.takeIf { it > 0 },
            videoDynamicRange = dynamicRange(video),
            videoProfile = video?.let { text(it, "profile") }?.takeIf { it.isNotBlank() && it != "unknown" },
            videoPixelFormat = video?.let { text(it, "pix_fmt") },
            audioTracks = audio.map { stream ->
                AudioTrackView(
                    text(stream, "codec_name"),
                    integer(stream, "channels")?.takeIf { it > 0 },
                    language(stream),
                    longValue(stream, "bit_rate")?.takeIf { it > 0 },
                    integer(stream, "sample_rate")?.takeIf { it > 0 },
                    text(stream, "channel_layout"),
                    text(stream, "profile")?.takeIf { it.isNotBlank() && it != "unknown" },
                )
            },
            subtitleTracks = subs.map { stream ->
                SubtitleTrackView(text(stream, "codec_name"), language(stream))
            },
        )
    }

    private fun formatName(raw: String?): String? {
        if (raw.isNullOrBlank()) return null
        val first = raw.split(',').first().trim().lowercase()
        return when (first) {
            "matroska", "webm" -> "mkv"
            "mpegts" -> "ts"
            "mov", "mp4", "m4a", "3gp", "3g2", "mj2" -> if (raw.contains("mp4")) "mp4" else first
            else -> first.take(32)
        }
    }

    private fun frameRate(raw: String?): BigDecimal? {
        if (raw.isNullOrBlank() || raw == "0/0" || raw == "N/A") return null
        val value = if ('/' in raw) {
            val left = raw.substringBefore('/').toDoubleOrNull() ?: return null
            val right = raw.substringAfter('/').toDoubleOrNull() ?: return null
            if (right == 0.0) return null
            left / right
        } else {
            raw.toDoubleOrNull() ?: return null
        }
        return BigDecimal.valueOf(value).setScale(3, RoundingMode.HALF_UP)
    }

    private fun dynamicRange(video: Map<String, Any?>?): String? {
        if (video == null) return null
        for (item in mapsValue(video["side_data_list"])) {
            val type = text(item, "side_data_type").orEmpty()
            if (type.contains("DOVI", ignoreCase = true) || type.contains("Dolby Vision", ignoreCase = true)) {
                return "Dolby Vision"
            }
        }
        val transfer = text(video, "color_transfer").orEmpty()
        return when {
            transfer.contains("smpte2084", ignoreCase = true) -> "HDR10"
            transfer.contains("arib-std-b67", ignoreCase = true) || transfer.contains("hlg", ignoreCase = true) -> "HLG"
            else -> null
        }
    }

    private fun language(stream: Map<String, Any?>): String? {
        val tags = map(stream["tags"])
        val value = text(tags, "language") ?: text(tags, "LANGUAGE")
        return value?.takeIf { it != "und" }
    }

    private fun encodeAudio(tracks: List<AudioTrackView>): String? {
        if (tracks.isEmpty()) return null
        return tracks.joinToString(",", "[", "]") { track ->
            """{"codec":${json(track.codec)},"channels":${track.channels ?: "null"},"language":${json(track.language)},"bitrate":${track.bitrate ?: "null"},"sampleRate":${track.sampleRate ?: "null"},"channelLayout":${json(track.channelLayout)},"profile":${json(track.profile)}}"""
        }
    }

    private fun encodeSubtitles(tracks: List<SubtitleTrackView>): String? {
        if (tracks.isEmpty()) return null
        return tracks.joinToString(",", "[", "]") { track ->
            """{"codec":${json(track.codec)},"language":${json(track.language)}}"""
        }
    }

    private fun json(value: String?): String {
        if (value == null) return "null"
        return "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"") + "\""
    }

    private fun parseMap(body: String): Map<String, Any?> = try {
        @Suppress("UNCHECKED_CAST")
        JsonParserFactory.getJsonParser().parseMap(body) as Map<String, Any?>
    } catch (_: RuntimeException) {
        emptyMap()
    }

    private fun maps(raw: String?): List<Map<String, Any?>> {
        if (raw.isNullOrBlank()) return emptyList()
        return try {
            mapsValue(JsonParserFactory.getJsonParser().parseList(raw))
        } catch (_: RuntimeException) {
            emptyList()
        }
    }

    private fun map(value: Any?): Map<String, Any?> {
        val raw = value as? Map<*, *> ?: return emptyMap()
        return raw.entries.associate { it.key.toString() to it.value }
    }

    private fun mapsValue(value: Any?): List<Map<String, Any?>> {
        val list = value as? List<*> ?: return emptyList()
        return list.mapNotNull { item ->
            if (item is Map<*, *>) item.entries.associate { it.key.toString() to it.value } else null
        }
    }

    private fun text(map: Map<String, Any?>, key: String): String? {
        val value = map[key] ?: return null
        val text = value.toString().trim()
        return if (text.isEmpty() || text == "null") null else text
    }

    private fun integer(map: Map<String, Any?>, key: String): Int? = when (val value = map[key]) {
        is Number -> value.toInt()
        is String -> value.trim().toIntOrNull()
        else -> null
    }

    private fun decimal(map: Map<String, Any?>, key: String): Double? = when (val value = map[key]) {
        is Number -> value.toDouble()
        is String -> value.trim().toDoubleOrNull()
        else -> null
    }

    private fun longValue(map: Map<String, Any?>, key: String): Long? = when (val value = map[key]) {
        is Number -> value.toLong()
        is String -> value.trim().toLongOrNull()
        else -> null
    }

    private data class ProbeResult(
        val container: String?,
        val durationMs: Long? = null,
        val videoCodec: String? = null,
        val videoWidth: Int? = null,
        val videoHeight: Int? = null,
        val videoFrameRate: BigDecimal? = null,
        val videoBitrate: Long? = null,
        val videoBitDepth: Int? = null,
        val videoDynamicRange: String? = null,
        val videoProfile: String? = null,
        val videoPixelFormat: String? = null,
        val audioTracks: List<AudioTrackView> = emptyList(),
        val subtitleTracks: List<SubtitleTrackView> = emptyList(),
    )

    private companion object {
        const val PROBE_TIMEOUT_SECONDS = 20L
    }
}
