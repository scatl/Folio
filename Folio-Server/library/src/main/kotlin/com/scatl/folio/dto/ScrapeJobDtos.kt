package com.scatl.folio.dto

import java.math.BigDecimal
import java.time.Instant

data class ScrapeJobRow(
    val id: Long,
    val status: String,
    val attempts: Int,
    val maxAttempts: Int,
    val nextRunAt: Instant,
    val lastError: String?,
    val progress: String?,
    val createdAt: Instant,
    val updatedAt: Instant,
    val fileId: Long,
    val fileName: String,
    val locator: String,
    val matchStatus: String,
    val parsedTitle: String?,
    val parsedYear: Int?,
    val parsedSeason: Int?,
    val parsedEpisode: Int?,
    val confidence: BigDecimal?,
    val message: String?,
    val workId: Long?,
    val mediaLibraryId: Long?,
    val mediaLibraryName: String?,
)

data class DeletedId(val id: Long)

data class ScrapeJobStats(
    val active: Long,
)

