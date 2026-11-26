package com.scatl.folio.auth

import jakarta.servlet.http.HttpServletResponse
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.http.HttpMethod
import org.springframework.http.MediaType
import org.springframework.security.authentication.AuthenticationManager
import org.springframework.security.config.annotation.authentication.configuration.AuthenticationConfiguration
import org.springframework.security.config.annotation.web.builders.HttpSecurity
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity
import org.springframework.security.config.http.SessionCreationPolicy
import org.springframework.security.core.session.SessionRegistry
import org.springframework.security.core.session.SessionRegistryImpl
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder
import org.springframework.security.crypto.password.PasswordEncoder
import org.springframework.security.web.AuthenticationEntryPoint
import org.springframework.security.web.SecurityFilterChain
import org.springframework.security.web.authentication.session.ChangeSessionIdAuthenticationStrategy
import org.springframework.security.web.authentication.session.CompositeSessionAuthenticationStrategy
import org.springframework.security.web.authentication.session.RegisterSessionAuthenticationStrategy
import org.springframework.security.web.authentication.session.SessionAuthenticationStrategy
import org.springframework.security.web.context.HttpSessionSecurityContextRepository
import org.springframework.security.web.context.SecurityContextRepository
import org.springframework.security.web.session.HttpSessionEventPublisher

@Configuration
@EnableWebSecurity
class SecurityConfig {
    @Bean
    fun passwordEncoder(): PasswordEncoder = BCryptPasswordEncoder()

    @Bean
    fun authenticationManager(config: AuthenticationConfiguration): AuthenticationManager =
        config.authenticationManager

    @Bean
    fun securityContextRepository(): SecurityContextRepository = HttpSessionSecurityContextRepository()

    @Bean
    fun sessionRegistry(): SessionRegistry = SessionRegistryImpl()

    @Bean
    fun sessionAuthenticationStrategy(sessionRegistry: SessionRegistry): SessionAuthenticationStrategy =
        CompositeSessionAuthenticationStrategy(
            listOf(
                ChangeSessionIdAuthenticationStrategy(),
                RegisterSessionAuthenticationStrategy(sessionRegistry),
            ),
        )

    @Bean
    fun httpSessionEventPublisher(): HttpSessionEventPublisher = HttpSessionEventPublisher()

    @Bean
    fun authenticationEntryPoint(): AuthenticationEntryPoint =
        AuthenticationEntryPoint { _, response, _ ->
            response.status = HttpServletResponse.SC_UNAUTHORIZED
            response.contentType = MediaType.APPLICATION_JSON_VALUE
            response.characterEncoding = Charsets.UTF_8.name()
            response.writer.write("""{"code":401,"data":null,"msg":"未登录"}""")
        }

    @Bean
    fun securityFilterChain(
        http: HttpSecurity,
        entryPoint: AuthenticationEntryPoint,
        contextRepository: SecurityContextRepository,
        sessionRegistry: SessionRegistry,
        sessionAuthenticationStrategy: SessionAuthenticationStrategy,
    ): SecurityFilterChain =
        http
            .csrf { it.disable() }
            .cors { }
            .securityContext { it.securityContextRepository(contextRepository) }
            .sessionManagement { session ->
                session.sessionCreationPolicy(SessionCreationPolicy.IF_REQUIRED)
                session.sessionAuthenticationStrategy(sessionAuthenticationStrategy)
                session.sessionConcurrency { concurrency ->
                    concurrency.maximumSessions(-1)
                    concurrency.sessionRegistry(sessionRegistry)
                    concurrency.expiredSessionStrategy { event ->
                        val response = event.response
                        response.status = HttpServletResponse.SC_UNAUTHORIZED
                        response.contentType = MediaType.APPLICATION_JSON_VALUE
                        response.characterEncoding = Charsets.UTF_8.name()
                        response.writer.write("""{"code":401,"data":null,"msg":"未登录"}""")
                    }
                }
            }
            .authorizeHttpRequests { auth ->
                auth.requestMatchers(HttpMethod.POST, "/api/auth/login").permitAll()
                auth.requestMatchers(HttpMethod.GET, "/api/auth/posters").permitAll()
                auth.requestMatchers(HttpMethod.GET, "/api/server/identity").permitAll()
                auth.requestMatchers("/api/users", "/api/users/**").hasRole("ADMIN")
                auth.requestMatchers("/api/settings", "/api/settings/**").hasRole("ADMIN")
                auth.requestMatchers(HttpMethod.POST, "/api/libraries").hasRole("ADMIN")
                auth.requestMatchers(HttpMethod.PUT, "/api/libraries/order").hasRole("ADMIN")
                auth.requestMatchers(HttpMethod.GET, "/api/libraries/browse").hasRole("ADMIN")
                auth.requestMatchers(HttpMethod.DELETE, "/api/libraries/*").hasRole("ADMIN")
                auth.requestMatchers(HttpMethod.GET, "/api/library/files").hasRole("ADMIN")
                auth.requestMatchers(HttpMethod.POST, "/api/library/files").hasRole("ADMIN")
                auth.requestMatchers("/api/scrape-jobs", "/api/scrape-jobs/**").hasRole("ADMIN")
                auth.requestMatchers("/api/logs/server", "/api/logs/server/**").hasRole("ADMIN")
                auth.requestMatchers(HttpMethod.GET, "/api/server/connections").hasRole("ADMIN")
                auth.requestMatchers(HttpMethod.PUT, "/api/server/remote").hasRole("ADMIN")
                auth.requestMatchers("/api/**").authenticated()
                auth.anyRequest().permitAll()
            }
            .formLogin { it.disable() }
            .httpBasic { it.disable() }
            .logout { it.disable() }
            .exceptionHandling { handling ->
                handling.authenticationEntryPoint(entryPoint)
                handling.accessDeniedHandler { _, response, _ ->
                    response.status = HttpServletResponse.SC_FORBIDDEN
                    response.contentType = MediaType.APPLICATION_JSON_VALUE
                    response.characterEncoding = Charsets.UTF_8.name()
                    response.writer.write("""{"code":403,"data":null,"msg":"没有权限"}""")
                }
            }
            .build()
}
