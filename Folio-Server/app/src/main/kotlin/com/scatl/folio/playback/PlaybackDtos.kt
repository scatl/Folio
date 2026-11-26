package com.scatl.folio.playback

import jakarta.validation.constraints.Min
import jakarta.validation.constraints.NotNull

data class WorkWatchRequest(
    @field:NotNull
    val watched: Boolean?,
)

data class WorkWatchView(
    val workId: Long,
    val watchState: String,
)

data class PlaybackProgressEvent(
    val workId: Long,
    val username: String,
)

data class PlaybackProgressUpsertRequest(
    @field:NotNull
    @field:Min(1)
    val libraryFileId: Long,
    @field:NotNull
    @field:Min(0)
    val positionMs: Long,
    @field:Min(0)
    val durationMs: Long? = null,
)

data class PlaybackProgressView(
    val libraryFileId: Long,
    val workId: Long?,
    val episodeId: Long?,
    val fileName: String? = null,
    val positionMs: Long,
    val durationMs: Long?,
    val completed: Boolean,
    val resumePositionMs: Long?,
    val updatedAt: String,
    val seasonNumber: Int? = null,
    val episodeNumber: Int? = null,
    val episodeTitle: String? = null,
)

data class ContinueWatchView(
    val workId: Long,
    val workTitle: String,
    val kind: String,
    val posterUrl: String?,
    val libraryFileId: Long,
    val fileName: String? = null,
    val positionMs: Long,
    val durationMs: Long?,
    val completed: Boolean,
    val resumePositionMs: Long?,
    val progressRatio: Double,
    val seasonNumber: Int?,
    val episodeNumber: Int?,
    val episodeTitle: String?,
    val subtitle: String,
)
