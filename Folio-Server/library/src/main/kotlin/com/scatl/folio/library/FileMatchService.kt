package com.scatl.folio.library

import com.scatl.folio.entity.JobStatus
import com.scatl.folio.entity.MatchStatus
import com.scatl.folio.parse.ParsedName
import com.scatl.folio.repository.EpisodeRepository
import com.scatl.folio.repository.LibraryFileRepository
import com.scatl.folio.repository.ScrapeJobRepository
import com.scatl.folio.repository.WorkRepository
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.Instant

@Service
open class FileMatchService(
    private val files: LibraryFileRepository,
    private val works: WorkRepository,
    private val episodes: EpisodeRepository,
    private val scrapeJobs: ScrapeJobRepository,
    private val events: ScrapeEventPublisher,
) {
    @Transactional(readOnly = true)
    open fun fileName(fileId: Long): String = files.findById(fileId).orElseThrow().fileName

    @Transactional(readOnly = true)
    open fun locator(fileId: Long): String = files.findById(fileId).orElseThrow().locator

    @Transactional
    open fun saveParsed(fileId: Long, parsed: ParsedName) {
        val file = files.findById(fileId).orElseThrow()
        file.parsedTitle = parsed.title
        file.parsedYear = parsed.year
        file.parsedSeason = parsed.season
        file.parsedEpisode = parsed.episode
        file.parsedImdbId = parsed.imdbId
        file.updatedAt = Instant.now()
    }

    @Transactional
    open fun markMatched(fileId: Long, workId: Long, episodeId: Long?, confidence: Double, message: String?) {
        val file = files.findById(fileId).orElseThrow()
        file.work = works.getReferenceById(workId)
        file.episode = episodeId?.let { episodes.getReferenceById(it) }
        file.matchStatus = MatchStatus.matched
        file.confidence = decimal(confidence)
        file.message = limit(message)
        file.updatedAt = Instant.now()
        finishManualJob(fileId)
        notifyJobForFile(fileId)
    }

    /** 人工匹配已提交，先离开「待人工」，任务显示为执行中。 */
    @Transactional
    open fun beginManualMatch(fileId: Long) {
        val file = files.findById(fileId).orElseThrow()
        val now = Instant.now()
        file.matchStatus = MatchStatus.pending
        file.message = limit("人工匹配中")
        file.updatedAt = now
        scrapeJobs.findByLibraryFile_Id(fileId).ifPresent { job ->
            job.status = JobStatus.running
            job.progress = "人工匹配中"
            job.lastError = null
            job.updatedAt = now
            events.notifyJobAfterCommit(requireNotNull(job.id))
        }
    }

    @Transactional
    open fun markReview(fileId: Long, confidence: Double, message: String) {
        val file = files.findById(fileId).orElseThrow()
        file.matchStatus = MatchStatus.needs_review
        file.confidence = decimal(confidence)
        file.message = limit(message)
        file.updatedAt = Instant.now()
        notifyJobForFile(fileId)
    }

    @Transactional
    open fun markFailed(fileId: Long, message: String) {
        val file = files.findById(fileId).orElseThrow()
        if (file.matchStatus == MatchStatus.matched) return
        file.matchStatus = MatchStatus.failed
        file.message = limit(message)
        file.updatedAt = Instant.now()
        finishManualJob(fileId)
        notifyJobForFile(fileId)
    }

    private fun finishManualJob(fileId: Long) {
        val job = scrapeJobs.findByLibraryFile_Id(fileId).orElse(null) ?: return
        if (job.progress != "人工匹配中") return
        val file = files.findById(fileId).orElse(null) ?: return
        when (file.matchStatus) {
            MatchStatus.matched -> {
                job.status = JobStatus.succeeded
                job.progress = "已完成"
                job.lastError = null
            }
            MatchStatus.failed -> {
                job.status = JobStatus.failed
                job.progress = "失败"
            }
            else -> return
        }
        job.updatedAt = Instant.now()
    }

    private fun notifyJobForFile(fileId: Long) {
        scrapeJobs.findByLibraryFile_Id(fileId).ifPresent { job ->
            events.notifyJobAfterCommit(requireNotNull(job.id))
        }
    }

    @Transactional
    open fun note(fileId: Long, message: String) {
        val file = files.findById(fileId).orElseThrow()
        if (file.matchStatus == MatchStatus.pending) {
            file.message = limit(message)
            file.updatedAt = Instant.now()
        }
    }

    private fun decimal(confidence: Double): BigDecimal =
        BigDecimal.valueOf(confidence).setScale(4, RoundingMode.HALF_UP)

    companion object {
        fun limit(value: String?): String? {
            if (value == null) return null
            val trimmed = value.trim()
            return if (trimmed.length <= 1024) trimmed else trimmed.substring(0, 1024)
        }
    }
}
