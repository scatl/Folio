package com.scatl.folio.library

import com.scatl.folio.entity.JobStatus
import com.scatl.folio.repository.ScrapeJobRepository
import jakarta.persistence.EntityManager
import org.slf4j.LoggerFactory
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Propagation
import org.springframework.transaction.annotation.Transactional
import org.springframework.transaction.support.TransactionTemplate
import java.time.Instant

@Service
open class ScrapeJobService(
    private val jobs: ScrapeJobRepository,
    private val files: FileMatchService,
    private val transactions: TransactionTemplate,
    private val entityManager: EntityManager,
    private val events: ScrapeEventPublisher,
) {
    private val log = LoggerFactory.getLogger(javaClass)

    fun claim(): Long? {
        val id = transactions.execute {
            @Suppress("UNCHECKED_CAST")
            val ids = entityManager.createNativeQuery(
                """
                SELECT id FROM scrape_jobs
                WHERE status = 'queued' AND next_run_at <= CURRENT_TIMESTAMP(6)
                ORDER BY id
                LIMIT 1
                FOR UPDATE SKIP LOCKED
                """.trimIndent(),
            ).resultList as List<Number>
            if (ids.isEmpty()) return@execute null
            val claimed = ids[0].toLong()
            entityManager.createNativeQuery(
                """
                UPDATE scrape_jobs
                SET status = 'running',
                    progress = '开始执行',
                    updated_at = CURRENT_TIMESTAMP(6)
                WHERE id = :id
                """.trimIndent(),
            ).setParameter("id", claimed).executeUpdate()
            claimed
        }
        if (id != null) {
            events.notifyJob(id)
        }
        return id
    }

    fun requeueInterrupted() {
        transactions.executeWithoutResult {
            val updated = entityManager.createNativeQuery(
                """
                UPDATE scrape_jobs
                SET status = 'queued',
                    progress = '等待执行',
                    updated_at = CURRENT_TIMESTAMP(6)
                WHERE status = 'running'
                """.trimIndent(),
            ).executeUpdate()
            if (updated > 0) {
                log.info("已将中断的刮削任务重新入队 count={}", updated)
            }
        }
    }

    @Transactional(readOnly = true)
    open fun fileId(jobId: Long): Long? = jobs.findById(jobId).orElse(null)?.libraryFile?.id

    /** 独立事务提交，确保前端能立刻看到当前步骤。 */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    open fun progress(jobId: Long, step: String) {
        val job = jobs.findById(jobId).orElse(null) ?: return
        job.progress = FileMatchService.limit(step)?.take(255)
        job.updatedAt = Instant.now()
        events.notifyJobAfterCommit(jobId)
    }

    @Transactional
    open fun succeed(jobId: Long) {
        val job = jobs.findById(jobId).orElse(null) ?: return
        if (job.status != JobStatus.running) return
        job.status = JobStatus.succeeded
        // 保留「待人工确认 / 无匹配结果」等终态文案，避免被笼统的「已完成」覆盖
        if (job.progress != "待人工确认" && job.progress != "无匹配结果") {
            job.progress = "已完成"
        }
        job.lastError = null
        job.updatedAt = Instant.now()
        events.notifyJobAfterCommit(jobId)
        log.info("刮削任务成功 jobId={} fileId={}", jobId, job.libraryFile?.id)
    }

    @Transactional
    open fun retryLater(jobId: Long, delaySeconds: Long, message: String) {
        val job = jobs.findById(jobId).orElse(null) ?: return
        val fileId = job.libraryFile?.id ?: return
        val now = Instant.now()
        val delay = delaySeconds.coerceAtLeast(1)
        job.status = JobStatus.queued
        job.progress = "等待重试"
        job.nextRunAt = now.plusSeconds(delay)
        job.lastError = FileMatchService.limit(message)
        job.updatedAt = now
        files.note(fileId, message)
        events.notifyJobAfterCommit(jobId)
        log.warn(
            "刮削任务延迟重试 jobId={} fileId={} delaySeconds={} reason={}",
            jobId,
            job.libraryFile?.id,
            delay,
            message,
        )
    }

    @Transactional
    open fun fail(jobId: Long, message: String) {
        val job = jobs.findById(jobId).orElse(null) ?: return
        val fileId = job.libraryFile?.id ?: return
        val now = Instant.now()
        job.attempts += 1
        job.lastError = FileMatchService.limit(message)
        job.updatedAt = now
        if (job.attempts >= job.maxAttempts) {
            job.status = JobStatus.failed
            job.progress = "失败"
            files.markFailed(fileId, message)
            events.notifyJobAfterCommit(jobId)
            log.error(
                "刮削任务永久失败 jobId={} fileId={} attempts={}/{} reason={}",
                jobId,
                fileId,
                job.attempts,
                job.maxAttempts,
                message,
            )
            return
        }
        job.status = JobStatus.queued
        job.progress = "等待重试"
        job.nextRunAt = now.plusSeconds(30L * job.attempts)
        files.note(fileId, message)
        events.notifyJobAfterCommit(jobId)
        log.warn(
            "刮削任务失败将重试 jobId={} fileId={} attempts={}/{} nextDelaySeconds={} reason={}",
            jobId,
            fileId,
            job.attempts,
            job.maxAttempts,
            30L * job.attempts,
            message,
        )
    }

    @Transactional
    open fun failPermanent(jobId: Long, message: String) {
        val job = jobs.findById(jobId).orElse(null) ?: return
        val fileId = job.libraryFile?.id ?: return
        job.attempts = job.maxAttempts
        job.status = JobStatus.failed
        job.progress = "失败"
        job.lastError = FileMatchService.limit(message)
        job.updatedAt = Instant.now()
        files.markFailed(fileId, message)
        events.notifyJobAfterCommit(jobId)
        log.error("刮削任务永久失败 jobId={} fileId={} reason={}", jobId, job.libraryFile?.id, message)
    }
}
