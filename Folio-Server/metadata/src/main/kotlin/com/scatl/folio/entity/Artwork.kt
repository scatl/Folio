package com.scatl.folio.entity

import com.scatl.folio.catalog.ExternalProvider
import com.scatl.folio.catalog.OwnerType
import com.scatl.folio.catalog.ArtworkKind
import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.EnumType
import jakarta.persistence.Enumerated
import jakarta.persistence.GeneratedValue
import jakarta.persistence.GenerationType
import jakarta.persistence.Id
import jakarta.persistence.Table

@Entity
@Table(name = "artworks")
open class Artwork {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    open var id: Long? = null

    @Enumerated(EnumType.STRING)
    @Column(name = "owner_type", nullable = false, length = 16)
    open var ownerType: OwnerType = OwnerType.work

    @Column(name = "owner_id", nullable = false)
    open var ownerId: Long = 0

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 32)
    open var kind: ArtworkKind = ArtworkKind.poster

    @Column(length = 16)
    open var locale: String? = null

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 16)
    open var provider: ExternalProvider = ExternalProvider.tmdb

    @Column(name = "remote_url", nullable = false, length = 1024)
    open var remoteUrl: String = ""

    @Column(name = "local_path", length = 1024)
    open var localPath: String? = null
}
