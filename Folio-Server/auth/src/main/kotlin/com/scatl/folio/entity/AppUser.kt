package com.scatl.folio.entity

import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.EnumType
import jakarta.persistence.Enumerated
import jakarta.persistence.GeneratedValue
import jakarta.persistence.GenerationType
import jakarta.persistence.Id
import jakarta.persistence.Table
import java.time.Instant

enum class UserRole {
    ADMIN,
    USER,
}

@Entity
@Table(name = "app_users")
open class AppUser {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    open var id: Long? = null

    @Column(nullable = false, length = 64, unique = true)
    open var username: String = ""

    @Column(name = "password_hash", nullable = false, length = 120)
    open var passwordHash: String = ""

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 16)
    open var role: UserRole = UserRole.USER

    @Column(nullable = false)
    open var disabled: Boolean = false

    @Column(name = "created_at", nullable = false)
    open var createdAt: Instant = Instant.EPOCH

    @Column(name = "updated_at", nullable = false)
    open var updatedAt: Instant = Instant.EPOCH
}
