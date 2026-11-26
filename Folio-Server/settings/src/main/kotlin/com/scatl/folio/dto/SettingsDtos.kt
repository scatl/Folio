package com.scatl.folio.dto

import jakarta.validation.constraints.DecimalMax
import jakarta.validation.constraints.DecimalMin
import jakarta.validation.constraints.Max
import jakarta.validation.constraints.Min
import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.Positive

data class AppSettingsView(
    val tmdbApiKeyConfigured: Boolean,
    val tmdbBaseUrl: String,
    val tmdbImageBaseUrl: String,
    val tmdbLanguage: String,
    val tmdbSearchLanguage: String,
    val tmdbRequestsPerSecond: Double,
    val omdbApiKeyConfigured: Boolean,
    val omdbBaseUrl: String,
    val omdbRequestsPerSecond: Double,
    val tvdbEnabled: Boolean,
    val tvdbApiKeyConfigured: Boolean,
    val tvdbPinConfigured: Boolean,
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
)

data class AppSettingsUpdateRequest(
    val tmdbApiKey: String? = null,
    @field:NotBlank(message = "不能为空")
    val tmdbBaseUrl: String,
    @field:NotBlank(message = "不能为空")
    val tmdbImageBaseUrl: String,
    @field:NotBlank(message = "不能为空")
    val tmdbLanguage: String,
    @field:NotBlank(message = "不能为空")
    val tmdbSearchLanguage: String,
    @field:Positive(message = "必须大于 0")
    val tmdbRequestsPerSecond: Double,
    val omdbApiKey: String? = null,
    @field:NotBlank(message = "不能为空")
    val omdbBaseUrl: String,
    @field:Positive(message = "必须大于 0")
    val omdbRequestsPerSecond: Double,
    val tvdbEnabled: Boolean = true,
    val tvdbApiKey: String? = null,
    val tvdbPin: String? = null,
    @field:NotBlank(message = "不能为空")
    val tvdbBaseUrl: String,
    @field:Positive(message = "必须大于 0")
    val tvdbRequestsPerSecond: Double,
    @field:Min(1, message = "至少 1 秒")
    @field:Max(120, message = "最多 120 秒")
    val httpTimeoutSeconds: Long,
    @field:DecimalMin("0.1", message = "不能低于 0.1")
    @field:DecimalMax("1.0", message = "不能高于 1")
    val matchAutoThreshold: Double,
    @field:Min(200, message = "至少 200 毫秒")
    @field:Max(60_000, message = "最多 60 秒")
    val workerDelayMs: Long,
    @field:Min(1, message = "至少 1 次")
    @field:Max(10, message = "最多 10 次")
    val workerMaxAttempts: Int,
    @field:Min(1, message = "至少 1")
    @field:Max(64, message = "最多 64")
    val workerConcurrency: Int,
    @field:Min(1, message = "至少 1 分钟")
    @field:Max(1440, message = "最多 1440 分钟")
    val scanIntervalMinutes: Int,
    val watchEnabled: Boolean,
    @field:Min(0, message = "不能小于 0 秒")
    @field:Max(3600, message = "最多 3600 秒")
    val playbackIgnoreBelowSeconds: Int,
    @field:Min(0, message = "不能小于 0 秒")
    @field:Max(3600, message = "最多 3600 秒")
    val playbackCompleteRemainingSeconds: Int,
)
