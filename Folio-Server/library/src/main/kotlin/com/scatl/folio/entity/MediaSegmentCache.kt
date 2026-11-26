package com.scatl.folio.entity

import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.GeneratedValue
import jakarta.persistence.GenerationType
import jakarta.persistence.Id
import jakarta.persistence.Table
import java.time.Instant

@Entity
@Table(name = "media_segment_cache")
open class MediaSegmentCache {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    open var id: Long? = null

    @Column(name = "work_id", nullable = false)
    open var workId: Long = 0

    /** 电影用 -1。 */
    @Column(name = "season_number", nullable = false)
    open var seasonNumber: Int = -1

    /** 电影用 -1。 */
    @Column(name = "episode_number", nullable = false)
    open var episodeNumber: Int = -1

    @Column(name = "duration_bucket", nullable = false)
    open var durationBucket: Int = 0

    @Column(nullable = false, columnDefinition = "TEXT")
    open var payload: String = "[]"

    @Column(name = "empty_result", nullable = false)
    open var emptyResult: Boolean = true

    @Column(name = "fetched_at", nullable = false)
    open var fetchedAt: Instant = Instant.EPOCH
}
