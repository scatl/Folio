package com.scatl.folio.playback

import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.GeneratedValue
import jakarta.persistence.GenerationType
import jakarta.persistence.Id
import jakarta.persistence.Table
import java.time.Instant

@Entity
@Table(name = "playback_progress")
open class PlaybackProgress {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    open var id: Long? = null

    @Column(name = "user_id", nullable = false)
    open var userId: Long = 0

    @Column(name = "library_file_id", nullable = false)
    open var libraryFileId: Long = 0

    @Column(name = "work_id")
    open var workId: Long? = null

    @Column(name = "episode_id")
    open var episodeId: Long? = null

    @Column(name = "position_ms", nullable = false)
    open var positionMs: Long = 0

    @Column(name = "duration_ms")
    open var durationMs: Long? = null

    @Column(nullable = false)
    open var completed: Boolean = false

    @Column(name = "updated_at", nullable = false)
    open var updatedAt: Instant = Instant.EPOCH
}
