package com.scatl.folio.library

import com.scatl.folio.settings.FolioSettings
import com.scatl.folio.entity.JobStatus
import com.scatl.folio.entity.LibraryFile
import com.scatl.folio.entity.MatchStatus
import com.scatl.folio.entity.MediaLibrary
import com.scatl.folio.entity.ScrapeJob
import com.scatl.folio.repository.LibraryFileRepository
import com.scatl.folio.repository.ScrapeJobRepository
import org.slf4j.LoggerFactory
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import java.time.Instant

@Service
open class FileIngestService(
    private val files: LibraryFileRepository,
    private val jobs: ScrapeJobRepository,
    private val appSettings: FolioSettings,
    private val events: ScrapeEventPublisher,
) {
    private val log = LoggerFactory.getLogger(javaClass)

    @Transactional
    open fun submit(
        fileName: String,
        locator: String?,
        mediaLibrary: MediaLibrary? = null,
        fileSize: Long? = null,
        sourceModifiedAt: Instant? = null,
    ): LibraryFile {
        val now = Instant.now()
        val storedLocator = if (locator.isNullOrBlank()) fileName else locator
        val file = files.save(LibraryFile().apply {
            this.mediaLibrary = mediaLibrary
            this.locator = storedLocator
            this.locatorHash = LibraryPaths.locatorHash(storedLocator)
            this.fileName = fileName
            this.fileSize = fileSize
            this.sourceModifiedAt = sourceModifiedAt
            matchStatus = MatchStatus.pending
            createdAt = now
            updatedAt = now
        })
        val job = jobs.save(ScrapeJob().apply {
            libraryFile = file
            status = JobStatus.queued
            progress = "等待执行"
            attempts = 0
            maxAttempts = appSettings.current().workerMaxAttempts
            nextRunAt = now
            createdAt = now
            updatedAt = now
        })
        events.notifyJobAfterCommit(requireNotNull(job.id))
        log.info(
            "刮削任务已入队 jobId={} fileId={} libraryId={} fileName={} locator={}",
            job.id,
            file.id,
            mediaLibrary?.id,
            fileName,
            file.locator,
        )
        return file
    }
}
