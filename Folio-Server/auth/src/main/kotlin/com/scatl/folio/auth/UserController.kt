package com.scatl.folio.auth

import jakarta.validation.Valid
import org.springframework.security.core.Authentication
import org.springframework.web.bind.annotation.DeleteMapping
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PatchMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/api/users")
class UserController(
    private val authService: AuthService,
) {
    @GetMapping
    fun list(): List<AuthUserView> = authService.listUsers()

    @PostMapping
    fun create(@Valid @RequestBody body: CreateUserRequest): AuthUserView = authService.createUser(body)

    @PatchMapping("/{id}")
    fun update(
        @PathVariable id: Long,
        @Valid @RequestBody body: UpdateUserRequest,
        authentication: Authentication,
    ): AuthUserView = authService.updateUser(id, authentication.name, body)

    @DeleteMapping("/{id}")
    fun delete(@PathVariable id: Long, authentication: Authentication): Map<String, Boolean> {
        authService.deleteUser(id, authentication.name)
        return mapOf("ok" to true)
    }
}
