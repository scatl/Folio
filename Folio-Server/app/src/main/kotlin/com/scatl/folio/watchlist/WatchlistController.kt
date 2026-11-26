package com.scatl.folio.watchlist

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
@RequestMapping("/api/watchlist")
class WatchlistController(
    private val watchlist: WatchlistService,
) {
    @GetMapping
    fun list(
        authentication: Authentication,
        @RequestParam(defaultValue = "20") limit: Int,
    ): List<WatchlistItemView> = watchlist.list(authentication.name, limit)

    @GetMapping("/works/{workId}")
    fun flag(
        authentication: Authentication,
        @PathVariable workId: Long,
    ): WatchlistFlagView = watchlist.flag(authentication.name, workId)

    @PutMapping("/works/{workId}")
    fun set(
        authentication: Authentication,
        @PathVariable workId: Long,
        @Valid @RequestBody body: WatchlistRequest,
    ): WatchlistFlagView = watchlist.set(authentication.name, workId, body.wanted == true)
}
