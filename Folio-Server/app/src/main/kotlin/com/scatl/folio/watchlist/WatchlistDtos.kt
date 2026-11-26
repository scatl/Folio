package com.scatl.folio.watchlist

import jakarta.validation.constraints.NotNull

data class WatchlistRequest(
    @field:NotNull
    val wanted: Boolean?,
)

data class WatchlistFlagView(
    val workId: Long,
    val wanted: Boolean,
)

data class WatchlistItemView(
    val workId: Long,
    val workTitle: String,
    val kind: String,
    val year: Int?,
    val posterUrl: String?,
    val subtitle: String,
)
