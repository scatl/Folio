package com.scatl.folio.entity

import com.scatl.folio.catalog.WorkKind
import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.EnumType
import jakarta.persistence.Enumerated
import jakarta.persistence.GeneratedValue
import jakarta.persistence.GenerationType
import jakarta.persistence.Id
import jakarta.persistence.Table
import java.time.Instant

@Entity
@Table(name = "media_libraries")
open class MediaLibrary {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    open var id: Long? = null

    @Column(nullable = false, length = 128)
    open var name: String = ""

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 16)
    open var kind: WorkKind = WorkKind.movie

    @Column(name = "root_path", nullable = false, length = 1024)
    open var rootPath: String = ""

    @Column(name = "created_at", nullable = false)
    open var createdAt: Instant = Instant.EPOCH

    @Column(name = "updated_at", nullable = false)
    open var updatedAt: Instant = Instant.EPOCH

    @Column(name = "sort_order", nullable = false)
    open var sortOrder: Int = 0
}
