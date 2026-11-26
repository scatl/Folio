package com.scatl.folio.watchlist

import org.springframework.data.jpa.repository.JpaRepository

interface WatchlistRepository : JpaRepository<WatchlistEntry, Long> {
    fun findByUserIdOrderByCreatedAtDescIdDesc(userId: Long): List<WatchlistEntry>

    fun findByUserIdAndWorkId(userId: Long, workId: Long): WatchlistEntry?
}
