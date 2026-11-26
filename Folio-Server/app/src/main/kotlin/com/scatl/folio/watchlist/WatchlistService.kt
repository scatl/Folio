package com.scatl.folio.watchlist

import com.scatl.folio.auth.LibraryAccessService
import com.scatl.folio.dto.WorkCard
import com.scatl.folio.library.LibraryQueryService
import com.scatl.folio.repository.AppUserRepository
import com.scatl.folio.repository.WorkRepository
import org.springframework.http.HttpStatus
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import org.springframework.web.server.ResponseStatusException
import java.time.Instant

@Service
class WatchlistService(
    private val entries: WatchlistRepository,
    private val users: AppUserRepository,
    private val works: WorkRepository,
    private val query: LibraryQueryService,
    private val libraryAccess: LibraryAccessService,
) {
    @Transactional(readOnly = true)
    fun list(username: String, limit: Int): List<WatchlistItemView> {
        val userId = requireUserId(username)
        val cap = limit.coerceIn(1, 50)
        val out = mutableListOf<WatchlistItemView>()
        for (row in entries.findByUserIdOrderByCreatedAtDescIdDesc(userId)) {
            val card = runCatching { query.workCard(row.workId) }.getOrNull() ?: continue
            out += toItem(card)
            if (out.size >= cap) break
        }
        return out
    }

    @Transactional(readOnly = true)
    fun flag(username: String, workId: Long): WatchlistFlagView {
        val userId = requireUserId(username)
        libraryAccess.requireWorkReadable(workId)
        val wanted = entries.findByUserIdAndWorkId(userId, workId) != null
        return WatchlistFlagView(workId, wanted)
    }

    @Transactional
    fun set(username: String, workId: Long, wanted: Boolean): WatchlistFlagView {
        val userId = requireUserId(username)
        libraryAccess.requireWorkReadable(workId)
        if (!works.existsById(workId)) {
            throw ResponseStatusException(HttpStatus.NOT_FOUND, "作品不存在")
        }
        val existing = entries.findByUserIdAndWorkId(userId, workId)
        if (wanted && existing == null) {
            entries.save(
                WatchlistEntry().apply {
                    this.userId = userId
                    this.workId = workId
                    this.createdAt = Instant.now()
                },
            )
        } else if (!wanted && existing != null) {
            entries.delete(existing)
        }
        return WatchlistFlagView(workId, wanted)
    }

    private fun requireUserId(username: String): Long =
        users.findByUsername(username.trim())?.id
            ?: throw ResponseStatusException(HttpStatus.UNAUTHORIZED, "未登录")

    private fun toItem(card: WorkCard): WatchlistItemView {
        val kindLabel = if (card.kind == "series") "剧集" else "电影"
        val year = card.year
        return WatchlistItemView(
            workId = card.id,
            workTitle = card.title,
            kind = card.kind,
            year = year,
            posterUrl = card.posterUrl,
            subtitle = if (year != null) "$kindLabel · $year" else kindLabel,
        )
    }
}
