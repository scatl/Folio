package com.scatl.folio.entity

import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.GeneratedValue
import jakarta.persistence.GenerationType
import jakarta.persistence.Id
import jakarta.persistence.Table
import java.time.Instant

@Entity
@Table(name = "file_fingerprints")
open class FileFingerprint {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    open var id: Long? = null

    @Column(name = "file_size", nullable = false)
    open var fileSize: Long = 0

    @Column(name = "content_hash", nullable = false, length = 64)
    open var contentHash: String = ""

    @Column(name = "work_id", nullable = false)
    open var workId: Long = 0

    @Column(name = "episode_id")
    open var episodeId: Long? = null

    @Column(name = "created_at", nullable = false)
    open var createdAt: Instant = Instant.EPOCH

    @Column(name = "updated_at", nullable = false)
    open var updatedAt: Instant = Instant.EPOCH
}
