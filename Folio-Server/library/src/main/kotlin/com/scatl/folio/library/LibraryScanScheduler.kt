package com.scatl.folio.library

import com.scatl.folio.repository.MediaLibraryRepository
import com.scatl.folio.settings.FolioSettings
import org.slf4j.LoggerFactory
import org.springframework.scheduling.annotation.Scheduled
import org.springframework.stereotype.Service
import java.time.Duration
import java.time.Instant

@Service
class LibraryScanScheduler(
    private val libraries: MediaLibraryRepository,
    private val appSettings: FolioSettings,
    private val reconcile: LibraryReconcileService,
) {
    private val log = LoggerFactory.getLogger(javaClass)
    private var lastScan: Instant? = null

    @Scheduled(fixedDelay = 15_000, initialDelay = 20_000)
    fun scanAll() {
        val now = Instant.now()
        val previous = lastScan
        val interval = Duration.ofMinutes(appSettings.current().scanIntervalMinutes.toLong().coerceAtLeast(1))
        if (previous != null && Duration.between(previous, now) < interval) {
            return
        }
        lastScan = now
        val ids = libraries.findAll().mapNotNull { it.id }
        if (ids.isEmpty()) return
        log.info("开始定时对账 libraries={}", ids.size)
        ids.forEach { reconcile.requestScan(it) }
    }
}
