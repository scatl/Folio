package com.scatl.folio.library

import com.scatl.folio.dto.ScrapeDeletedEvent
import com.scatl.folio.dto.ScrapeJobStats
import com.scatl.folio.dto.WorkRemovedEvent
import com.scatl.folio.dto.toRow
import com.scatl.folio.entity.JobStatus
import com.scatl.folio.repository.ScrapeJobRepository
import org.slf4j.LoggerFactory
import org.springframework.stereotype.Service
import org.springframework.transaction.support.TransactionSynchronization
import org.springframework.transaction.support.TransactionSynchronizationManager

@Service
class ScrapeEventPublisher(
    private val hub: ScrapeEventHub,
    private val jobs: ScrapeJobRepository,
) {
    private val log = LoggerFactory.getLogger(javaClass)

    fun notifyJobAfterCommit(jobId: Long) {
        afterCommit { notifyJob(jobId) }
    }

    fun notifyWorkRemovedAfterCommit(workId: Long) {
        afterCommit { hub.publish("work.removed", WorkRemovedEvent(workId)) }
    }

    fun notifyDeletedAfterCommit(jobId: Long) {
        afterCommit {
            hub.publish("scrape.deleted", ScrapeDeletedEvent(jobId))
            notifyStats()
        }
    }

    fun notifyJob(jobId: Long) {
        val job = jobs.findDetailedById(jobId).orElse(null)
        if (job == null) {
            log.debug("SSE 跳过：任务不存在 jobId={}", jobId)
            return
        }
        try {
            val row = job.toRow()
            hub.publish("scrape.job", row)
            notifyStats()
            if (row.status == JobStatus.succeeded.name || row.status == JobStatus.failed.name) {
                hub.publish("scrape.done", row)
            }
        } catch (ex: Exception) {
            log.warn("SSE 发布失败 jobId={} reason={}", jobId, ex.message)
        }
    }

    fun notifyStats() {
        val active = jobs.countByStatusIn(listOf(JobStatus.queued, JobStatus.running))
        hub.publish("scrape.stats", ScrapeJobStats(active))
    }

    private fun afterCommit(block: () -> Unit) {
        if (TransactionSynchronizationManager.isSynchronizationActive()) {
            TransactionSynchronizationManager.registerSynchronization(
                object : TransactionSynchronization {
                    override fun afterCommit() = block()
                },
            )
        } else {
            block()
        }
    }
}
