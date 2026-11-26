package com.scatl.folio.library

import com.scatl.folio.entity.JobStatus
import com.scatl.folio.entity.MatchStatus
import com.scatl.folio.entity.ScrapeJob
import com.scatl.folio.repository.LibraryFileRepository
import com.scatl.folio.repository.ScrapeJobRepository
import org.springframework.data.domain.Page
import org.springframework.data.domain.PageRequest
import org.springframework.data.domain.Sort
import org.springframework.http.HttpStatus
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import org.springframework.web.server.ResponseStatusException

@Service
open class ScrapeJobQueryService(
    private val jobs: ScrapeJobRepository,
    private val files: LibraryFileRepository,
    private val events: ScrapeEventPublisher,
) {
    @Transactional(readOnly = true)
    open fun list(status: String?, page: Int, size: Int): Page<ScrapeJob> {
        val mode = status?.trim()?.lowercase()?.takeIf { it.isNotEmpty() && it != "all" } ?: "all"
        if (mode !in FILTERS) {
            throw ResponseStatusException(HttpStatus.BAD_REQUEST, "无效的任务状态: $status")
        }
        val pageable = PageRequest.of(
            page.coerceAtLeast(0),
            size.coerceIn(1, 200),
            Sort.by(Sort.Direction.DESC, "id"),
        )
        return jobs.search(
            mode,
            JobStatus.queued,
            JobStatus.running,
            JobStatus.failed,
            MatchStatus.matched,
            MatchStatus.failed,
            MatchStatus.needs_review,
            pageable,
        )
    }

    @Transactional(readOnly = true)
    open fun activeCount(): Long =
        jobs.countByStatusIn(listOf(JobStatus.queued, JobStatus.running))

    @Transactional
    open fun delete(id: Long) {
        val job = jobs.findDetailedById(id)
            .orElseThrow { ResponseStatusException(HttpStatus.NOT_FOUND, "任务不存在") }
        if (job.status == JobStatus.running) {
            throw ResponseStatusException(HttpStatus.CONFLICT, "任务正在执行，无法删除")
        }
        val file = job.libraryFile
        jobs.delete(job)
        if (file != null) {
            files.delete(file)
        }
        events.notifyDeletedAfterCommit(id)
    }

    @Transactional
    open fun retry(id: Long): ScrapeJob {
        val job = jobs.findDetailedById(id)
            .orElseThrow { ResponseStatusException(HttpStatus.NOT_FOUND, "任务不存在") }
        val matchFailed = job.libraryFile?.matchStatus == MatchStatus.failed
        if (job.status != JobStatus.failed && !matchFailed) {
            throw ResponseStatusException(HttpStatus.CONFLICT, "仅失败任务可重试")
        }
        val now = java.time.Instant.now()
        job.status = JobStatus.queued
        job.progress = "等待执行"
        job.attempts = 0
        job.nextRunAt = now
        job.lastError = null
        job.updatedAt = now

        val file = job.libraryFile
        if (file != null && file.matchStatus != MatchStatus.matched) {
            file.matchStatus = MatchStatus.pending
            file.message = "已重新入队"
            file.updatedAt = now
        }
        events.notifyJobAfterCommit(id)
        return job
    }

    companion object {
        private val FILTERS = setOf("all", "queued", "running", "failed", "needs_review")
    }
}
