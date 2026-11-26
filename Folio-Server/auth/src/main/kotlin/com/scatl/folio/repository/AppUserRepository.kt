package com.scatl.folio.repository

import com.scatl.folio.entity.AppUser
import com.scatl.folio.entity.UserRole
import org.springframework.data.jpa.repository.JpaRepository

interface AppUserRepository : JpaRepository<AppUser, Long> {
    fun findByUsername(username: String): AppUser?
    fun existsByUsername(username: String): Boolean
    fun findAllByOrderByIdAsc(): List<AppUser>
    fun countByRoleAndDisabled(role: UserRole, disabled: Boolean): Long
}
