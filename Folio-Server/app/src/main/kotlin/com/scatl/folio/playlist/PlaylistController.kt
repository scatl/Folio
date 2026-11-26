package com.scatl.folio.playlist

import jakarta.validation.Valid
import org.springframework.security.core.Authentication
import org.springframework.validation.annotation.Validated
import org.springframework.web.bind.annotation.DeleteMapping
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PatchMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.PutMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.RestController

@Validated
@RestController
@RequestMapping("/api/playlists")
class PlaylistController(
    private val playlists: PlaylistService,
) {
    @GetMapping
    fun list(
        authentication: Authentication,
        @RequestParam(required = false) workId: Long?,
        @RequestParam(defaultValue = "50") limit: Int,
    ): List<PlaylistSummary> = playlists.list(authentication.name, workId, limit)

    @PostMapping
    fun create(
        authentication: Authentication,
        @Valid @RequestBody body: PlaylistCreateRequest,
    ): PlaylistSummary = playlists.create(authentication.name, body.name, body.workId)

    @GetMapping("/{id}")
    fun detail(
        authentication: Authentication,
        @PathVariable id: Long,
    ): PlaylistDetailView = playlists.detail(authentication.name, id)

    @PatchMapping("/{id}")
    fun rename(
        authentication: Authentication,
        @PathVariable id: Long,
        @Valid @RequestBody body: PlaylistRenameRequest,
    ): PlaylistDetailView = playlists.rename(authentication.name, id, body.name)

    @DeleteMapping("/{id}")
    fun delete(
        authentication: Authentication,
        @PathVariable id: Long,
    ): PlaylistRemoved = playlists.delete(authentication.name, id)

    @GetMapping("/{id}/queue")
    fun queue(
        authentication: Authentication,
        @PathVariable id: Long,
    ): List<PlaylistQueueEntry> = playlists.queue(authentication.name, id)

    @PutMapping("/{id}/items/order")
    fun reorder(
        authentication: Authentication,
        @PathVariable id: Long,
        @Valid @RequestBody body: PlaylistReorderRequest,
    ): PlaylistDetailView = playlists.reorder(authentication.name, id, body.workIds)

    @PostMapping("/{id}/items")
    fun addItem(
        authentication: Authentication,
        @PathVariable id: Long,
        @Valid @RequestBody body: PlaylistItemRequest,
    ): PlaylistSummary = playlists.add(authentication.name, id, body.workId)

    @DeleteMapping("/{id}/items/{workId}")
    fun removeItem(
        authentication: Authentication,
        @PathVariable id: Long,
        @PathVariable workId: Long,
    ): PlaylistDetailView = playlists.remove(authentication.name, id, workId)
}
