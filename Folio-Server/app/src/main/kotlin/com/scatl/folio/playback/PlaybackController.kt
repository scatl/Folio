package com.scatl.folio.playback

import jakarta.validation.Valid
import org.springframework.security.core.Authentication
import org.springframework.validation.annotation.Validated
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PutMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.RestController

@Validated
@RestController
@RequestMapping("/api/playback")
class PlaybackController(
    private val playback: PlaybackProgressService,
) {
    @PutMapping("/progress")
    fun upsert(
        authentication: Authentication,
        @Valid @RequestBody body: PlaybackProgressUpsertRequest,
    ): PlaybackProgressView = playback.upsert(authentication.name, body)

    @GetMapping("/progress")
    fun getForFile(
        authentication: Authentication,
        @RequestParam libraryFileId: Long,
    ): PlaybackProgressView? = playback.getForFile(authentication.name, libraryFileId)

    @GetMapping("/progress/work/{workId}")
    fun latestForWork(
        authentication: Authentication,
        @PathVariable workId: Long,
    ): PlaybackProgressView? = playback.latestForWork(authentication.name, workId)

    @GetMapping("/works/{workId}")
    fun workWatch(
        authentication: Authentication,
        @PathVariable workId: Long,
    ): WorkWatchView = playback.workWatch(authentication.name, workId)

    @PutMapping("/works/{workId}")
    fun setWorkWatch(
        authentication: Authentication,
        @PathVariable workId: Long,
        @Valid @RequestBody body: WorkWatchRequest,
    ): WorkWatchView = playback.setWorkWatched(authentication.name, workId, body.watched == true)

    @GetMapping("/continue")
    fun continueWatching(
        authentication: Authentication,
        @RequestParam(defaultValue = "20") limit: Int,
    ): List<ContinueWatchView> = playback.continueWatching(authentication.name, limit)
}
