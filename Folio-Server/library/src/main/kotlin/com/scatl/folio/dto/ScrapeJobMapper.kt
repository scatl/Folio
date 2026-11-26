package com.scatl.folio.dto

import com.scatl.folio.entity.ScrapeJob

fun ScrapeJob.toRow(): ScrapeJobRow {
    val file = requireNotNull(libraryFile)
    return ScrapeJobRow(
        id = requireNotNull(id),
        status = status.name,
        attempts = attempts,
        maxAttempts = maxAttempts,
        nextRunAt = nextRunAt,
        lastError = lastError,
        progress = progress,
        createdAt = createdAt,
        updatedAt = updatedAt,
        fileId = requireNotNull(file.id),
        fileName = file.fileName,
        locator = file.locator,
        matchStatus = file.matchStatus.name,
        parsedTitle = file.parsedTitle,
        parsedYear = file.parsedYear,
        parsedSeason = file.parsedSeason,
        parsedEpisode = file.parsedEpisode,
        confidence = file.confidence,
        message = file.message,
        workId = file.work?.id,
        mediaLibraryId = file.mediaLibrary?.id,
        mediaLibraryName = file.mediaLibrary?.name,
    )
}

data class ScrapeDeletedEvent(val id: Long)

data class WorkRemovedEvent(val workId: Long)
