package com.scatl.folio.provider

import com.scatl.folio.settings.AppSettingsChangedEvent
import com.scatl.folio.settings.FolioSettings
import com.scatl.folio.settings.RuntimeSettings
import jakarta.annotation.PostConstruct
import org.springframework.context.event.EventListener
import org.springframework.http.client.JdkClientHttpRequestFactory
import org.springframework.stereotype.Component
import org.springframework.web.client.RestClient
import java.net.http.HttpClient
import java.time.Duration

@Component
class ProviderClients(
    private val settings: FolioSettings,
) {
    data class Handle(val client: RestClient, val pacer: RequestPacer)

    @Volatile
    private lateinit var tmdbHandle: Handle

    @Volatile
    private lateinit var tvdbHandle: Handle

    @Volatile
    private lateinit var omdbHandle: Handle

    val tmdb: Handle get() = tmdbHandle
    val tvdb: Handle get() = tvdbHandle
    val omdb: Handle get() = omdbHandle

    private val lock = Any()
    private var signature: String? = null

    @PostConstruct
    fun start() {
        rebuild(settings.current())
    }

    @EventListener
    fun onSettings(event: AppSettingsChangedEvent) {
        rebuild(event.current)
    }

    private fun rebuild(current: RuntimeSettings) {
        val next = current.clientSignature()
        synchronized(lock) {
            if (next == signature && this::tmdbHandle.isInitialized) return
            tmdbHandle = Handle(
                restClient(current.tmdbBaseUrl, current.httpTimeoutSeconds),
                RequestPacer(current.tmdbRequestsPerSecond),
            )
            tvdbHandle = Handle(
                restClient(current.tvdbBaseUrl, current.httpTimeoutSeconds),
                RequestPacer(current.tvdbRequestsPerSecond),
            )
            omdbHandle = Handle(
                restClient(current.omdbBaseUrl, current.httpTimeoutSeconds),
                RequestPacer(current.omdbRequestsPerSecond),
            )
            signature = next
        }
    }

    private fun restClient(baseUrl: String, timeoutSeconds: Long): RestClient {
        val timeout = Duration.ofSeconds(timeoutSeconds.coerceAtLeast(1))
        val httpClient = HttpClient.newBuilder().connectTimeout(timeout).build()
        val factory = JdkClientHttpRequestFactory(httpClient).apply {
            setReadTimeout(timeout)
        }
        return RestClient.builder()
            .baseUrl(baseUrl.removeSuffix("/"))
            .requestFactory(factory)
            .build()
    }
}
