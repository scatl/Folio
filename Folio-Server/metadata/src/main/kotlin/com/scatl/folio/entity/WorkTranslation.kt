package com.scatl.folio.entity

import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.GeneratedValue
import jakarta.persistence.GenerationType
import jakarta.persistence.Id
import jakarta.persistence.Table

@Entity
@Table(name = "work_translations")
open class WorkTranslation {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    open var id: Long? = null

    @Column(name = "work_id", nullable = false)
    open var workId: Long = 0

    @Column(nullable = false, length = 16)
    open var locale: String = ""

    @Column(nullable = false, length = 512)
    open var title: String = ""

    @Column(columnDefinition = "TEXT")
    open var overview: String? = null

    @Column(length = 1024)
    open var tagline: String? = null
}
