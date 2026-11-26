package com.scatl.folio.entity

import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.GeneratedValue
import jakarta.persistence.GenerationType
import jakarta.persistence.Id
import jakarta.persistence.Table

@Entity
@Table(name = "series_title_aliases")
open class SeriesTitleAlias {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    open var id: Long? = null

    @Column(name = "title_key", nullable = false, length = 512)
    open var titleKey: String = ""

    @Column(name = "release_year")
    open var releaseYear: Int? = null

    @Column(name = "work_id", nullable = false)
    open var workId: Long = 0

    @Column(name = "tmdb_id", nullable = false, length = 32)
    open var tmdbId: String = ""
}
