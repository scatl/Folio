package com.scatl.folio.library

import com.scatl.folio.dto.PersonDetailView
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/api/people")
class PersonController(
    private val query: LibraryQueryService,
) {
    @GetMapping("/{provider}/{externalId}")
    fun get(
        @PathVariable provider: String,
        @PathVariable externalId: String,
    ): PersonDetailView = query.person(provider, externalId)

    @PostMapping("/{provider}/{externalId}/refresh")
    fun refresh(
        @PathVariable provider: String,
        @PathVariable externalId: String,
    ): PersonDetailView = query.refreshPerson(provider, externalId)
}
