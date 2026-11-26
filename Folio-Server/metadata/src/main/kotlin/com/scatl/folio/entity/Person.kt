package com.scatl.folio.entity

import com.scatl.folio.catalog.ExternalProvider
import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.EnumType
import jakarta.persistence.Enumerated
import jakarta.persistence.GeneratedValue
import jakarta.persistence.GenerationType
import jakarta.persistence.Id
import jakarta.persistence.Lob
import jakarta.persistence.Table
import java.time.Instant
import java.time.LocalDate

@Entity
@Table(name = "people")
open class Person {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    open var id: Long? = null

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 16)
    open var provider: ExternalProvider = ExternalProvider.tmdb

    @Column(name = "provider_person_id", nullable = false, length = 64)
    open var providerPersonId: String = ""

    @Column(nullable = false, length = 512)
    open var name: String = ""

    @Column(name = "profile_url", length = 1024)
    open var profileUrl: String? = null

    @Lob
    @Column(columnDefinition = "TEXT")
    open var biography: String? = null

    @Column
    open var birthday: LocalDate? = null

    @Column
    open var deathday: LocalDate? = null

    @Column(name = "place_of_birth", length = 512)
    open var placeOfBirth: String? = null

    @Column(name = "known_for_department", length = 128)
    open var knownForDepartment: String? = null

    @Lob
    @Column(name = "also_known_as", columnDefinition = "TEXT")
    open var alsoKnownAs: String? = null

    @Column(name = "detail_fetched_at")
    open var detailFetchedAt: Instant? = null
}
