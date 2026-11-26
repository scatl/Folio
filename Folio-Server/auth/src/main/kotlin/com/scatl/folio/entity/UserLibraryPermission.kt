package com.scatl.folio.entity

import jakarta.persistence.Column
import jakarta.persistence.Embeddable
import jakarta.persistence.EmbeddedId
import jakarta.persistence.Entity
import jakarta.persistence.EnumType
import jakarta.persistence.Enumerated
import jakarta.persistence.Table
import java.io.Serializable

enum class LibraryAccess {
    READ,
    WRITE,
}

@Embeddable
open class UserLibraryPermissionId : Serializable {
    @Column(name = "user_id", nullable = false)
    open var userId: Long = 0

    @Column(name = "library_id", nullable = false)
    open var libraryId: Long = 0

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is UserLibraryPermissionId) return false
        return userId == other.userId && libraryId == other.libraryId
    }

    override fun hashCode(): Int = 31 * userId.hashCode() + libraryId.hashCode()
}

@Entity
@Table(name = "user_library_permissions")
open class UserLibraryPermission {
    @EmbeddedId
    open var id: UserLibraryPermissionId = UserLibraryPermissionId()

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 8)
    open var access: LibraryAccess = LibraryAccess.READ
}
