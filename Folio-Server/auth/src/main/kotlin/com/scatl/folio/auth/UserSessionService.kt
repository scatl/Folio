package com.scatl.folio.auth

import org.springframework.security.core.session.SessionRegistry
import org.springframework.security.core.userdetails.User
import org.springframework.stereotype.Service

@Service
class UserSessionService(
    private val sessions: SessionRegistry,
) {
    fun expire(username: String) {
        val name = username.trim()
        if (name.isEmpty()) return
        val principal = User.withUsername(name).password("").roles("USER").build()
        sessions.getAllSessions(principal, false).forEach { it.expireNow() }
    }
}
