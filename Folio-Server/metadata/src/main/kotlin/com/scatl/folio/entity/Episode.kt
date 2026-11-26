package com.scatl.folio.entity

import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.GeneratedValue
import jakarta.persistence.GenerationType
import jakarta.persistence.Id
import jakarta.persistence.Table
import java.math.BigDecimal
import java.time.LocalDate

@Entity
@Table(name = "episodes")
open class Episode {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    open var id: Long? = null

    @Column(name = "work_id", nullable = false)
    open var workId: Long = 0

    @Column(name = "season_id", nullable = false)
    open var seasonId: Long = 0

    @Column(name = "episode_number", nullable = false)
    open var episodeNumber: Int = 0

    @Column(name = "absolute_number")
    open var absoluteNumber: Int? = null

    @Column(length = 512)
    open var title: String? = null

    @Column(columnDefinition = "TEXT")
    open var overview: String? = null

    @Column(name = "air_date")
    open var airDate: LocalDate? = null

    @Column(name = "runtime_minutes")
    open var runtimeMinutes: Int? = null

    @Column(name = "vote_average", precision = 6, scale = 2)
    open var voteAverage: BigDecimal? = null

    @Column(name = "vote_count")
    open var voteCount: Int? = null
}
