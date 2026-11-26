package com.scatl.folio.settings

import com.scatl.folio.dto.AppSettingsUpdateRequest
import com.scatl.folio.dto.AppSettingsView
import com.scatl.folio.entity.AppSettings
import com.scatl.folio.repository.AppSettingsRepository
import org.springframework.context.ApplicationEventPublisher
import org.springframework.http.HttpStatus
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import org.springframework.web.server.ResponseStatusException
import java.time.Instant

@Service
class AppSettingsService(
    private val repository: AppSettingsRepository,
    private val events: ApplicationEventPublisher,
) : FolioSettings {
    @Volatile
    private var cached: RuntimeSettings? = null

    override fun current(): RuntimeSettings {
        cached?.let { return it }
        synchronized(this) {
            cached?.let { return it }
            val loaded = load()
            cached = loaded
            return loaded
        }
    }

    fun view(): AppSettingsView = toView(current())

    @Transactional
    fun update(body: AppSettingsUpdateRequest): AppSettingsView {
        val previous = cached
        val row = repository.findById(ROW_ID).orElseGet { AppSettings().apply { id = ROW_ID } }
        apply(row, body)
        row.updatedAt = Instant.now()
        repository.save(row)
        val next = toRuntime(row)
        cached = next
        events.publishEvent(AppSettingsChangedEvent(this, previous, next))
        return toView(next)
    }

    private fun load(): RuntimeSettings {
        val row = repository.findById(ROW_ID).orElseGet {
            AppSettings().apply {
                id = ROW_ID
                updatedAt = Instant.now()
            }.also { repository.save(it) }
        }
        return toRuntime(row)
    }

    private fun apply(row: AppSettings, body: AppSettingsUpdateRequest) {
        row.tmdbApiKey = mergeSecret(body.tmdbApiKey, row.tmdbApiKey)
        row.tmdbBaseUrl = trimUrl(body.tmdbBaseUrl, "TMDB API 地址")
        row.tmdbImageBaseUrl = trimUrl(body.tmdbImageBaseUrl, "TMDB 图片地址")
        row.tmdbLanguage = body.tmdbLanguage.trim()
        row.tmdbSearchLanguage = body.tmdbSearchLanguage.trim()
        row.tmdbRequestsPerSecond = body.tmdbRequestsPerSecond
        row.omdbApiKey = mergeSecret(body.omdbApiKey, row.omdbApiKey)
        row.omdbBaseUrl = trimUrl(body.omdbBaseUrl, "OMDb 地址")
        row.omdbRequestsPerSecond = body.omdbRequestsPerSecond
        row.tvdbApiKey = mergeSecret(body.tvdbApiKey, row.tvdbApiKey)
        row.tvdbPin = mergeSecret(body.tvdbPin, row.tvdbPin)
        row.tvdbEnabled = !row.tvdbApiKey.isNullOrBlank()
        row.tvdbBaseUrl = trimUrl(body.tvdbBaseUrl, "TVDB 地址")
        row.tvdbRequestsPerSecond = body.tvdbRequestsPerSecond
        row.httpTimeoutSeconds = body.httpTimeoutSeconds
        row.matchAutoThreshold = body.matchAutoThreshold
        row.workerDelayMs = body.workerDelayMs
        row.workerMaxAttempts = body.workerMaxAttempts
        row.workerConcurrency = body.workerConcurrency
        row.scanIntervalMinutes = body.scanIntervalMinutes
        row.watchEnabled = body.watchEnabled
        row.playbackIgnoreBelowSeconds = body.playbackIgnoreBelowSeconds
        row.playbackCompleteRemainingSeconds = body.playbackCompleteRemainingSeconds
    }

    private fun mergeSecret(incoming: String?, current: String?): String? {
        if (incoming == null) return current
        val trimmed = incoming.trim()
        return trimmed.ifEmpty { null }
    }

    private fun trimUrl(raw: String, label: String): String {
        val url = raw.trim().trimEnd('/')
        if (!url.startsWith("https://") && !url.startsWith("http://")) {
            throw ResponseStatusException(HttpStatus.BAD_REQUEST, "$label 必须以 http:// 或 https:// 开头")
        }
        return url
    }

    private fun toRuntime(row: AppSettings) = RuntimeSettings(
        tmdbApiKey = row.tmdbApiKey.orEmpty(),
        tmdbBaseUrl = row.tmdbBaseUrl,
        tmdbImageBaseUrl = row.tmdbImageBaseUrl,
        tmdbLanguage = row.tmdbLanguage,
        tmdbSearchLanguage = row.tmdbSearchLanguage,
        tmdbRequestsPerSecond = row.tmdbRequestsPerSecond,
        omdbApiKey = row.omdbApiKey.orEmpty(),
        omdbBaseUrl = row.omdbBaseUrl,
        omdbRequestsPerSecond = row.omdbRequestsPerSecond,
        tvdbEnabled = !row.tvdbApiKey.isNullOrBlank(),
        tvdbApiKey = row.tvdbApiKey.orEmpty(),
        tvdbPin = row.tvdbPin.orEmpty(),
        tvdbBaseUrl = row.tvdbBaseUrl,
        tvdbRequestsPerSecond = row.tvdbRequestsPerSecond,
        httpTimeoutSeconds = row.httpTimeoutSeconds,
        matchAutoThreshold = row.matchAutoThreshold,
        workerDelayMs = row.workerDelayMs,
        workerMaxAttempts = row.workerMaxAttempts,
        workerConcurrency = row.workerConcurrency,
        scanIntervalMinutes = row.scanIntervalMinutes,
        watchEnabled = row.watchEnabled,
        playbackIgnoreBelowSeconds = row.playbackIgnoreBelowSeconds,
        playbackCompleteRemainingSeconds = row.playbackCompleteRemainingSeconds,
    )

    private fun toView(settings: RuntimeSettings) = AppSettingsView(
        tmdbApiKeyConfigured = settings.tmdbConfigured(),
        tmdbBaseUrl = settings.tmdbBaseUrl,
        tmdbImageBaseUrl = settings.tmdbImageBaseUrl,
        tmdbLanguage = settings.tmdbLanguage,
        tmdbSearchLanguage = settings.tmdbSearchLanguage,
        tmdbRequestsPerSecond = settings.tmdbRequestsPerSecond,
        omdbApiKeyConfigured = settings.omdbConfigured(),
        omdbBaseUrl = settings.omdbBaseUrl,
        omdbRequestsPerSecond = settings.omdbRequestsPerSecond,
        tvdbEnabled = settings.tvdbEnabled,
        tvdbApiKeyConfigured = settings.tvdbApiKey.isNotBlank(),
        tvdbPinConfigured = settings.tvdbPin.isNotBlank(),
        tvdbBaseUrl = settings.tvdbBaseUrl,
        tvdbRequestsPerSecond = settings.tvdbRequestsPerSecond,
        httpTimeoutSeconds = settings.httpTimeoutSeconds,
        matchAutoThreshold = settings.matchAutoThreshold,
        workerDelayMs = settings.workerDelayMs,
        workerMaxAttempts = settings.workerMaxAttempts,
        workerConcurrency = settings.workerConcurrency,
        scanIntervalMinutes = settings.scanIntervalMinutes,
        watchEnabled = settings.watchEnabled,
        playbackIgnoreBelowSeconds = settings.playbackIgnoreBelowSeconds,
        playbackCompleteRemainingSeconds = settings.playbackCompleteRemainingSeconds,
    )

    companion object {
        private const val ROW_ID = 1L
    }
}
