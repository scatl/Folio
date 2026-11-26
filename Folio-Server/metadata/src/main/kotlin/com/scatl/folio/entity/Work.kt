package com.scatl.folio.entity

import com.scatl.folio.catalog.WorkKind
import com.scatl.folio.catalog.ExternalProvider
import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.EnumType
import jakarta.persistence.Enumerated
import jakarta.persistence.GeneratedValue
import jakarta.persistence.GenerationType
import jakarta.persistence.Id
import jakarta.persistence.Table
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate

@Entity
@Table(name = "works")
open class Work {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    open var id: Long? = null

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 16)
    open var kind: WorkKind = WorkKind.movie

    @Column(name = "original_title", nullable = false, length = 512)
    open var originalTitle: String = ""

    @Column(name = "original_language", length = 16)
    open var originalLanguage: String? = null

    @Column(name = "release_year")
    open var releaseYear: Int? = null

    @Column(name = "premiere_date")
    open var premiereDate: LocalDate? = null

    @Column(name = "runtime_minutes")
    open var runtimeMinutes: Int? = null

    @Column(name = "work_status", length = 64)
    open var workStatus: String? = null

    @Column(length = 1024)
    open var homepage: String? = null

    @Column(precision = 12, scale = 3)
    open var popularity: BigDecimal? = null

    open var budget: Long? = null

    open var revenue: Long? = null

    open var adult: Boolean? = null

    @Column(name = "show_type", length = 64)
    open var showType: String? = null

    @Column(name = "in_production")
    open var inProduction: Boolean? = null

    @Column(name = "last_air_date")
    open var lastAirDate: LocalDate? = null

    @Column(name = "number_of_seasons")
    open var numberOfSeasons: Int? = null

    @Column(name = "number_of_episodes")
    open var numberOfEpisodes: Int? = null

    @Column(name = "collection_external_id", length = 64)
    open var collectionExternalId: String? = null

    @Column(name = "collection_name", length = 512)
    open var collectionName: String? = null

    @Column(length = 1024)
    open var awards: String? = null

    @Enumerated(EnumType.STRING)
    @Column(name = "source_provider", nullable = false, length = 16)
    open var sourceProvider: ExternalProvider = ExternalProvider.tmdb

    @Column(name = "created_at", nullable = false)
    open var createdAt: Instant = Instant.EPOCH

    @Column(name = "updated_at", nullable = false)
    open var updatedAt: Instant = Instant.EPOCH
}
