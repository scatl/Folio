package com.scatl.folio.entity

import com.scatl.folio.catalog.ExternalProvider
import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.EnumType
import jakarta.persistence.Enumerated
import jakarta.persistence.GeneratedValue
import jakarta.persistence.GenerationType
import jakarta.persistence.Id
import jakarta.persistence.Table
import java.time.Instant

@Entity
@Table(name = "provider_snapshots")
open class ProviderSnapshot {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    open var id: Long? = null

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 16)
    open var provider: ExternalProvider = ExternalProvider.tmdb

    @Column(name = "resource_key", nullable = false, length = 255)
    open var resourceKey: String = ""

    @Column(nullable = false, columnDefinition = "MEDIUMTEXT")
    open var body: String = ""

    @Column(name = "fetched_at", nullable = false)
    open var fetchedAt: Instant = Instant.EPOCH
}
