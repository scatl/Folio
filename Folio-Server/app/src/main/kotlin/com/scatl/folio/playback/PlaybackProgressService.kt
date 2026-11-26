package com.scatl.folio.playback

import com.scatl.folio.entity.Episode
import com.scatl.folio.entity.LibraryFile
import com.scatl.folio.entity.Season
import com.scatl.folio.entity.Work
import com.scatl.folio.auth.LibraryAccessService
import com.scatl.folio.library.LibraryQueryService
import com.scatl.folio.library.ScrapeEventHub
import com.scatl.folio.library.WatchStates
import com.scatl.folio.repository.AppUserRepository
import com.scatl.folio.settings.FolioSettings
import com.scatl.folio.repository.EpisodeRepository
import com.scatl.folio.repository.LibraryFileRepository
import com.scatl.folio.repository.SeasonRepository
import com.scatl.folio.repository.WorkRepository
import org.springframework.http.HttpStatus
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import org.springframework.transaction.support.TransactionSynchronization
import org.springframework.transaction.support.TransactionSynchronizationManager
import org.springframework.web.server.ResponseStatusException
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

@Service
class PlaybackProgressService(
    private val progress: PlaybackProgressRepository,
    private val users: AppUserRepository,
    private val files: LibraryFileRepository,
    private val works: WorkRepository,
    private val episodes: EpisodeRepository,
    private val seasons: SeasonRepository,
    private val query: LibraryQueryService,
    private val settings: FolioSettings,
    private val events: ScrapeEventHub,
    private val libraryAccess: LibraryAccessService,
) {
    private val timeFmt = DateTimeFormatter.ISO_OFFSET_DATE_TIME

    fun requireUserId(username: String): Long =
        users.findByUsername(username.trim())?.id
            ?: throw ResponseStatusException(HttpStatus.UNAUTHORIZED, "未登录")

    @Transactional
    fun upsert(username: String, body: PlaybackProgressUpsertRequest): PlaybackProgressView {
        val userId = requireUserId(username)
        val file = files.findById(body.libraryFileId).orElseThrow {
            ResponseStatusException(HttpStatus.NOT_FOUND, "文件不存在")
        }
        val duration = body.durationMs?.takeIf { it > 0 } ?: file.durationMs
        val position = body.positionMs.coerceAtLeast(0)
        val rules = playbackRules()
        val completed = isCompleted(position, duration, rules.completeRemainingMs)
        val storedPosition = when {
            completed -> duration ?: position
            position < rules.ignoreBelowMs -> 0
            else -> position
        }
        val row = progress.findByUserIdAndLibraryFileId(userId, file.id!!)
            ?: PlaybackProgress().apply {
                this.userId = userId
                this.libraryFileId = file.id!!
            }
        row.workId = file.work?.id
        row.episodeId = file.episode?.id
        row.positionMs = storedPosition
        row.durationMs = duration
        row.completed = completed
        row.updatedAt = Instant.now()
        val saved = progress.save(row)
        val workId = saved.workId
        if (workId != null) {
            afterCommit {
                events.publish("playback.progress", PlaybackProgressEvent(workId, username))
            }
        }
        return toView(saved, file)
    }

    @Transactional(readOnly = true)
    fun getForFile(username: String, libraryFileId: Long): PlaybackProgressView? {
        val userId = requireUserId(username)
        val row = progress.findByUserIdAndLibraryFileId(userId, libraryFileId) ?: return null
        val file = files.findById(libraryFileId).orElse(null)
        return toView(row, file)
    }

    @Transactional(readOnly = true)
    fun workWatch(username: String, workId: Long): WorkWatchView {
        requireUserId(username)
        return WorkWatchView(workId, currentWatchState(username, workId))
    }

    @Transactional
    fun setWorkWatched(username: String, workId: Long, watched: Boolean): WorkWatchView {
        val userId = requireUserId(username)
        val target = readableFiles(workId)
        if (target.isEmpty()) {
            throw ResponseStatusException(HttpStatus.NOT_FOUND, "没有可标记的文件")
        }
        val fileIds = target.map { requireNotNull(it.id) }
        if (watched) {
            val now = Instant.now()
            for (file in target) {
                val fileId = requireNotNull(file.id)
                val row = progress.findByUserIdAndLibraryFileId(userId, fileId)
                    ?: PlaybackProgress().apply {
                        this.userId = userId
                        this.libraryFileId = fileId
                    }
                row.workId = workId
                row.episodeId = file.episode?.id
                row.positionMs = file.durationMs ?: 0
                row.durationMs = file.durationMs
                row.completed = true
                row.updatedAt = now
                progress.save(row)
            }
        } else if (fileIds.isNotEmpty()) {
            progress.deleteByUserIdAndLibraryFileIdIn(userId, fileIds)
        }
        afterCommit {
            events.publish("playback.progress", PlaybackProgressEvent(workId, username))
        }
        return WorkWatchView(workId, currentWatchState(username, workId))
    }

    @Transactional(readOnly = true)
    fun latestForWork(username: String, workId: Long): PlaybackProgressView? {
        val userId = requireUserId(username)
        val row = progress.findByUserIdAndWorkIdOrderByUpdatedAtDesc(userId, workId).firstOrNull()
            ?: return null
        val resolved = resolvePlayTarget(userId, row) ?: return null
        return toViewFromTarget(row, resolved)
    }

    @Transactional(readOnly = true)
    fun continueWatching(username: String, limit: Int): List<ContinueWatchView> {
        val userId = requireUserId(username)
        val cap = limit.coerceIn(1, 50)
        val seenWorks = linkedSetOf<Long>()
        val out = mutableListOf<ContinueWatchView>()
        for (row in progress.findLatestRowsPerWork(userId)) {
            val workId = row.workId ?: continue
            if (!seenWorks.add(workId)) continue
            val resolved = resolvePlayTarget(userId, row) ?: continue
            val work = works.findById(workId).orElse(null) ?: continue
            out += toContinue(row, work, resolved)
            if (out.size >= cap) break
        }
        return out
    }

    /** 未看完 → 原文件续看；已看完剧集 → 下一集尚未看完的文件；电影看完 / 后面都看完 → null。 */
    private fun resolvePlayTarget(userId: Long, row: PlaybackProgress): PlayTarget? {
        if (!row.completed) {
            val file = files.findById(row.libraryFileId).orElse(null) ?: return null
            return PlayTarget(
                file = file,
                positionMs = row.positionMs,
                durationMs = row.durationMs ?: file.durationMs,
                completed = false,
                episodeId = row.episodeId,
            )
        }
        val next = findNextEpisodeFile(userId, row) ?: return null
        return PlayTarget(
            file = next,
            positionMs = 0,
            durationMs = next.durationMs,
            completed = false,
            episodeId = next.episode?.id,
        )
    }

    private fun findNextEpisodeFile(userId: Long, row: PlaybackProgress): LibraryFile? {
        val workId = row.workId ?: return null
        val episodeId = row.episodeId ?: return null
        val current = episodes.findById(episodeId).orElse(null) ?: return null
        val currentSeason = seasons.findById(current.seasonId).orElse(null) ?: return null
        for (season in seasons.findByWorkIdOrderBySeasonNumberAsc(workId)) {
            if (season.seasonNumber < currentSeason.seasonNumber) continue
            val seasonId = season.id ?: continue
            for (episode in episodes.findBySeasonIdOrderByEpisodeNumberAsc(seasonId)) {
                if (season.seasonNumber == currentSeason.seasonNumber &&
                    episode.episodeNumber <= current.episodeNumber
                ) {
                    continue
                }
                val episodeIdNext = episode.id ?: continue
                val file = files.findFirstByEpisode_IdOrderByIdAsc(episodeIdNext) ?: continue
                val fileId = file.id ?: continue
                val played = progress.findByUserIdAndLibraryFileId(userId, fileId)
                if (played?.completed == true) continue
                return file
            }
        }
        return null
    }

    private fun toView(row: PlaybackProgress, file: LibraryFile?): PlaybackProgressView {
        val episode = row.episodeId?.let { episodes.findById(it).orElse(null) }
        val season = episode?.let { seasons.findById(it.seasonId).orElse(null) }
        return PlaybackProgressView(
            libraryFileId = row.libraryFileId,
            workId = row.workId,
            episodeId = row.episodeId,
            fileName = file?.fileName,
            positionMs = row.positionMs,
            durationMs = row.durationMs,
            completed = row.completed,
            resumePositionMs = resumePosition(row.positionMs, row.durationMs, row.completed, playbackRules()),
            updatedAt = timeFmt.format(row.updatedAt.atOffset(ZoneOffset.UTC)),
            seasonNumber = season?.seasonNumber,
            episodeNumber = episode?.episodeNumber,
            episodeTitle = episode?.title,
        )
    }

    private fun toViewFromTarget(row: PlaybackProgress, target: PlayTarget): PlaybackProgressView {
        val episode = target.episodeId?.let { episodes.findById(it).orElse(null) }
        val season = episode?.let { seasons.findById(it.seasonId).orElse(null) }
        val advanced = target.file.id != row.libraryFileId
        return PlaybackProgressView(
            libraryFileId = target.file.id!!,
            workId = row.workId,
            episodeId = target.episodeId,
            fileName = target.file.fileName,
            positionMs = target.positionMs,
            durationMs = target.durationMs,
            completed = false,
            resumePositionMs = if (advanced) null else resumePosition(target.positionMs, target.durationMs, false, playbackRules()),
            updatedAt = timeFmt.format(row.updatedAt.atOffset(ZoneOffset.UTC)),
            seasonNumber = season?.seasonNumber,
            episodeNumber = episode?.episodeNumber,
            episodeTitle = episode?.title,
        )
    }

    private fun toContinue(row: PlaybackProgress, work: Work, target: PlayTarget): ContinueWatchView {
        val episode = target.episodeId?.let { episodes.findById(it).orElse(null) }
        val season = episode?.let { seasons.findById(it.seasonId).orElse(null) }
        val advanced = target.file.id != row.libraryFileId
        val resume = if (advanced) null else resumePosition(target.positionMs, target.durationMs, false, playbackRules())
        val duration = target.durationMs
        val ratio = if (!advanced && duration != null && duration > 0) {
            (target.positionMs.toDouble() / duration).coerceIn(0.0, 1.0)
        } else {
            0.0
        }
        val card = runCatching { query.workCard(work.id!!) }.getOrNull()
        val subtitle = buildSubtitle(work.kind.name, season, episode, resume, nextEpisode = advanced)
        return ContinueWatchView(
            workId = work.id!!,
            workTitle = card?.title ?: work.originalTitle,
            kind = work.kind.name,
            posterUrl = card?.posterUrl,
            libraryFileId = target.file.id!!,
            fileName = target.file.fileName,
            positionMs = target.positionMs,
            durationMs = target.durationMs,
            completed = false,
            resumePositionMs = resume,
            progressRatio = ratio,
            seasonNumber = season?.seasonNumber,
            episodeNumber = episode?.episodeNumber,
            episodeTitle = episode?.title,
            subtitle = subtitle,
        )
    }

    private fun buildSubtitle(
        kind: String,
        season: Season?,
        episode: Episode?,
        resumeMs: Long?,
        nextEpisode: Boolean,
    ): String {
        val parts = mutableListOf<String>()
        if (kind == "series" && season != null && episode != null) {
            parts += "S${season.seasonNumber}E${episode.episodeNumber}"
        }
        when {
            nextEpisode -> parts += "下一集"
            resumeMs != null && resumeMs > 0 -> parts += "已看至 ${formatClock(resumeMs)}"
            else -> parts += "继续播放"
        }
        return parts.joinToString(" · ")
    }

    private data class PlayTarget(
        val file: LibraryFile,
        val positionMs: Long,
        val durationMs: Long?,
        val completed: Boolean,
        val episodeId: Long?,
    )

    private fun readableFiles(workId: Long): List<LibraryFile> {
        libraryAccess.requireWorkReadable(workId)
        val allowed = libraryAccess.readableLibraryIds()
        return files.findByWork_IdOrderByIdAsc(workId).filter { file ->
            val libraryId = file.mediaLibrary?.id ?: return@filter false
            allowed == null || libraryId in allowed
        }
    }

    private fun currentWatchState(username: String, workId: Long): String {
        val userId = requireUserId(username)
        val target = readableFiles(workId)
        if (target.isEmpty()) return WatchStates.UNWATCHED
        val rows = progress.findByUserIdAndWorkIdOrderByUpdatedAtDesc(userId, workId)
        val completed = rows.filter { it.completed }.map { it.libraryFileId }.toSet()
        val started = rows.filter { !it.completed && it.positionMs > 0 }.map { it.libraryFileId }.toSet()
        val ids = target.map { requireNotNull(it.id) }
        val kind = works.findById(workId).orElse(null)?.kind?.name ?: "movie"
        return WatchStates.of(kind, ids.size, ids.count { it in completed }, ids.count { it in started })
    }

    private fun afterCommit(block: () -> Unit) {
        if (TransactionSynchronizationManager.isSynchronizationActive()) {
            TransactionSynchronizationManager.registerSynchronization(
                object : TransactionSynchronization {
                    override fun afterCommit() = block()
                },
            )
        } else {
            block()
        }
    }

    private fun playbackRules(): PlaybackRules {
        val current = settings.current()
        return PlaybackRules(
            ignoreBelowMs = current.playbackIgnoreBelowSeconds.coerceAtLeast(0) * 1000L,
            completeRemainingMs = current.playbackCompleteRemainingSeconds.coerceAtLeast(0) * 1000L,
        )
    }

    private data class PlaybackRules(
        val ignoreBelowMs: Long,
        val completeRemainingMs: Long,
    )

    companion object {
        fun isCompleted(positionMs: Long, durationMs: Long?, completeRemainingMs: Long): Boolean {
            if (durationMs == null || durationMs <= 0) return false
            return durationMs - positionMs <= completeRemainingMs
        }

        private fun resumePosition(
            positionMs: Long,
            durationMs: Long?,
            completed: Boolean,
            rules: PlaybackRules,
        ): Long? {
            if (completed) return null
            if (positionMs < rules.ignoreBelowMs) return null
            if (durationMs != null && durationMs > 0 && durationMs - positionMs <= rules.completeRemainingMs) {
                return null
            }
            return positionMs
        }

        fun formatClock(ms: Long): String {
            val total = (ms / 1000).toInt().coerceAtLeast(0)
            val h = total / 3600
            val m = (total % 3600) / 60
            val s = total % 60
            return if (h > 0) {
                "%d:%02d:%02d".format(h, m, s)
            } else {
                "%d:%02d".format(m, s)
            }
        }
    }
}
