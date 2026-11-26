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

@Entity
@Table(name = "companies")
open class Company {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    open var id: Long? = null

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 16)
    open var provider: ExternalProvider = ExternalProvider.tmdb

    @Column(name = "external_id", nullable = false, length = 64)
    open var externalId: String = ""

    @Column(nullable = false, length = 512)
    open var name: String = ""

    @Column(name = "origin_country", length = 8)
    open var originCountry: String? = null

    @Column(name = "logo_url", length = 1024)
    open var logoUrl: String? = null
}
