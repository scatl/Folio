package com.scatl.folio.library

import com.scatl.folio.config.FolioProperties
import com.scatl.folio.dto.EmbeddedSubtitleView
import com.scatl.folio.repository.LibraryFileRepository
import org.slf4j.LoggerFactory
import org.springframework.http.HttpStatus
import org.springframework.stereotype.Service
import org.springframework.web.server.ResponseStatusException
import java.io.ByteArrayOutputStream
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.Path
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit

@Service
class EmbeddedSubtitleService(
    private val files: LibraryFileRepository,
    private val properties: FolioProperties,
) {
    private val log = LoggerFactory.getLogger(javaClass)
    private val tracks = object : LinkedHashMap<String, List<EmbeddedSubtitleView>>(32, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, List<EmbeddedSubtitleView>>) = size > 64
    }
    private val extracted = object : LinkedHashMap<String, ByteArray>(16, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, ByteArray>) = size > 24
    }
    private val locks = ConcurrentHashMap<String, Any>()

    fun list(fileId: Long): List<EmbeddedSubtitleView> {
        val path = videoPath(fileId)
        val key = cacheKey(path)
        synchronized(tracks) {
            tracks[key]?.let { return it }
        }
        val json = runProbe(path) ?: return emptyList()
        val parsed = parseEmbeddedSubtitles(json)
        synchronized(tracks) {
            tracks[key] = parsed
        }
        return parsed
    }

    fun extract(fileId: Long, index: Int): ByteArray {
        if (index < 0) throw ResponseStatusException(HttpStatus.BAD_REQUEST, "无效的字幕轨")
        val path = videoPath(fileId)
        val key = cacheKey(path)
        val track = list(fileId).firstOrNull { it.index == index }
            ?: throw ResponseStatusException(HttpStatus.NOT_FOUND, "这条字幕不是文本格式")
        val extractKey = "$key#$index"
        synchronized(extracted) {
            extracted[extractKey]?.let { return it }
        }
        val lock = locks.computeIfAbsent(extractKey) { Any() }
        return synchronized(lock) {
            val cached = synchronized(extracted) { extracted[extractKey] }
            if (cached != null) return@synchronized cached
            val produced = runFfmpeg(path, track.index)
            synchronized(extracted) {
                extracted[extractKey] = produced
            }
            produced
        }
    }

    private fun videoPath(fileId: Long): Path {
        val row = files.findById(fileId).orElseThrow {
            ResponseStatusException(HttpStatus.NOT_FOUND, "文件不存在")
        }
        val path = Path.of(row.locator).toAbsolutePath().normalize()
        if (!Files.isRegularFile(path)) {
            throw ResponseStatusException(HttpStatus.NOT_FOUND, "文件不存在")
        }
        return path
    }

    private fun cacheKey(path: Path): String {
        val size = Files.size(path)
        val modified = Files.getLastModifiedTime(path).toMillis()
        return "$path|$size|$modified"
    }

    private fun runProbe(path: Path): String? {
        val binary = properties.library.ffprobe.trim().ifBlank { "ffprobe" }
        val process = try {
            ProcessBuilder(
                binary,
                "-v", "error",
                "-select_streams", "s",
                "-show_entries", "stream=codec_name,codec_type:stream_tags=language,title",
                "-of", "json",
                path.toString(),
            ).redirectError(ProcessBuilder.Redirect.DISCARD).start()
        } catch (ex: Exception) {
            log.warn("未找到 ffprobe（{}）", binary)
            return null
        }
        val output = ByteArrayOutputStream()
        val reader = Thread({
            process.inputStream.copyTo(output)
        }, "embedded-subtitle-ffprobe")
        reader.isDaemon = true
        reader.start()
        val finished = process.waitFor(PROBE_TIMEOUT_SECONDS, TimeUnit.SECONDS)
        if (!finished) {
            process.destroyForcibly()
            reader.join(1000)
            log.warn("ffprobe 超时 path={}", path.fileName)
            return null
        }
        reader.join(2000)
        if (process.exitValue() != 0) {
            log.warn("ffprobe 失败 path={} code={}", path.fileName, process.exitValue())
            return null
        }
        return output.toString(StandardCharsets.UTF_8)
    }

    private fun runFfmpeg(path: Path, index: Int): ByteArray {
        val binary = properties.library.ffmpeg.trim().ifBlank { "ffmpeg" }
        val output = Files.createTempFile("folio-sub-", ".ass")
        try {
            val process = try {
                ProcessBuilder(
                    binary,
                    "-nostdin",
                    "-hide_banner",
                    "-loglevel", "error",
                    "-y",
                    "-i", path.toString(),
                    "-map", "0:s:$index",
                    "-c:s", "ass",
                    "-f", "ass",
                    output.toString(),
                ).redirectError(ProcessBuilder.Redirect.DISCARD).start()
            } catch (ex: Exception) {
                throw ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE, "未找到 ffmpeg")
            }
            val finished = process.waitFor(EXTRACT_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            if (!finished) {
                process.destroyForcibly()
                throw ResponseStatusException(HttpStatus.GATEWAY_TIMEOUT, "字幕抽出超时")
            }
            if (process.exitValue() != 0 || !Files.isRegularFile(output)) {
                throw ResponseStatusException(HttpStatus.BAD_GATEWAY, "字幕抽出失败")
            }
            val size = Files.size(output)
            if (size <= 0) throw ResponseStatusException(HttpStatus.BAD_GATEWAY, "字幕抽出失败")
            if (size > MAX_BYTES) throw ResponseStatusException(HttpStatus.PAYLOAD_TOO_LARGE, "字幕文件过大")
            return Files.readAllBytes(output)
        } finally {
            Files.deleteIfExists(output)
        }
    }

    private companion object {
        const val PROBE_TIMEOUT_SECONDS = 20L
        const val EXTRACT_TIMEOUT_SECONDS = 60L
        const val MAX_BYTES = 5L * 1024 * 1024
    }
}
