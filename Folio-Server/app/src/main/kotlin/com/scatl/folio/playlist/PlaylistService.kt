package com.scatl.folio.playlist

import com.scatl.folio.auth.LibraryAccessService
import com.scatl.folio.dto.WorkCard
import com.scatl.folio.entity.LibraryFile
import com.scatl.folio.library.LibraryQueryService
import com.scatl.folio.playback.PlaybackProgressService
import com.scatl.folio.repository.AppUserRepository
import com.scatl.folio.repository.EpisodeRepository
import com.scatl.folio.repository.LibraryFileRepository
import com.scatl.folio.repository.SeasonRepository
import com.scatl.folio.repository.WorkRepository
import org.springframework.http.HttpStatus
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import org.springframework.web.server.ResponseStatusException
import java.time.Instant

@Service
class PlaylistService(
    private val playlists: PlaylistRepository,
    private val items: PlaylistItemRepository,
    private val users: AppUserRepository,
    private val works: WorkRepository,
    private val files: LibraryFileRepository,
    private val seasons: SeasonRepository,
    private val episodes: EpisodeRepository,
    private val query: LibraryQueryService,
    private val libraryAccess: LibraryAccessService,
    private val playback: PlaybackProgressService,
) {
    @Transactional(readOnly = true)
    fun list(username: String, workId: Long?, limit: Int): List<PlaylistSummary> {
        val userId = requireUserId(username)
        val cap = limit.coerceIn(1, 100)
        return playlists.findByUserIdOrderByUpdatedAtDescIdDesc(userId)
            .take(cap)
            .map { toSummary(it, workId) }
    }

    @Transactional
    fun create(username: String, rawName: String, workId: Long?): PlaylistSummary {
        val userId = requireUserId(username)
        val now = Instant.now()
        val saved = playlists.save(
            Playlist().apply {
                this.userId = userId
                this.name = cleanName(rawName)
                this.createdAt = now
                this.updatedAt = now
            },
        )
        if (workId != null) insert(saved, workId)
        return toSummary(saved, workId)
    }

    @Transactional(readOnly = true)
    fun detail(username: String, playlistId: Long): PlaylistDetailView {
        val playlist = requireOwn(username, playlistId)
        return toDetail(username, playlist)
    }

    @Transactional
    fun rename(username: String, playlistId: Long, rawName: String): PlaylistDetailView {
        val playlist = requireOwn(username, playlistId)
        playlist.name = cleanName(rawName)
        playlist.updatedAt = Instant.now()
        playlists.save(playlist)
        return toDetail(username, playlist)
    }

    @Transactional
    fun delete(username: String, playlistId: Long): PlaylistRemoved {
        val playlist = requireOwn(username, playlistId)
        val id = playlist.id ?: playlistId
        items.deleteByPlaylistId(id)
        playlists.delete(playlist)
        return PlaylistRemoved(id)
    }

    @Transactional(readOnly = true)
    fun queue(username: String, playlistId: Long): List<PlaylistQueueEntry> {
        val playlist = requireOwn(username, playlistId)
        val id = playlist.id ?: return emptyList()
        val allowed = libraryAccess.readableLibraryIds()
        val out = mutableListOf<PlaylistQueueEntry>()
        for (row in items.findByPlaylistIdOrderByPositionAscIdAsc(id)) {
            val card = runCatching { query.workCard(row.workId) }.getOrNull() ?: continue
            for (playable in playables(card.id, card.kind, allowed)) {
                out += PlaylistQueueEntry(
                    workId = card.id,
                    workTitle = card.title,
                    kind = card.kind,
                    posterUrl = card.posterUrl,
                    fileId = playable.fileId,
                    fileName = playable.fileName,
                    seasonNumber = playable.seasonNumber,
                    episodeNumber = playable.episodeNumber,
                    episodeTitle = playable.episodeTitle,
                    label = if (card.kind == "series") {
                        episodeLabel(playable.seasonNumber, playable.episodeNumber, playable.episodeTitle)
                    } else {
                        card.title
                    },
                )
            }
        }
        return out
    }

    @Transactional
    fun add(username: String, playlistId: Long, workId: Long): PlaylistSummary {
        val playlist = requireOwn(username, playlistId)
        insert(playlist, workId)
        return toSummary(playlist, workId)
    }

    @Transactional
    fun reorder(username: String, playlistId: Long, workIds: List<Long>): PlaylistDetailView {
        val playlist = requireOwn(username, playlistId)
        val id = playlist.id ?: playlistId
        if (workIds.size != workIds.toSet().size) {
            throw ResponseStatusException(HttpStatus.BAD_REQUEST, "播放列表顺序有重复")
        }
        val rows = items.findByPlaylistIdOrderByPositionAscIdAsc(id)
        val byWork = rows.associateBy { it.workId }
        if (workIds.any { it !in byWork }) {
            throw ResponseStatusException(HttpStatus.BAD_REQUEST, "播放列表顺序不完整")
        }
        val incoming = workIds.filter { it in byWork }
        val rest = rows.map { it.workId }.filter { it !in incoming.toSet() }
        (incoming + rest).forEachIndexed { index, workId ->
            byWork.getValue(workId).position = index
        }
        items.saveAll(rows)
        playlist.updatedAt = Instant.now()
        playlists.save(playlist)
        return toDetail(username, playlist)
    }

    @Transactional
    fun remove(username: String, playlistId: Long, workId: Long): PlaylistDetailView {
        val playlist = requireOwn(username, playlistId)
        val id = playlist.id ?: playlistId
        val existing = items.findByPlaylistIdAndWorkId(id, workId)
        if (existing != null) {
            items.delete(existing)
            playlist.updatedAt = Instant.now()
            playlists.save(playlist)
        }
        return toDetail(username, playlist)
    }

    private fun insert(playlist: Playlist, workId: Long) {
        if (workId <= 0) throw ResponseStatusException(HttpStatus.BAD_REQUEST, "作品不存在")
        libraryAccess.requireWorkReadable(workId)
        if (!works.existsById(workId)) {
            throw ResponseStatusException(HttpStatus.NOT_FOUND, "作品不存在")
        }
        val playlistId = playlist.id ?: throw ResponseStatusException(HttpStatus.NOT_FOUND, "播放列表不存在")
        if (items.findByPlaylistIdAndWorkId(playlistId, workId) != null) return
        val position = items.findByPlaylistIdOrderByPositionAscIdAsc(playlistId)
            .maxOfOrNull { it.position }
            ?.plus(1)
            ?: 0
        items.save(
            PlaylistItem().apply {
                this.playlistId = playlistId
                this.workId = workId
                this.position = position
            },
        )
        playlist.updatedAt = Instant.now()
        playlists.save(playlist)
    }

    private fun toDetail(username: String, playlist: Playlist): PlaylistDetailView {
        val id = playlist.id ?: throw ResponseStatusException(HttpStatus.NOT_FOUND, "播放列表不存在")
        val allowed = libraryAccess.readableLibraryIds()
        val views = mutableListOf<PlaylistItemView>()
        for (row in items.findByPlaylistIdOrderByPositionAscIdAsc(id)) {
            val card = runCatching { query.workCard(row.workId) }.getOrNull() ?: continue
            views += toItem(username, card, allowed)
        }
        return PlaylistDetailView(id, playlist.name, views)
    }

    private fun toItem(username: String, card: WorkCard, allowed: Set<Long>?): PlaylistItemView {
        val playable = playables(card.id, card.kind, allowed)
        val start = startFile(username, card, playable, allowed)
        val kindLabel = if (card.kind == "series") "剧集" else "电影"
        val subtitle = when {
            card.kind == "series" && playable.isNotEmpty() -> "剧集 · ${playable.size} 集"
            card.year != null -> "$kindLabel · ${card.year}"
            else -> kindLabel
        }
        return PlaylistItemView(
            workId = card.id,
            workTitle = card.title,
            kind = card.kind,
            year = card.year,
            posterUrl = card.posterUrl,
            subtitle = subtitle,
            playFileId = start?.fileId,
            playFileName = start?.fileName,
            seasonNumber = start?.seasonNumber,
            episodeNumber = start?.episodeNumber,
            episodeTitle = start?.episodeTitle,
        )
    }

    private fun startFile(
        username: String,
        card: WorkCard,
        playable: List<Playable>,
        allowed: Set<Long>?,
    ): Playable? {
        if (playable.isEmpty()) return null
        val progress = runCatching { playback.latestForWork(username, card.id) }.getOrNull()
        val progressId = progress?.libraryFileId
        if (progress != null && progressId != null && files.findWorkIdById(progressId) == card.id) {
            val file = files.findById(progressId).orElse(null)
            if (file?.id != null && readable(file, allowed)) {
                val episodeHit = playable.firstOrNull {
                    it.seasonNumber != null &&
                        it.seasonNumber == progress.seasonNumber &&
                        it.episodeNumber == progress.episodeNumber
                }
                if (episodeHit != null) {
                    return episodeHit.copy(fileId = file.id!!, fileName = file.fileName)
                }
                if (card.kind != "series") {
                    return playable.first().copy(fileId = file.id!!, fileName = file.fileName)
                }
            }
        }
        return playable.first()
    }

    private fun playables(workId: Long, kind: String, allowed: Set<Long>?): List<Playable> {
        if (kind != "series") {
            val file = files.findByWork_IdOrderByIdAsc(workId).firstOrNull { readable(it, allowed) } ?: return emptyList()
            val fileId = file.id ?: return emptyList()
            return listOf(Playable(fileId, file.fileName, null, null, null))
        }
        val out = mutableListOf<Playable>()
        for (season in seasons.findByWorkIdOrderBySeasonNumberAsc(workId)) {
            val seasonId = season.id ?: continue
            for (episode in episodes.findBySeasonIdOrderByEpisodeNumberAsc(seasonId)) {
                val episodeId = episode.id ?: continue
                val file = readableEpisodeFile(workId, episodeId, allowed) ?: continue
                val fileId = file.id ?: continue
                out += Playable(
                    fileId = fileId,
                    fileName = file.fileName,
                    seasonNumber = season.seasonNumber,
                    episodeNumber = episode.episodeNumber,
                    episodeTitle = episode.title,
                )
            }
        }
        return out
    }

    private fun readableEpisodeFile(workId: Long, episodeId: Long, allowed: Set<Long>?): LibraryFile? {
        val first = files.findFirstByEpisode_IdOrderByIdAsc(episodeId)
        if (first != null && readable(first, allowed)) return first
        return files.findByWork_IdOrderByIdAsc(workId).firstOrNull { file ->
            file.episode?.id == episodeId && readable(file, allowed)
        }
    }

    private fun readable(file: LibraryFile, allowed: Set<Long>?): Boolean {
        if (allowed == null) return true
        val libraryId = file.mediaLibrary?.id ?: return false
        return libraryId in allowed
    }

    private fun toSummary(playlist: Playlist, workId: Long?): PlaylistSummary {
        val id = playlist.id ?: throw ResponseStatusException(HttpStatus.NOT_FOUND, "播放列表不存在")
        val rows = items.findByPlaylistIdOrderByPositionAscIdAsc(id)
        var poster: String? = null
        var count = 0
        var contains = false
        for (row in rows) {
            if (workId != null && row.workId == workId) contains = true
            val card = runCatching { query.workCard(row.workId) }.getOrNull() ?: continue
            if (poster == null) poster = card.posterUrl
            count += 1
        }
        return PlaylistSummary(
            id = id,
            name = playlist.name,
            itemCount = count,
            posterUrl = poster,
            contains = contains,
        )
    }

    private fun requireOwn(username: String, playlistId: Long): Playlist {
        val userId = requireUserId(username)
        return playlists.findByIdAndUserId(playlistId, userId)
            ?: throw ResponseStatusException(HttpStatus.NOT_FOUND, "播放列表不存在")
    }

    private fun requireUserId(username: String): Long =
        users.findByUsername(username.trim())?.id
            ?: throw ResponseStatusException(HttpStatus.UNAUTHORIZED, "未登录")

    private fun cleanName(raw: String): String {
        val name = raw.trim()
        if (name.isEmpty()) throw ResponseStatusException(HttpStatus.BAD_REQUEST, "请填写播放列表名称")
        if (name.length > 40) throw ResponseStatusException(HttpStatus.BAD_REQUEST, "名称最多 40 个字")
        return name
    }

    private fun episodeLabel(season: Int?, episode: Int?, title: String?): String {
        if (season == null || episode == null) return title?.trim().orEmpty().ifEmpty { "剧集" }
        val code = "S${season.toString().padStart(2, '0')}E${episode.toString().padStart(2, '0')}"
        val name = title?.trim().orEmpty()
        return if (name.isEmpty()) code else "$code $name"
    }

    private data class Playable(
        val fileId: Long,
        val fileName: String,
        val seasonNumber: Int?,
        val episodeNumber: Int?,
        val episodeTitle: String?,
    )
}
