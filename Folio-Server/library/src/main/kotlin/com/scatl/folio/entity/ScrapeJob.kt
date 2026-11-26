package com.scatl.folio.entity

import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.EnumType
import jakarta.persistence.Enumerated
import jakarta.persistence.FetchType
import jakarta.persistence.GeneratedValue
import jakarta.persistence.GenerationType
import jakarta.persistence.Id
import jakarta.persistence.JoinColumn
import jakarta.persistence.ManyToOne
import jakarta.persistence.Table
import java.time.Instant

@Entity
@Table(name = "scrape_jobs")
open class ScrapeJob {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    open var id: Long? = null

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "library_file_id", nullable = false)
    open var libraryFile: LibraryFile? = null

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 16)
    open var status: JobStatus = JobStatus.queued

    @Column(nullable = false)
    open var attempts: Int = 0

    @Column(name = "max_attempts", nullable = false)
    open var maxAttempts: Int = 3

    @Column(name = "next_run_at", nullable = false)
    open var nextRunAt: Instant = Instant.EPOCH

    @Column(name = "last_error", length = 1024)
    open var lastError: String? = null

    /** 当前执行步骤，供前端实时展示。 */
    @Column(length = 255)
    open var progress: String? = null

    @Column(name = "created_at", nullable = false)
    open var createdAt: Instant = Instant.EPOCH

    @Column(name = "updated_at", nullable = false)
    open var updatedAt: Instant = Instant.EPOCH
}
