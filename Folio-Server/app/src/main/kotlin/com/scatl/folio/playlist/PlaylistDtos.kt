package com.scatl.folio.playlist

import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.Size

data class PlaylistCreateRequest(
    @field:NotBlank
    @field:Size(max = 40)
    val name: String,
    val workId: Long? = null,
)

data class PlaylistRenameRequest(
    @field:NotBlank
    @field:Size(max = 40)
    val name: String,
)

data class PlaylistItemRequest(
    val workId: Long,
)

data class PlaylistReorderRequest(
    val workIds: List<Long> = emptyList(),
)

data class PlaylistSummary(
    val id: Long,
    val name: String,
    val itemCount: Int,
    val posterUrl: String?,
    val contains: Boolean = false,
)

data class PlaylistItemView(
    val workId: Long,
    val workTitle: String,
    val kind: String,
    val year: Int?,
    val posterUrl: String?,
    val subtitle: String,
    val playFileId: Long?,
    val playFileName: String?,
    val seasonNumber: Int?,
    val episodeNumber: Int?,
    val episodeTitle: String?,
)

data class PlaylistDetailView(
    val id: Long,
    val name: String,
    val items: List<PlaylistItemView>,
)

data class PlaylistQueueEntry(
    val workId: Long,
    val workTitle: String,
    val kind: String,
    val posterUrl: String?,
    val fileId: Long,
    val fileName: String,
    val seasonNumber: Int?,
    val episodeNumber: Int?,
    val episodeTitle: String?,
    val label: String,
)

data class PlaylistRemoved(
    val id: Long,
)
