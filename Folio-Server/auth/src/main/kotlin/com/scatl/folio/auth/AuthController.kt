package com.scatl.folio.auth

import jakarta.servlet.http.HttpServletRequest
import jakarta.servlet.http.HttpServletResponse
import jakarta.validation.Valid
import org.springframework.http.HttpStatus
import org.springframework.security.authentication.AuthenticationManager
import org.springframework.security.authentication.DisabledException
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken
import org.springframework.security.core.Authentication
import org.springframework.security.core.AuthenticationException
import org.springframework.security.core.context.SecurityContextHolder
import org.springframework.security.core.userdetails.User
import org.springframework.security.web.authentication.session.SessionAuthenticationStrategy
import org.springframework.security.web.context.SecurityContextRepository
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController
import org.springframework.web.server.ResponseStatusException

@RestController
@RequestMapping("/api/auth")
class AuthController(
    private val authenticationManager: AuthenticationManager,
    private val securityContextRepository: SecurityContextRepository,
    private val sessionAuthenticationStrategy: SessionAuthenticationStrategy,
    private val authService: AuthService,
) {
    private val contextHolder = SecurityContextHolder.getContextHolderStrategy()

    @PostMapping("/login")
    fun login(
        @Valid @RequestBody body: LoginRequest,
        request: HttpServletRequest,
        response: HttpServletResponse,
    ): AuthUserView {
        val authentication = try {
            authenticationManager.authenticate(
                UsernamePasswordAuthenticationToken(body.username.trim(), body.password),
            )
        } catch (_: DisabledException) {
            throw ResponseStatusException(HttpStatus.FORBIDDEN, "账号已停用")
        } catch (_: AuthenticationException) {
            throw ResponseStatusException(HttpStatus.UNAUTHORIZED, "用户名或密码错误")
        }
        request.getSession(true)
        val context = contextHolder.createEmptyContext()
        context.authentication = authentication
        contextHolder.context = context
        sessionAuthenticationStrategy.onAuthentication(authentication, request, response)
        securityContextRepository.saveContext(context, request, response)
        return authService.viewByUsername(authentication.name)
    }

    @GetMapping("/me")
    fun me(authentication: Authentication): AuthUserView = authService.viewByUsername(authentication.name)

    @GetMapping("/posters")
    fun posters(): List<String> = authService.loginPosters()

    @PostMapping("/logout")
    fun logout(request: HttpServletRequest, response: HttpServletResponse): Map<String, Boolean> {
        request.getSession(false)?.invalidate()
        contextHolder.clearContext()
        return mapOf("ok" to true)
    }

    @PostMapping("/account")
    fun account(
        @Valid @RequestBody body: AccountUpdateRequest,
        authentication: Authentication,
        request: HttpServletRequest,
        response: HttpServletResponse,
    ): AuthUserView {
        val view = authService.updateAccount(authentication.name, body)
        val principal = User.withUsername(view.username)
            .password("")
            .authorities(authentication.authorities)
            .build()
        val refreshed = UsernamePasswordAuthenticationToken(principal, null, principal.authorities)
        val context = contextHolder.createEmptyContext()
        context.authentication = refreshed
        contextHolder.context = context
        sessionAuthenticationStrategy.onAuthentication(refreshed, request, response)
        securityContextRepository.saveContext(context, request, response)
        return view
    }
}
