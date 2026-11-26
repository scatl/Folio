package com.scatl.folio.logs

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import org.springframework.web.server.ResponseStatusException
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.Path
import java.util.zip.GZIPOutputStream

class ServerLogFilesTest {
    @TempDir
    lateinit var directory: Path

    @Test
    fun listsTodayThenArchivesAndSkipsOtherFiles() {
        Files.writeString(directory.resolve("folio.log"), "today\n")
        writeGz(directory.resolve("folio.log.2026-10-25.0.gz"), "gzipped\n")
        Files.writeString(directory.resolve("folio.log.2026-10-24.0"), "plain archive\n")
        Files.writeString(directory.resolve("notes.txt"), "nope\n")

        val names = ServerLogFiles.list(directory).map { it.name }

        assertEquals(
            listOf("folio.log", "folio.log.2026-10-25.0.gz", "folio.log.2026-10-24.0"),
            names,
        )
        val gzip = ServerLogFiles.list(directory).first { it.name.endsWith(".gz") }
        assertTrue(gzip.compressed)
        assertEquals("2026-10-25", gzip.label)
        val plain = ServerLogFiles.list(directory).first { it.name.endsWith(".0") && !it.name.endsWith(".gz") }
        assertFalse(plain.compressed)
    }

    @Test
    fun readsGzipAndPlainArchivesAsText() {
        writeGz(directory.resolve("folio.log.2026-10-25.0.gz"), "yesterday line\n")
        Files.writeString(directory.resolve("folio.log.2026-10-24.0"), "plain archive\n")

        val gzip = ServerLogFiles.read(directory, "folio.log.2026-10-25.0.gz")
        assertEquals("yesterday line", gzip.text)
        assertTrue(gzip.compressed)
        assertFalse(gzip.truncated)

        val plain = ServerLogFiles.read(directory, "folio.log.2026-10-24.0")
        assertEquals("plain archive", plain.text)
        assertFalse(plain.compressed)
    }

    @Test
    fun keepsOnlyTheTail() {
        val body = (1..5).joinToString("\n") { "line $it" } + "\n"
        Files.writeString(directory.resolve("folio.log"), body)

        val content = ServerLogFiles.read(directory, "folio.log", maxLines = 2)

        assertEquals("line 4\nline 5", content.text)
        assertTrue(content.truncated)
        assertEquals(2, content.lineCount)
        assertEquals(5, content.totalLines)
    }

    @Test
    fun rejectsNamesOutsideTheLogDirectory() {
        Files.writeString(directory.resolve("folio.log"), "today\n")

        assertThrows(ResponseStatusException::class.java) {
            ServerLogFiles.read(directory, "../folio.log")
        }
        assertThrows(ResponseStatusException::class.java) {
            ServerLogFiles.read(directory, "folio.log.2026-10-25.0.gz/../../secret")
        }
        assertThrows(ResponseStatusException::class.java) {
            ServerLogFiles.read(directory, "notes.txt")
        }
    }

    @Test
    fun resolvesConfiguredDirectoryThenFallbacks() {
        assertEquals(Path.of("/data/logs"), ServerLogFiles.resolveDirectory("/data/logs/folio.log") { false })
        assertEquals(Path.of("/data/log"), ServerLogFiles.resolveDirectory("/data/log/folio.log") { false })
        assertEquals(Path.of("/data/logs"), ServerLogFiles.resolveDirectory("") { it == Path.of("/data/logs") })
        assertEquals(Path.of("/data/log"), ServerLogFiles.resolveDirectory("") { it == Path.of("/data/log") })
        assertNull(ServerLogFiles.resolveDirectory("") { false })
    }

    private fun writeGz(path: Path, text: String) {
        GZIPOutputStream(Files.newOutputStream(path)).use { gzip ->
            gzip.write(text.toByteArray(StandardCharsets.UTF_8))
        }
    }
}
