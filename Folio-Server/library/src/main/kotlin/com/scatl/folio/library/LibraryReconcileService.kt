package com.scatl.folio.library

import com.scatl.folio.entity.JobStatus
import com.scatl.folio.entity.LibraryFile
import com.scatl.folio.entity.MatchStatus
import com.scatl.folio.repository.LibraryFileRepository
import com.scatl.folio.repository.MediaLibraryRepository
import com.scatl.folio.repository.ScrapeJobRepository
import org.slf4j.LoggerFactory
import org.springframework.beans.factory.annotation.Qualifier
import org.springframework.http.HttpStatus
import org.springframework.stereotype.Service
import org.springframework.transaction.PlatformTransactionManager
import org.springframework.transaction.support.TransactionTemplate
import org.springframework.web.server.ResponseStatusException
import java.nio.file.Files
import java.nio.file.Path
import java.time.Instant
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executor
import kotlin.io.path.isDirectory
import kotlin.io.path.isRegularFile

@Service
class LibraryReconcileService(
    private val libraries: MediaLibraryRepository,
    private val files: LibraryFileRepository,
    private val jobs: ScrapeJobRepository,
    private val ingest: FileIngestService,
    private val probe: MediaProbeService,
    private val events: ScrapeEventPublisher,
    @Qualifier("libraryScanExecutor") private val scanExecutor: Executor,
    transactionManager: PlatformTransactionManager,
) {
    private val log = LoggerFactory.getLogger(javaClass)
    private val tx = TransactionTemplate(transactionManager)
    private val scanning = ConcurrentHashMap.newKeySet<Long>()
    private val rescan = ConcurrentHashMap.newKeySet<Long>()
    private val abandoned = ConcurrentHashMap.newKeySet<Long>()

    fun abandon(libraryId: Long) {
        abandoned.add(libraryId)
        rescan.remove(libraryId)
    }

    fun requestScan(libraryId: Long) {
        if (libraryId in abandoned) return
        if (!scanning.add(libraryId)) {
            rescan.add(libraryId)
            return
        }
        try {
            scanExecutor.execute {
                try {
                    do {
                        rescan.remove(libraryId)
                        reconcile(libraryId)
                    } while (rescan.remove(libraryId))
                } catch (e: Exception) {
                    log.error("资料库对账失败 libraryId={}", libraryId, e)
                } finally {
                    scanning.remove(libraryId)
                    if (rescan.remove(libraryId)) {
                        requestScan(libraryId)
                    }
                }
            }
        } catch (e: RuntimeException) {
            scanning.remove(libraryId)
            log.error("资料库对账未能入队 libraryId={}", libraryId, e)
        }
    }

    private fun reconcile(libraryId: Long) {
        if (libraryId in abandoned) return
        val library = libraries.findById(libraryId).orElse(null)
        if (library == null) {
            log.warn("资料库已不存在，跳过对账 libraryId={}", libraryId)
            return
        }
        val root = Path.of(library.rootPath).toAbsolutePath().normalize()
        if (!root.isDirectory() || !LibraryPaths.isUnderMediaRoots(root)) {
            log.warn("资料库根目录不可用，跳过对账 libraryId={} path={}", libraryId, library.rootPath)
            return
        }

        val disk = try {
            listDiskFiles(root)
        } catch (e: Exception) {
            log.error("读取资料库目录失败，跳过对账 libraryId={} path={}", libraryId, root, e)
            return
        }
        val existing = files.findByMediaLibrary_IdOrderByIdAsc(libraryId)
        if (existing.size >= MIN_FILES_FOR_GUARD && disk.size * 5 < existing.size) {
            log.error(
                "本次只看到 {} 个视频，库内有 {} 条，疑似目录不可用，跳过对账 libraryId={}",
                disk.size,
                existing.size,
                libraryId,
            )
            return
        }

        val existingByHash = existing.associateBy { it.locatorHash }
        val diskByHash = disk.associateBy { it.hash }
        val missing = existing.filter { it.locatorHash !in diskByHash }
        val added = disk.filter { it.hash !in existingByHash }
        val renamedIds = mutableSetOf<Long>()
        val consumedNew = mutableSetOf<String>()

        val missingByParent = missing.groupBy { LibraryPaths.parentLocator(it.locator) }
        val addedByParent = added.groupBy { it.parent }
        for (parent in missingByParent.keys) {
            val gone = missingByParent[parent].orEmpty()
            val arrived = addedByParent[parent].orEmpty()
            if (gone.size != 1 || arrived.size != 1) continue
            val old = gone[0]
            val fresh = arrived[0]
            if (old.fileSize == null || old.fileSize != fresh.size) continue
            if (!fresh.stable) {
                renamedIds += requireNotNull(old.id)
                consumedNew += fresh.hash
                continue
            }
            if (isRunning(requireNotNull(old.id))) {
                log.info("任务正在执行，跳过改名 libraryId={} fileId={}", libraryId, old.id)
                renamedIds += requireNotNull(old.id)
                consumedNew += fresh.hash
                continue
            }
            rename(old, fresh)
            renamedIds += requireNotNull(old.id)
            consumedNew += fresh.hash
        }

        for (fresh in added) {
            if (libraryId in abandoned) return
            if (fresh.hash in consumedNew || !fresh.stable) continue
            val created = ingest.submit(fresh.fileName, fresh.locator, library, fresh.size, fresh.modifiedAt)
            probe.probeAndSave(requireNotNull(created.id))
        }

        for (file in existing) {
            if (libraryId in abandoned) return
            val fresh = diskByHash[file.locatorHash] ?: continue
            if (isRunning(requireNotNull(file.id)) || !fresh.stable) continue
            applyExisting(file, fresh)
        }

        for (file in missing) {
            if (libraryId in abandoned) return
            val fileId = requireNotNull(file.id)
            if (fileId in renamedIds || isRunning(fileId)) continue
            removeFile(file)
        }
        log.info(
            "资料库对账完成 libraryId={} disk={} existing={} added={} missing={}",
            libraryId,
            disk.size,
            existing.size,
            added.size,
            missing.size,
        )
    }

    private fun listDiskFiles(root: Path): List<DiskFile> {
        val found = mutableListOf<DiskFile>()
        val freshAfter = Instant.now().minusSeconds(STABLE_SECONDS)
        Files.walk(root).use { stream ->
            stream.filter { it.isRegularFile() && LibraryPaths.isVideoFile(it) }.forEach { path ->
                val fileName = path.fileName.toString()
                if (LibraryPaths.isPartial(fileName)) return@forEach
                val modifiedAt = Files.getLastModifiedTime(path).toInstant()
                val locator = LibraryPaths.displayPath(path)
                found += DiskFile(
                    locator = locator,
                    hash = LibraryPaths.locatorHash(locator),
                    fileName = fileName,
                    parent = LibraryPaths.parentLocator(locator),
                    size = Files.size(path),
                    modifiedAt = modifiedAt,
                    stable = !modifiedAt.isAfter(freshAfter),
                )
            }
        }
        return found
    }

    private fun applyExisting(file: LibraryFile, fresh: DiskFile) {
        val fileId = requireNotNull(file.id)
        if (file.fileSize == null || file.sourceModifiedAt == null) {
            tx.executeWithoutResult {
                val current = files.findById(fileId).orElse(null) ?: return@executeWithoutResult
                current.fileSize = fresh.size
                current.sourceModifiedAt = fresh.modifiedAt
                current.updatedAt = Instant.now()
            }
        }
        val unchanged = (file.fileSize == null || file.fileSize == fresh.size) &&
            (file.sourceModifiedAt == null || sameSecond(file.sourceModifiedAt, fresh.modifiedAt))
        if (unchanged) {
            if (file.probedAt == null) probe.probeAndSave(fileId)
            if (file.matchStatus == MatchStatus.pending) requeueFinishedWithoutMatch(fileId)
            return
        }
        tx.executeWithoutResult {
            val current = files.findById(fileId).orElse(null) ?: return@executeWithoutResult
            val previousWorkId = current.work?.id
            current.fileName = fresh.fileName
            current.fileSize = fresh.size
            current.sourceModifiedAt = fresh.modifiedAt
            clearMatch(current)
            files.flush()
            requeue(fileId)
            if (previousWorkId != null && files.countByWork_IdAndIdNot(previousWorkId, fileId) == 0L) {
                events.notifyWorkRemovedAfterCommit(previousWorkId)
            }
        }
        probe.probeAndSave(fileId)
    }

    private fun rename(file: LibraryFile, fresh: DiskFile) {
        val fileId = requireNotNull(file.id)
        tx.executeWithoutResult {
            val current = files.findById(fileId).orElse(null) ?: return@executeWithoutResult
            current.locator = fresh.locator
            current.locatorHash = fresh.hash
            current.fileName = fresh.fileName
            current.fileSize = fresh.size
            current.sourceModifiedAt = fresh.modifiedAt
            current.updatedAt = Instant.now()
            if (current.matchStatus == MatchStatus.matched) {
                jobs.findByLibraryFile_Id(fileId).ifPresent { job ->
                    events.notifyJobAfterCommit(requireNotNull(job.id))
                }
            } else {
                clearMatch(current)
                requeue(fileId)
            }
        }
    }

    private fun removeFile(file: LibraryFile) {
        val fileId = requireNotNull(file.id)
        tx.executeWithoutResult {
            val current = files.findById(fileId).orElse(null) ?: return@executeWithoutResult
            val workId = current.work?.id
            val job = jobs.findByLibraryFile_Id(fileId).orElse(null)
            if (job != null) {
                val jobId = requireNotNull(job.id)
                jobs.delete(job)
                jobs.flush()
                events.notifyDeletedAfterCommit(jobId)
            }
            val lastOfWork = workId != null && files.countByWork_IdAndIdNot(workId, fileId) == 0L
            files.delete(current)
            if (lastOfWork && workId != null) {
                events.notifyWorkRemovedAfterCommit(workId)
            }
        }
    }

    private fun clearMatch(file: LibraryFile) {
        file.work = null
        file.episode = null
        file.matchStatus = MatchStatus.pending
        file.confidence = null
        file.message = "文件已变化，重新刮削"
        file.parsedTitle = null
        file.parsedYear = null
        file.parsedSeason = null
        file.parsedEpisode = null
        file.parsedImdbId = null
        file.updatedAt = Instant.now()
    }

    /** 刮削已经成功，但探测把整行写回，匹配状态仍停在待匹配。 */
    private fun requeueFinishedWithoutMatch(fileId: Long) {
        tx.executeWithoutResult {
            val job = jobs.findByLibraryFile_Id(fileId).orElse(null) ?: return@executeWithoutResult
            if (job.status != JobStatus.succeeded) return@executeWithoutResult
            val current = files.findById(fileId).orElse(null) ?: return@executeWithoutResult
            if (current.matchStatus != MatchStatus.pending) return@executeWithoutResult
            log.info("任务已完成但文件仍待匹配，重新入队 fileId={} jobId={}", fileId, job.id)
            requeue(fileId)
        }
    }

    private fun requeue(fileId: Long) {
        val now = Instant.now()
        val job = jobs.findByLibraryFile_Id(fileId).orElse(null)
        if (job == null) {
            log.warn("文件没有刮削任务，跳过重新入队 fileId={}", fileId)
            return
        }
        job.status = JobStatus.queued
        job.progress = "等待执行"
        job.attempts = 0
        job.nextRunAt = now
        job.lastError = null
        job.updatedAt = now
        events.notifyJobAfterCommit(requireNotNull(job.id))
    }

    private fun isRunning(fileId: Long): Boolean =
        jobs.findByLibraryFile_Id(fileId).map { it.status == JobStatus.running }.orElse(false)

    fun requireLibrary(libraryId: Long) {
        if (!libraries.existsById(libraryId)) {
            throw ResponseStatusException(HttpStatus.NOT_FOUND, "资料库不存在")
        }
    }

    private fun sameSecond(left: Instant?, right: Instant): Boolean =
        left != null && left.epochSecond == right.epochSecond

    private data class DiskFile(
        val locator: String,
        val hash: String,
        val fileName: String,
        val parent: String,
        val size: Long,
        val modifiedAt: Instant,
        val stable: Boolean,
    )

    companion object {
        private const val MIN_FILES_FOR_GUARD = 20
        private const val STABLE_SECONDS = 10L
    }
}
