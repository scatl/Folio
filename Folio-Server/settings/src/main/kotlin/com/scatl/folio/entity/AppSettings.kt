package com.scatl.folio.entity

import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.Id
import jakarta.persistence.Table
import java.time.Instant

@Entity
@Table(name = "app_settings")
open class AppSettings {
    @Id
    open var id: Long = 1

    @Column(name = "tmdb_api_key", length = 256)
    open var tmdbApiKey: String? = null

    @Column(name = "tmdb_base_url", nullable = false, length = 512)
    open var tmdbBaseUrl: String = "https://api.tmdb.org/3"

    @Column(name = "tmdb_image_base_url", nullable = false, length = 512)
    open var tmdbImageBaseUrl: String = "https://image.tmdb.org/t/p/original"

    @Column(name = "tmdb_language", nullable = false, length = 32)
    open var tmdbLanguage: String = "zh-CN"

    @Column(name = "tmdb_search_language", nullable = false, length = 32)
    open var tmdbSearchLanguage: String = "en-US"

    @Column(name = "tmdb_requests_per_second", nullable = false)
    open var tmdbRequestsPerSecond: Double = 30.0

    @Column(name = "omdb_api_key", length = 256)
    open var omdbApiKey: String? = null

    @Column(name = "omdb_base_url", nullable = false, length = 512)
    open var omdbBaseUrl: String = "https://www.omdbapi.com"

    @Column(name = "omdb_requests_per_second", nullable = false)
    open var omdbRequestsPerSecond: Double = 30.0

    @Column(name = "tvdb_enabled", nullable = false)
    open var tvdbEnabled: Boolean = false

    @Column(name = "tvdb_api_key", length = 256)
    open var tvdbApiKey: String? = null

    @Column(name = "tvdb_pin", length = 128)
    open var tvdbPin: String? = null

    @Column(name = "tvdb_base_url", nullable = false, length = 512)
    open var tvdbBaseUrl: String = "https://api4.thetvdb.com/v4"

    @Column(name = "tvdb_requests_per_second", nullable = false)
    open var tvdbRequestsPerSecond: Double = 30.0

    @Column(name = "http_timeout_seconds", nullable = false)
    open var httpTimeoutSeconds: Long = 10

    @Column(name = "match_auto_threshold", nullable = false)
    open var matchAutoThreshold: Double = 0.72

    @Column(name = "worker_delay_ms", nullable = false)
    open var workerDelayMs: Long = 2000

    @Column(name = "worker_max_attempts", nullable = false)
    open var workerMaxAttempts: Int = 3

    @Column(name = "worker_concurrency", nullable = false)
    open var workerConcurrency: Int = 8

    @Column(name = "scan_interval_minutes", nullable = false)
    open var scanIntervalMinutes: Int = 10

    @Column(name = "watch_enabled", nullable = false)
    open var watchEnabled: Boolean = true

    @Column(name = "playback_ignore_below_seconds", nullable = false)
    open var playbackIgnoreBelowSeconds: Int = 10

    @Column(name = "playback_complete_remaining_seconds", nullable = false)
    open var playbackCompleteRemainingSeconds: Int = 30

    @Column(name = "updated_at", nullable = false)
    open var updatedAt: Instant = Instant.EPOCH
}
