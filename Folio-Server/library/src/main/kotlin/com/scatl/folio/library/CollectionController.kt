package com.scatl.folio.library

import com.scatl.folio.dto.CollectionView
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/api/collections")
class CollectionController(
    private val query: LibraryQueryService,
) {
    @GetMapping("/{id}")
    fun get(@PathVariable id: String): CollectionView = query.collection(id)
}
