package com.scatl.folio.home

import com.scatl.folio.dto.HomeSetupView
import com.scatl.folio.dto.HomeView
import com.scatl.folio.dto.MediaLibraryView
import com.scatl.folio.dto.PageResult
import com.scatl.folio.dto.WorkCard
import com.scatl.folio.library.LibraryQueryService
import com.scatl.folio.library.MediaLibraryService
import com.scatl.folio.playback.ContinueWatchView
import com.scatl.folio.playback.PlaybackProgressService
import com.scatl.folio.playlist.PlaylistService
import com.scatl.folio.playlist.PlaylistSummary
import com.scatl.folio.settings.AppSettingsService
import com.scatl.folio.watchlist.WatchlistItemView
import com.scatl.folio.watchlist.WatchlistService
import org.slf4j.LoggerFactory
import org.springframework.security.core.context.SecurityContextHolder
import org.springframework.stereotype.Service

@Service
class HomeService(
    private val libraries: MediaLibraryService,
    private val query: LibraryQueryService,
    private val settings: AppSettingsService,
    private val playback: PlaybackProgressService,
    private val watchlist: WatchlistService,
    private val playlists: PlaylistService,
) {
    private val log = LoggerFactory.getLogger(javaClass)

    fun home(): HomeView =
        HomeView(
            libraries = loadLibraries(),
            recent = loadRecent(),
            continueWatching = loadContinueWatching(),
            watchlist = loadWatchlist(),
            playlists = loadPlaylists(),
            setup = loadSetup(),
        )

    private fun loadContinueWatching(): List<ContinueWatchView>? {
        val name = SecurityContextHolder.getContext().authentication?.name?.trim().orEmpty()
        if (name.isEmpty() || name == "anonymousUser") return emptyList()
        return runCatching { playback.continueWatching(name, 20) }
            .onFailure { log.warn("首页继续观看加载失败: {}", it.message) }
            .getOrNull()
    }

    private fun loadWatchlist(): List<WatchlistItemView>? {
        val name = SecurityContextHolder.getContext().authentication?.name?.trim().orEmpty()
        if (name.isEmpty() || name == "anonymousUser") return emptyList()
        return runCatching { watchlist.list(name, 20) }
            .onFailure { log.warn("首页想看加载失败: {}", it.message) }
            .getOrNull()
    }

    private fun loadPlaylists(): List<PlaylistSummary>? {
        val name = SecurityContextHolder.getContext().authentication?.name?.trim().orEmpty()
        if (name.isEmpty() || name == "anonymousUser") return emptyList()
        return runCatching { playlists.list(name, null, 50) }
            .onFailure { log.warn("首页播放列表加载失败: {}", it.message) }
            .getOrNull()
    }

    private fun loadLibraries(): List<MediaLibraryView>? =
        runCatching { libraries.listViews() }
            .onFailure { log.warn("首页资料库块加载失败: {}", it.message) }
            .getOrNull()

    private fun loadRecent(): PageResult<WorkCard>? =
        runCatching {
            query.listRecentScrapedWorks(limit = 50)
        }.onFailure { log.warn("首页近期作品块加载失败: {}", it.message) }.getOrNull()

    private fun loadSetup(): HomeSetupView? =
        runCatching {
            HomeSetupView(tmdbConfigured = settings.view().tmdbApiKeyConfigured)
        }.onFailure { log.warn("首页设置块加载失败: {}", it.message) }.getOrNull()
}
