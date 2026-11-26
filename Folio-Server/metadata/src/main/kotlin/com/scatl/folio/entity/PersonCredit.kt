package com.scatl.folio.entity

import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.FetchType
import jakarta.persistence.GeneratedValue
import jakarta.persistence.GenerationType
import jakarta.persistence.Id
import jakarta.persistence.JoinColumn
import jakarta.persistence.ManyToOne
import jakarta.persistence.Table
import java.time.LocalDate

@Entity
@Table(name = "person_credits")
open class PersonCredit {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    open var id: Long? = null

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "person_id", nullable = false)
    open var person: Person? = null

    @Column(name = "media_type", nullable = false, length = 16)
    open var mediaType: String = "movie"

    @Column(name = "provider_media_id", nullable = false, length = 64)
    open var providerMediaId: String = ""

    @Column(nullable = false, length = 512)
    open var title: String = ""

    @Column(name = "original_title", length = 512)
    open var originalTitle: String? = null

    @Column(name = "release_year")
    open var releaseYear: Int? = null

    @Column(name = "release_date")
    open var releaseDate: LocalDate? = null

    @Column(name = "poster_url", length = 1024)
    open var posterUrl: String? = null

    @Column(name = "character_name", length = 512)
    open var characterName: String? = null

    @Column(name = "job_name", length = 64)
    open var jobName: String? = null

    @Column(length = 64)
    open var department: String? = null
}
