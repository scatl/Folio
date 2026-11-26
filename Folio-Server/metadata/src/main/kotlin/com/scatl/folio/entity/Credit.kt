package com.scatl.folio.entity

import com.scatl.folio.catalog.OwnerType
import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.EnumType
import jakarta.persistence.Enumerated
import jakarta.persistence.FetchType
import jakarta.persistence.GeneratedValue
import jakarta.persistence.GenerationType
import jakarta.persistence.Id
import jakarta.persistence.JoinColumn
import jakarta.persistence.ManyToOne
import jakarta.persistence.Table

@Entity
@Table(name = "credits")
open class Credit {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    open var id: Long? = null

    @Enumerated(EnumType.STRING)
    @Column(name = "owner_type", nullable = false, length = 16)
    open var ownerType: OwnerType = OwnerType.work

    @Column(name = "owner_id", nullable = false)
    open var ownerId: Long = 0

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "person_id", nullable = false)
    open var person: Person? = null

    @Column(length = 64)
    open var department: String? = null

    @Column(name = "job_name", length = 64)
    open var jobName: String? = null

    @Column(name = "character_name", length = 512)
    open var characterName: String? = null

    @Column(name = "sort_order", nullable = false)
    open var sortOrder: Int = 0
}
