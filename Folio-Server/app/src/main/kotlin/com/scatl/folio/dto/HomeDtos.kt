package com.scatl.folio.dto

import com.scatl.folio.playback.ContinueWatchView
import com.scatl.folio.playlist.PlaylistSummary
import com.scatl.folio.watchlist.WatchlistItemView

data class HomeView(
    val libraries: List<MediaLibraryView>?,
    val recent: PageResult<WorkCard>?,
    val continueWatching: List<ContinueWatchView>?,
    val watchlist: List<WatchlistItemView>?,
    val playlists: List<PlaylistSummary>?,
    val setup: HomeSetupView?,
)

data class HomeSetupView(
    val tmdbConfigured: Boolean,
)
