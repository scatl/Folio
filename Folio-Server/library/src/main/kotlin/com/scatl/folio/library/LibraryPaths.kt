package com.scatl.folio.library

import java.nio.file.Path
import java.security.MessageDigest
import kotlin.io.path.isDirectory
import kotlin.io.path.name

object LibraryPaths {
    private val VIDEO_EXTENSIONS = setOf(
        "mkv", "mp4", "avi", "m4v", "ts", "m2ts", "wmv", "mov", "webm", "mpg", "mpeg",
    )

    private val SUBTITLE_EXTENSIONS = setOf(
        "srt", "ass", "ssa", "vtt", "sub", "smi",
    )

    fun locatorHash(locator: String): String {
        val normalized = locator.replace('\\', '/')
        val digest = MessageDigest.getInstance("SHA-256").digest(normalized.toByteArray(Charsets.UTF_8))
        return digest.joinToString("") { "%02x".format(it) }
    }

    fun displayPath(path: Path): String =
        path.toAbsolutePath().normalize().toString().replace('\\', '/')

    fun parentLocator(locator: String): String {
        val normalized = locator.replace('\\', '/')
        val slash = normalized.lastIndexOf('/')
        return if (slash <= 0) "" else normalized.substring(0, slash)
    }

    fun isVideoFile(path: Path): Boolean {
        val fileName = path.fileName?.toString() ?: return false
        val ext = fileName.substringAfterLast('.', missingDelimiterValue = "").lowercase()
        return ext in VIDEO_EXTENSIONS
    }

    fun isSubtitleFileName(fileName: String): Boolean {
        val ext = fileName.substringAfterLast('.', missingDelimiterValue = "").lowercase()
        return ext in SUBTITLE_EXTENSIONS
    }

    /** 仅允许同目录下的字幕文件名，拒绝路径穿越。 */
    fun isSafeSiblingSubtitleName(name: String): Boolean {
        if (name.isBlank() || name.length > 512) return false
        if (name.contains('/') || name.contains('\\')) return false
        if (name == "." || name == ".." || name.contains("..")) return false
        return isSubtitleFileName(name)
    }

    fun isPartial(fileName: String): Boolean {
        val lower = fileName.lowercase()
        return lower.endsWith(".part") ||
            lower.endsWith(".tmp") ||
            lower.endsWith(".download") ||
            lower.contains(".!qb")
    }

    /** 容器内片库必须挂载到这里；浏览和扫库都只允许这个根目录。 */
    val mediaRoot: Path = Path.of("/media").toAbsolutePath().normalize()

    fun mediaRoots(): List<Path> =
        listOf(mediaRoot).filter { it.isDirectory() }

    fun isUnderMediaRoots(path: Path): Boolean {
        val normalized = path.toAbsolutePath().normalize()
        return normalized == mediaRoot || normalized.startsWith(mediaRoot)
    }
}
