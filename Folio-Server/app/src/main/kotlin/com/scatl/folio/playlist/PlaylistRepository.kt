package com.scatl.folio.playlist

import org.springframework.data.jpa.repository.JpaRepository

interface PlaylistRepository : JpaRepository<Playlist, Long> {
    fun findByUserIdOrderByUpdatedAtDescIdDesc(userId: Long): List<Playlist>

    fun findByIdAndUserId(id: Long, userId: Long): Playlist?
}

interface PlaylistItemRepository : JpaRepository<PlaylistItem, Long> {
    fun findByPlaylistIdOrderByPositionAscIdAsc(playlistId: Long): List<PlaylistItem>

    fun findByPlaylistIdAndWorkId(playlistId: Long, workId: Long): PlaylistItem?

    fun deleteByPlaylistId(playlistId: Long)
}
