package com.scatl.folio.logs

import org.springframework.http.HttpStatus
import org.springframework.web.server.ResponseStatusException
import java.io.BufferedReader
import java.io.IOException
import java.io.InputStream
import java.io.InputStreamReader
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.Path
import java.util.zip.GZIPInputStream
import java.util.zip.ZipException

/**
 * 服务端日志在容器里落在 [logging.file.name] 的目录，默认 `/data/logs`。
 * 当天是明文 `folio.log`，更早的由 Logback 滚成 `folio.log.yyyy-MM-dd.i.gz`。
 * 读 `.gz` 时先解压，之后和未压缩文件一样按行取文本。
 */
object ServerLogFiles {
    const val MAX_LINES = 8000

    private val namePattern = Regex("""^folio\.log(?:\.(\d{4}-\d{2}-\d{2})\.(\d+)(?:\.gz)?)?$""")

    fun resolveDirectory(configuredFile: String, isDirectory: (Path) -> Boolean = Files::isDirectory): Path? {
        if (configuredFile.isNotBlank()) {
            val parent = Path.of(configuredFile).parent
            if (parent != null) return parent
        }
        val logs = Path.of("/data/logs")
        val log = Path.of("/data/log")
        return when {
            isDirectory(logs) -> logs
            isDirectory(log) -> log
            else -> null
        }
    }

    fun list(directory: Path): List<ServerLogFileView> {
        val realDir = directory.toRealPath()
        val entries = Files.list(realDir).use { stream ->
            stream.toList().mapNotNull { listed(realDir, it) }
        }
        return entries
            .sortedWith(
                compareByDescending<Listed> { it.date ?: "9999-12-31" }
                    .thenByDescending { it.index },
            )
            .map { it.view }
    }

    fun read(directory: Path, name: String, maxLines: Int = MAX_LINES): ServerLogContentView {
        val meta = parse(name) ?: throw ResponseStatusException(HttpStatus.BAD_REQUEST, "日志文件名无效")
        val realDir = try {
            directory.toRealPath()
        } catch (_: IOException) {
            throw ResponseStatusException(HttpStatus.NOT_FOUND, "日志目录不存在")
        }
        val file = realDir.resolve(meta.name)
        if (!Files.isRegularFile(file)) {
            throw ResponseStatusException(HttpStatus.NOT_FOUND, "日志文件不存在")
        }
        val realFile = file.toRealPath()
        if (realFile.parent != realDir) {
            throw ResponseStatusException(HttpStatus.BAD_REQUEST, "日志文件无效")
        }
        val tail = try {
            open(realFile, meta.compressed).use { tailLines(it, maxLines) }
        } catch (_: ZipException) {
            throw ResponseStatusException(HttpStatus.BAD_REQUEST, "日志压缩文件无法解压")
        }
        return ServerLogContentView(
            name = meta.name,
            label = meta.label,
            size = Files.size(realFile),
            compressed = meta.compressed,
            modifiedAt = Files.getLastModifiedTime(realFile).toInstant().toString(),
            truncated = tail.truncated,
            lineCount = tail.lines.size,
            totalLines = tail.total,
            text = tail.lines.joinToString("\n"),
        )
    }

    private fun listed(realDir: Path, path: Path): Listed? {
        val name = path.fileName?.toString() ?: return null
        val meta = parse(name) ?: return null
        val real = try {
            path.toRealPath()
        } catch (_: IOException) {
            return null
        }
        if (real.parent != realDir || !Files.isRegularFile(real)) return null
        return Listed(
            view = ServerLogFileView(
                name = meta.name,
                label = meta.label,
                size = Files.size(real),
                compressed = meta.compressed,
                modifiedAt = Files.getLastModifiedTime(real).toInstant().toString(),
            ),
            date = meta.date,
            index = meta.index,
        )
    }

    private fun parse(name: String): Parsed? {
        val match = namePattern.matchEntire(name) ?: return null
        val date = match.groupValues[1].ifEmpty { null }
        val index = match.groupValues[2].toIntOrNull() ?: Int.MAX_VALUE
        val label = when {
            date == null -> "今天"
            index == 0 -> date
            else -> "$date #$index"
        }
        return Parsed(
            name = name,
            date = date,
            index = index,
            compressed = name.endsWith(".gz"),
            label = label,
        )
    }

    private fun open(file: Path, compressed: Boolean): BufferedReader {
        val raw: InputStream = Files.newInputStream(file)
        val input = try {
            if (compressed) GZIPInputStream(raw) else raw
        } catch (exception: IOException) {
            raw.close()
            throw exception
        }
        val decoder = StandardCharsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.REPLACE)
            .onUnmappableCharacter(CodingErrorAction.REPLACE)
        return InputStreamReader(input, decoder).buffered()
    }

    private fun tailLines(reader: BufferedReader, maxLines: Int): Tail {
        val kept = ArrayDeque<String>(maxLines.coerceAtLeast(1))
        var total = 0
        reader.forEachLine { line ->
            total += 1
            if (kept.size == maxLines) kept.removeFirst()
            kept.addLast(line)
        }
        return Tail(lines = kept.toList(), total = total, truncated = total > kept.size)
    }

    private data class Parsed(
        val name: String,
        val date: String?,
        val index: Int,
        val compressed: Boolean,
        val label: String,
    )

    private data class Listed(
        val view: ServerLogFileView,
        val date: String?,
        val index: Int,
    )

    private data class Tail(
        val lines: List<String>,
        val total: Int,
        val truncated: Boolean,
    )
}

data class ServerLogFileView(
    val name: String,
    val label: String,
    val size: Long,
    val compressed: Boolean,
    val modifiedAt: String,
)

data class ServerLogListView(
    val directory: String?,
    val available: Boolean,
    val message: String?,
    val files: List<ServerLogFileView>,
)

data class ServerLogContentView(
    val name: String,
    val label: String,
    val size: Long,
    val compressed: Boolean,
    val modifiedAt: String,
    val truncated: Boolean,
    val lineCount: Int,
    val totalLines: Int,
    val text: String,
)
