package com.scatl.folio.auth

import com.scatl.folio.entity.UserRole
import com.scatl.folio.repository.AppUserRepository
import org.springframework.security.core.userdetails.User
import org.springframework.security.core.userdetails.UserDetails
import org.springframework.security.core.userdetails.UserDetailsService
import org.springframework.security.core.userdetails.UsernameNotFoundException
import org.springframework.stereotype.Service

@Service
class FolioUserDetailsService(
    private val users: AppUserRepository,
) : UserDetailsService {
    override fun loadUserByUsername(username: String): UserDetails {
        val user = users.findByUsername(username.trim())
            ?: throw UsernameNotFoundException("用户不存在")
        val role = if (user.role == UserRole.ADMIN) "ADMIN" else "USER"
        return User.withUsername(user.username)
            .password(user.passwordHash)
            .roles(role)
            .disabled(user.disabled)
            .build()
    }
}
