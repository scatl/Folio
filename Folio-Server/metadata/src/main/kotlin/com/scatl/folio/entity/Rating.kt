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
import java.math.BigDecimal

@Entity
@Table(name = "ratings")
open class Rating {
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

    @Column(name = "score_value", nullable = false, precision = 6, scale = 2)
    open var scoreValue: BigDecimal = BigDecimal.ZERO

    open var votes: Int? = null

    @Column(name = "score_scale", nullable = false, precision = 6, scale = 2)
    open var scoreScale: BigDecimal = BigDecimal.TEN
}
