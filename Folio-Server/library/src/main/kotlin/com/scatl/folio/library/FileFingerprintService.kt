package com.scatl.folio.library

import com.scatl.folio.catalog.SavedRef
import com.scatl.folio.entity.FileFingerprint
import com.scatl.folio.repository.FileFingerprintRepository
import com.scatl.folio.repository.LibraryFileRepository
import org.slf4j.LoggerFactory
import org.springframework.boot.context.event.ApplicationReadyEvent
import org.springframework.context.event.EventListener
import org.springframework.dao.DataIntegrityViolationException
import org.springframework.data.domain.PageRequest
import org.springframework.stereotype.Service
import org.springframework.transaction.PlatformTransactionManager
import org.springframework.transaction.support.TransactionTemplate
import java.nio.ByteBuffer
import java.nio.channels.FileChannel
import java.nio.file.Path
import java.nio.file.StandardOpenOption
import java.security.MessageDigest
import java.time.Instant
import kotlin.concurrent.thread
import kotlin.io.path.isRegularFile

data class ContentFingerprint(
    val fileSize: Long,
    val contentHash: String,
)

@Service
open class FileFingerprintService(
    private val fingerprints: FileFingerprintRepository,
    private val files: LibraryFileRepository,
    transactionManager: PlatformTransactionManager,
) {
    private val log = LoggerFactory.getLogger(javaClass)
    private val tx = TransactionTemplate(transactionManager)

    @EventListener(ApplicationReadyEvent::class)
    fun backfillOnReady() {
        thread(name = "fingerprint-backfill", isDaemon = true) {
            try {
                backfill()
            } catch (ex: Exception) {
                log.warn("文件特征值补算失败 reason={}", ex.message)
            }
        }
    }

    fun lookup(locator: String): Pair<ContentFingerprint, SavedRef?>? {
        val computed = compute(Path.of(locator)) ?: return null
        val saved = fingerprints.findByFileSizeAndContentHash(computed.fileSize, computed.contentHash)
            ?.let { SavedRef(it.workId, it.episodeId) }
        return computed to saved
    }

    fun remember(fileId: Long, workId: Long, episodeId: Long?, computed: ContentFingerprint? = null): Boolean {
        val file = files.findById(fileId).orElse(null) ?: return false
        val fingerprint = computed ?: compute(Path.of(file.locator)) ?: return false
        return try {
            store(fileId, workId, episodeId, fingerprint)
        } catch (_: DataIntegrityViolationException) {
            store(fileId, workId, episodeId, fingerprint)
        }
    }

    private fun store(fileId: Long, workId: Long, episodeId: Long?, fingerprint: ContentFingerprint): Boolean {
        var stored = false
        tx.executeWithoutResult {
            val current = files.findById(fileId).orElse(null) ?: return@executeWithoutResult
            val now = Instant.now()
            val existing = fingerprints.findByFileSizeAndContentHash(fingerprint.fileSize, fingerprint.contentHash)
            if (existing == null) {
                fingerprints.saveAndFlush(FileFingerprint().apply {
                    fileSize = fingerprint.fileSize
                    contentHash = fingerprint.contentHash
                    this.workId = workId
                    this.episodeId = episodeId
                    createdAt = now
                    updatedAt = now
                })
            } else {
                existing.workId = workId
                existing.episodeId = episodeId
                existing.updatedAt = now
            }
            current.fingerprintedAt = now
            current.updatedAt = now
            stored = true
        }
        return stored
    }

    private fun backfill() {
        var afterId = 0L
        var stored = 0
        while (true) {
            val batch = files.findPendingFingerprints(afterId, PageRequest.of(0, 20))
            if (batch.isEmpty()) break
            for (file in batch) {
                val fileId = requireNotNull(file.id)
                afterId = fileId
                val workId = file.work?.id ?: continue
                try {
                    if (remember(fileId, workId, file.episode?.id)) stored += 1
                } catch (ex: Exception) {
                    log.warn("文件特征值补算跳过 fileId={} reason={}", fileId, ex.message)
                }
            }
        }
        if (stored > 0) {
            log.info("已补算文件特征值 count={}", stored)
        }
    }

    private fun compute(path: Path): ContentFingerprint? {
        if (!path.isRegularFile()) return null
        return try {
            FileChannel.open(path, StandardOpenOption.READ).use { channel ->
                val size = channel.size()
                if (size <= 0L) return null
                val window = minOf(WINDOW_BYTES, size)
                val digest = MessageDigest.getInstance("SHA-256")
                update(channel, 0L, window, digest)
                update(channel, size - window, window, digest)
                ContentFingerprint(size, digest.digest().joinToString("") { "%02x".format(it) })
            }
        } catch (ex: Exception) {
            log.warn("读取文件特征值失败 path={} reason={}", path, ex.message)
            null
        }
    }

    private fun update(channel: FileChannel, position: Long, length: Long, digest: MessageDigest) {
        val buffer = ByteBuffer.allocate(CHUNK_BYTES)
        var remaining = length
        var offset = position
        while (remaining > 0L) {
            buffer.clear()
            if (remaining < buffer.capacity()) {
                buffer.limit(remaining.toInt())
            }
            val read = channel.read(buffer, offset)
            if (read <= 0) return
            digest.update(buffer.array(), 0, read)
            offset += read
            remaining -= read
        }
    }

    private companion object {
        const val WINDOW_BYTES = 2L * 1024 * 1024
        const val CHUNK_BYTES = 256 * 1024
    }
}
