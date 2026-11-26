package com.scatl.folio.settings

data class RuntimeSettings(
    val tmdbApiKey: String,
    val tmdbBaseUrl: String,
    val tmdbImageBaseUrl: String,
    val tmdbLanguage: String,
    val tmdbSearchLanguage: String,
    val tmdbRequestsPerSecond: Double,
    val omdbApiKey: String,
    val omdbBaseUrl: String,
    val omdbRequestsPerSecond: Double,
    val tvdbEnabled: Boolean,
    val tvdbApiKey: String,
    val tvdbPin: String,
    val tvdbBaseUrl: String,
    val tvdbRequestsPerSecond: Double,
    val httpTimeoutSeconds: Long,
    val matchAutoThreshold: Double,
    val workerDelayMs: Long,
    val workerMaxAttempts: Int,
    val workerConcurrency: Int,
    val scanIntervalMinutes: Int,
    val watchEnabled: Boolean,
    val playbackIgnoreBelowSeconds: Int,
    val playbackCompleteRemainingSeconds: Int,
) {
    fun tmdbConfigured(): Boolean = tmdbApiKey.isNotBlank()

    fun omdbConfigured(): Boolean = omdbApiKey.isNotBlank()

    fun tvdbConfigured(): Boolean = tvdbApiKey.isNotBlank()

    fun clientSignature(): String =
        listOf(
            tmdbBaseUrl,
            omdbBaseUrl,
            tvdbBaseUrl,
            httpTimeoutSeconds,
            tmdbRequestsPerSecond,
            omdbRequestsPerSecond,
            tvdbRequestsPerSecond,
        ).joinToString("|")
}
