package com.scatl.folio.library

import com.scatl.folio.provider.RateLimitException
import com.scatl.folio.settings.FolioSettings
import jakarta.annotation.PostConstruct
import jakarta.annotation.PreDestroy
import org.slf4j.LoggerFactory
import org.springframework.boot.context.event.ApplicationReadyEvent
import org.springframework.context.event.EventListener
import org.springframework.scheduling.annotation.Scheduled
import org.springframework.stereotype.Service
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.ThreadFactory
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong

@Service
open class ScrapeWorker(
    private val jobs: ScrapeJobService,
    private val scrape: FilenameScrapeService,
    private val appSettings: FolioSettings,
) {
    private val log = LoggerFactory.getLogger(javaClass)
    private lateinit var executor: ExecutorService
    private val running = AtomicInteger(0)
    private val lastTick = AtomicLong(0)

    @PostConstruct
    fun startPool() {
        val sequence = AtomicInteger()
        val factory = ThreadFactory { runnable ->
            Thread(runnable, "scrape-worker-" + sequence.incrementAndGet()).apply { isDaemon = true }
        }
        executor = Executors.newCachedThreadPool(factory)
        log.info("刮削线程池已创建")
    }

    @PreDestroy
    fun shutdownPool() {
        if (::executor.isInitialized) {
            executor.shutdownNow()
        }
    }

    @EventListener(ApplicationReadyEvent::class)
    fun requeueInterrupted() {
        log.info("刮削 Worker 就绪 concurrency={}", appSettings.current().workerConcurrency.coerceAtLeast(1))
        jobs.requeueInterrupted()
    }

    @Scheduled(fixedDelay = 200)
    fun tick() {
        if (!::executor.isInitialized) return
        val settings = appSettings.current()
        val delay = settings.workerDelayMs.coerceAtLeast(200)
        val now = System.currentTimeMillis()
        if (now - lastTick.get() < delay) return
        lastTick.set(now)
        val limit = settings.workerConcurrency.coerceIn(1, 64)
        while (running.get() < limit) {
            val jobId = jobs.claim() ?: break
            val inFlight = running.incrementAndGet()
            log.info("领取刮削任务 jobId={} running={}", jobId, inFlight)
            executor.execute {
                try {
                    runJob(jobId)
                } finally {
                    running.decrementAndGet()
                }
            }
        }
    }

    private fun runJob(jobId: Long) {
        try {
            if (scrape.match(jobId)) {
                jobs.succeed(jobId)
            }
        } catch (ex: RuntimeException) {
            val rateLimit = rateLimit(ex)
            if (rateLimit != null) {
                log.warn(
                    "刮削限流 jobId={} provider={} delaySeconds={}",
                    jobId,
                    rateLimit.provider,
                    rateLimit.delaySeconds,
                    ex,
                )
                jobs.retryLater(jobId, rateLimit.delaySeconds, rateLimit.message ?: rateLimit.provider)
                return
            }
            if (isDeadlock(ex)) {
                log.warn("刮削遇数据库死锁，稍后重试 jobId={}", jobId, ex)
                jobs.retryLater(jobId, 3, "数据库死锁，稍后重试")
                return
            }
            log.error("刮削异常 jobId={} reason={}", jobId, ex.message, ex)
            jobs.fail(jobId, ex.message ?: ex.javaClass.simpleName)
        }
    }

    private fun rateLimit(error: Throwable?): RateLimitException? {
        var current = error
        while (current != null) {
            if (current is RateLimitException) return current
            current = current.cause
        }
        return null
    }

    private fun isDeadlock(error: Throwable?): Boolean {
        var current = error
        while (current != null) {
            val message = current.message.orEmpty()
            if (
                message.contains("Deadlock found", ignoreCase = true) ||
                current.javaClass.name.contains("Deadlock", ignoreCase = true)
            ) {
                return true
            }
            current = current.cause
        }
        return false
    }
}
