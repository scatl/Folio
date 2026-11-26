package com.scatl.folio.library

import com.scatl.folio.repository.LibraryFileRepository
import org.springframework.http.HttpStatus
import org.springframework.stereotype.Service
import org.springframework.web.server.ResponseStatusException
import java.nio.file.Files
import java.nio.file.Path
import kotlin.streams.asSequence

@Service
class ExternalSubtitleService(
    private val files: LibraryFileRepository,
) {
    fun listNames(fileId: Long): List<String> {
        val dir = videoPath(fileId).parent ?: return emptyList()
        if (!Files.isDirectory(dir)) return emptyList()
        return Files.list(dir).use { stream ->
            stream.asSequence()
                .filter { Files.isRegularFile(it) }
                .mapNotNull { it.fileName?.toString() }
                .filter { LibraryPaths.isSubtitleFileName(it) }
                .sorted()
                .toList()
        }
    }

    fun resolve(fileId: Long, name: String): Path {
        if (!LibraryPaths.isSafeSiblingSubtitleName(name)) {
            throw ResponseStatusException(HttpStatus.BAD_REQUEST, "无效的字幕文件名")
        }
        val video = videoPath(fileId)
        val parent = video.parent
            ?: throw ResponseStatusException(HttpStatus.NOT_FOUND, "字幕不存在")
        val parentNorm = parent.toAbsolutePath().normalize()
        val target = parentNorm.resolve(name).normalize()
        if (target.parent != parentNorm) {
            throw ResponseStatusException(HttpStatus.BAD_REQUEST, "无效的字幕文件名")
        }
        if (!Files.isRegularFile(target)) {
            throw ResponseStatusException(HttpStatus.NOT_FOUND, "字幕不存在")
        }
        val size = Files.size(target)
        if (size > MAX_BYTES) {
            throw ResponseStatusException(HttpStatus.PAYLOAD_TOO_LARGE, "字幕文件过大")
        }
        return target
    }

    private fun videoPath(fileId: Long): Path {
        val row = files.findById(fileId)
            .orElseThrow { ResponseStatusException(HttpStatus.NOT_FOUND, "文件不存在") }
        val path = Path.of(row.locator).toAbsolutePath().normalize()
        if (!Files.isRegularFile(path)) {
            throw ResponseStatusException(HttpStatus.NOT_FOUND, "文件不存在")
        }
        return path
    }

    companion object {
        private const val MAX_BYTES = 5L * 1024 * 1024
    }
}
