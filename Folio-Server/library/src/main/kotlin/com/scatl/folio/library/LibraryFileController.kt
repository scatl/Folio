package com.scatl.folio.library

import com.scatl.folio.dto.EmbeddedSubtitleView
import com.scatl.folio.dto.FileAccepted
import com.scatl.folio.dto.FileView
import com.scatl.folio.dto.ManualMatchRequest
import com.scatl.folio.dto.ManualMatchResult
import com.scatl.folio.dto.MatchCandidateView
import com.scatl.folio.dto.PageResult
import com.scatl.folio.dto.RankedCandidate
import com.scatl.folio.dto.ReviewFileRow
import com.scatl.folio.dto.MediaSegmentsView
import com.scatl.folio.dto.VideoDetail
import jakarta.servlet.http.HttpServletRequest
import jakarta.servlet.http.HttpServletResponse
import jakarta.validation.Valid
import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.Size
import org.springframework.http.HttpHeaders
import org.springframework.http.HttpRange
import org.springframework.http.HttpStatus
import org.springframework.http.MediaType
import org.springframework.http.ResponseEntity
import org.springframework.util.StreamUtils
import org.springframework.validation.annotation.Validated
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.RestController
import org.springframework.web.server.ResponseStatusException
import java.nio.channels.Channels
import java.nio.channels.FileChannel
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardOpenOption

@Validated
@RestController
@RequestMapping("/api/library/files")
class LibraryFileController(
    private val ingest: FileIngestService,
    private val query: LibraryQueryService,
    private val manualMatch: ManualMatchService,
    private val probe: MediaProbeService,
    private val externalSubtitles: ExternalSubtitleService,
    private val embeddedSubtitles: EmbeddedSubtitleService,
    private val mediaSegments: MediaSegmentService,
    private val libraryAccess: com.scatl.folio.auth.LibraryAccessService,
) {
    @PostMapping
    fun create(
        @RequestParam
        @NotBlank(message = "不能为空")
        @Size(max = 512, message = "最长 512 个字符")
        fileName: String,
        @RequestParam(required = false)
        @Size(max = 1024, message = "最长 1024 个字符")
        locator: String?,
    ): ResponseEntity<FileAccepted> {
        val file = ingest.submit(fileName, locator)
        probe.probeAndSave(requireNotNull(file.id))
        return ResponseEntity.accepted().body(FileAccepted(requireNotNull(file.id), file.matchStatus.name))
    }

    @GetMapping
    fun list(
        @RequestParam(defaultValue = "needs_review") status: String,
        @RequestParam(defaultValue = "0") page: Int,
        @RequestParam(defaultValue = "50") size: Int,
    ): PageResult<ReviewFileRow> {
        if (status != "needs_review") {
            throw ResponseStatusException(HttpStatus.BAD_REQUEST, "目前仅支持 status=needs_review")
        }
        val result = manualMatch.listForReview(page, size)
        return PageResult(
            result.content.map { query.reviewFileRow(it) },
            result.number,
            result.size,
            result.totalElements,
            result.totalPages,
        )
    }

    @GetMapping("/{id}")
    fun get(@PathVariable id: Long): FileView = query.file(id)

    @GetMapping("/{id}/subtitles")
    fun subtitles(@PathVariable id: Long): List<String> {
        libraryAccess.requireFileReadable(id)
        return externalSubtitles.listNames(id)
    }

    @GetMapping("/{id}/subtitles/content")
    fun subtitleContent(
        @PathVariable id: Long,
        @RequestParam
        @NotBlank(message = "不能为空")
        @Size(max = 512, message = "最长 512 个字符")
        name: String,
        response: HttpServletResponse,
    ) {
        libraryAccess.requireFileReadable(id)
        val path = externalSubtitles.resolve(id, name)
        response.contentType = subtitleContentType(name).toString()
        response.setContentLengthLong(Files.size(path))
        Files.newInputStream(path).use { input ->
            StreamUtils.copy(input, response.outputStream)
        }
    }

    @GetMapping("/{id}/embedded-subtitles")
    fun listEmbedded(@PathVariable id: Long): List<EmbeddedSubtitleView> {
        libraryAccess.requireFileReadable(id)
        return embeddedSubtitles.list(id)
    }

    @GetMapping("/{id}/embedded-subtitles/content")
    fun embeddedSubtitleContent(
        @PathVariable id: Long,
        @RequestParam index: Int,
        response: HttpServletResponse,
    ) {
        libraryAccess.requireFileReadable(id)
        val bytes = embeddedSubtitles.extract(id, index)
        response.contentType = "text/x-ssa;charset=UTF-8"
        response.setContentLength(bytes.size)
        response.outputStream.write(bytes)
    }

    @GetMapping("/{id}/content")
    fun content(
        @PathVariable id: Long,
        request: HttpServletRequest,
        response: HttpServletResponse,
    ) {
        val row = query.contentFile(id)
        val path = Path.of(row.locator)
        if (!Files.isRegularFile(path)) {
            throw ResponseStatusException(HttpStatus.NOT_FOUND, "文件不存在")
        }
        val length = Files.size(path)
        val mediaType = contentType(row.fileName)
        response.setHeader(HttpHeaders.ACCEPT_RANGES, "bytes")
        response.contentType = mediaType.toString()

        val rangeHeader = request.getHeader(HttpHeaders.RANGE)
        if (rangeHeader.isNullOrBlank()) {
            response.status = HttpStatus.OK.value()
            response.setContentLengthLong(length)
            Files.newInputStream(path).use { input ->
                StreamUtils.copy(input, response.outputStream)
            }
            return
        }

        val ranges = try {
            HttpRange.parseRanges(rangeHeader)
        } catch (_: IllegalArgumentException) {
            response.status = HttpStatus.REQUESTED_RANGE_NOT_SATISFIABLE.value()
            response.setHeader(HttpHeaders.CONTENT_RANGE, "bytes */$length")
            return
        }
        if (ranges.isEmpty()) {
            response.status = HttpStatus.REQUESTED_RANGE_NOT_SATISFIABLE.value()
            response.setHeader(HttpHeaders.CONTENT_RANGE, "bytes */$length")
            return
        }

        val range = ranges.first()
        val start = range.getRangeStart(length)
        val end = range.getRangeEnd(length)
        if (start >= length) {
            response.status = HttpStatus.REQUESTED_RANGE_NOT_SATISFIABLE.value()
            response.setHeader(HttpHeaders.CONTENT_RANGE, "bytes */$length")
            return
        }
        val count = end - start + 1
        response.status = HttpStatus.PARTIAL_CONTENT.value()
        response.setHeader(HttpHeaders.CONTENT_RANGE, "bytes $start-$end/$length")
        response.setContentLengthLong(count)
        FileChannel.open(path, StandardOpenOption.READ).use { channel ->
            val out = Channels.newChannel(response.outputStream)
            var transferred = 0L
            while (transferred < count) {
                val n = channel.transferTo(start + transferred, count - transferred, out)
                if (n <= 0) break
                transferred += n
            }
        }
    }

    @PostMapping("/{id}/probe")
    fun probeFile(@PathVariable id: Long): ReviewFileRow {
        libraryAccess.requireFileWritable(id)
        query.reviewFile(id)
        probe.probeAndSave(id)
        return query.reviewFile(id)
    }

    @GetMapping("/{id}/detail")
    fun detail(@PathVariable id: Long): VideoDetail = query.detail(id)

    @GetMapping("/{id}/segments")
    fun segments(@PathVariable id: Long): MediaSegmentsView = mediaSegments.forFile(id)

    @GetMapping("/{id}/candidates")
    fun candidates(
        @PathVariable id: Long,
        @RequestParam(required = false) q: String?,
        @RequestParam(required = false) kind: String?,
        @RequestParam(required = false) year: Int?,
    ): List<MatchCandidateView> {
        libraryAccess.requireFileWritable(id)
        return manualMatch.searchCandidates(id, q, kind, year).map { it.toView() }
    }

    @PostMapping("/{id}/match")
    fun match(
        @PathVariable id: Long,
        @Valid @RequestBody body: ManualMatchRequest,
    ): ManualMatchResult {
        libraryAccess.requireFileWritable(id)
        manualMatch.confirm(id, body.kind, body.tmdbId, body.year, body.season, body.episode, body.scope)
        return ManualMatchResult(id, null, "queued")
    }

    private fun contentType(fileName: String): MediaType {
        val type = when (fileName.substringAfterLast('.', "").lowercase()) {
            "mp4", "m4v" -> "video/mp4"
            "mkv" -> "video/x-matroska"
            "webm" -> "video/webm"
            "avi" -> "video/x-msvideo"
            "mov" -> "video/quicktime"
            "ts", "m2ts" -> "video/mp2t"
            "wmv" -> "video/x-ms-wmv"
            else -> "application/octet-stream"
        }
        return MediaType.parseMediaType(type)
    }

    private fun subtitleContentType(fileName: String): MediaType {
        val type = when (fileName.substringAfterLast('.', "").lowercase()) {
            "srt" -> "application/x-subrip"
            "vtt" -> "text/vtt"
            "ass", "ssa" -> "text/x-ssa"
            else -> "application/octet-stream"
        }
        return MediaType.parseMediaType(type)
    }

    private fun RankedCandidate.toView() = MatchCandidateView(
        provider,
        kind,
        externalId,
        title,
        originalTitle,
        year,
        overview,
        posterUrl,
        score,
    )
}

