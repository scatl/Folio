package com.scatl.folio.entity

import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.GeneratedValue
import jakarta.persistence.GenerationType
import jakarta.persistence.Id
import jakarta.persistence.Table

@Entity
@Table(name = "work_countries")
open class WorkCountry {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    open var id: Long? = null

    @Column(name = "work_id", nullable = false)
    open var workId: Long = 0

    @Column(name = "country_code", nullable = false, length = 8)
    open var countryCode: String = ""

    @Column(length = 255)
    open var name: String? = null

    @Column(name = "country_kind", nullable = false, length = 16)
    open var countryKind: String = ""
}
