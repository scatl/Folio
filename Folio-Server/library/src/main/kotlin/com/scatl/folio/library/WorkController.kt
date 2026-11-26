package com.scatl.folio.library

import com.scatl.folio.dto.EpisodeDetailView
import com.scatl.folio.dto.PageResult
import com.scatl.folio.dto.SeasonDetailView
import com.scatl.folio.dto.WorkBrowseQuery
import com.scatl.folio.dto.WorkCard
import com.scatl.folio.dto.WorkFacets
import com.scatl.folio.dto.WorkView
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/api/works")
class WorkController(private val query: LibraryQueryService) {
    @GetMapping
    fun list(browse: WorkBrowseQuery): PageResult<WorkCard> = query.listWorks(browse)

    @GetMapping("/facets")
    fun facets(
        @RequestParam(required = false) libraryId: Long?,
        @RequestParam(required = false) personQ: String?,
    ): WorkFacets = query.facets(libraryId, personQ)

    @GetMapping("/detail")
    fun detailByExternal(
        @RequestParam provider: String,
        @RequestParam externalId: String,
        @RequestParam kind: String,
    ): WorkView = query.workByExternal(provider, externalId, kind)

    @GetMapping("/{id}/card")
    fun card(@PathVariable id: Long): WorkCard = query.workCard(id)

    @GetMapping("/{id}/collection")
    fun collection(@PathVariable id: Long): List<WorkCard> = query.collectionSiblings(id)

    @PostMapping("/{id}/refresh")
    fun refresh(@PathVariable id: Long): WorkView = query.refreshWork(id)

    @GetMapping("/{id}")
    fun get(@PathVariable id: Long): WorkView = query.work(id)

    @GetMapping("/{id}/seasons/{seasonNumber}")
    fun season(
        @PathVariable id: Long,
        @PathVariable seasonNumber: Int,
    ): SeasonDetailView = query.season(id, seasonNumber)

    @GetMapping("/{id}/seasons/{seasonNumber}/episodes/{episodeNumber}")
    fun episode(
        @PathVariable id: Long,
        @PathVariable seasonNumber: Int,
        @PathVariable episodeNumber: Int,
    ): EpisodeDetailView = query.episode(id, seasonNumber, episodeNumber)
}

