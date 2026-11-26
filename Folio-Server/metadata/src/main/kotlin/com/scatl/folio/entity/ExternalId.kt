package com.scatl.folio.entity

import com.scatl.folio.catalog.ExternalProvider
import com.scatl.folio.catalog.OwnerType
import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.EnumType
import jakarta.persistence.Enumerated
import jakarta.persistence.GeneratedValue
import jakarta.persistence.GenerationType
import jakarta.persistence.Id
import jakarta.persistence.Table

@Entity
@Table(name = "external_ids")
open class ExternalId {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    open var id: Long? = null

    @Enumerated(EnumType.STRING)
    @Column(name = "owner_type", nullable = false, length = 16)
    open var ownerType: OwnerType = OwnerType.work

    @Column(name = "owner_id", nullable = false)
    open var ownerId: Long = 0

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 16)
    open var provider: ExternalProvider = ExternalProvider.tmdb

    @Column(name = "external_id", nullable = false, length = 64)
    open var externalId: String = ""
}
