package com.scatl.folio.entity

import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.GeneratedValue
import jakarta.persistence.GenerationType
import jakarta.persistence.Id
import jakarta.persistence.Table

@Entity
@Table(name = "work_languages")
open class WorkLanguage {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    open var id: Long? = null

    @Column(name = "work_id", nullable = false)
    open var workId: Long = 0

    @Column(name = "language_code", nullable = false, length = 16)
    open var languageCode: String = ""

    @Column(length = 255)
    open var name: String? = null
}
