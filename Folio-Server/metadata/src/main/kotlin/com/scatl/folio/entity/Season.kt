package com.scatl.folio.entity

import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.GeneratedValue
import jakarta.persistence.GenerationType
import jakarta.persistence.Id
import jakarta.persistence.Table
import java.time.LocalDate

@Entity
@Table(name = "seasons")
open class Season {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    open var id: Long? = null

    @Column(name = "work_id", nullable = false)
    open var workId: Long = 0

    @Column(name = "season_number", nullable = false)
    open var seasonNumber: Int = 0

    @Column(length = 512)
    open var name: String? = null

    @Column(name = "episode_count")
    open var episodeCount: Int? = null

    @Column(name = "air_date")
    open var airDate: LocalDate? = null

    @Column(columnDefinition = "TEXT")
    open var overview: String? = null
}
