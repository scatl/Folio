package com.scatl.folio.auth

import org.springframework.boot.ApplicationArguments
import org.springframework.boot.ApplicationRunner
import org.springframework.stereotype.Component

@Component
class AuthBootstrap(
    private val auth: AuthService,
) : ApplicationRunner {
    override fun run(args: ApplicationArguments) {
        auth.ensureDefaultUser()
    }
}
