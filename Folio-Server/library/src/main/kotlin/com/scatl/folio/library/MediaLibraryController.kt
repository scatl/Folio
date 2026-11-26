package com.scatl.folio.library

import com.scatl.folio.dto.CollectionCard
import com.scatl.folio.dto.BrowseEntryView
import com.scatl.folio.dto.BrowseView
import com.scatl.folio.dto.CreateMediaLibraryRequest
import com.scatl.folio.dto.MediaLibraryFileView
import com.scatl.folio.dto.MediaLibraryView
import com.scatl.folio.dto.ReorderLibrariesRequest
import com.scatl.folio.dto.WorkCard
import com.scatl.folio.entity.LibraryFile
import com.scatl.folio.dto.BrowseResult
import com.scatl.folio.dto.MediaLibraryDetail
import jakarta.validation.Valid
import org.springframework.validation.annotation.Validated
import org.springframework.web.bind.annotation.DeleteMapping
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.PutMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.RestController

@Validated
@RestController
@RequestMapping("/api/libraries")
class MediaLibraryController(
    private val service: MediaLibraryService,
    private val query: LibraryQueryService,
    private val libraryAccess: com.scatl.folio.auth.LibraryAccessService,
) {
    @GetMapping
    fun list(): List<MediaLibraryView> = service.listViews()

    @GetMapping("/browse")
    fun browse(@RequestParam(required = false) path: String?): BrowseView =
        service.browse(path).toView()

    @GetMapping("/{id}/collections")
    fun collections(@PathVariable id: Long): List<CollectionCard> {
        service.get(id)
        return query.listCollections(id)
    }

    @GetMapping("/{id}/collections/works")
    fun collectionWorks(
        @PathVariable id: Long,
        @RequestParam collectionId: String,
    ): List<WorkCard> {
        service.get(id)
        return query.collectionWorks(id, collectionId)
    }

    @GetMapping("/{id}")
    fun get(@PathVariable id: Long): MediaLibraryView {
        val detail = service.get(id)
        val libraryId = detail.library.id ?: id
        return detail.toView(service.workCount(libraryId), accessOf(libraryId))
    }

    @PutMapping("/order")
    fun reorder(@Valid @RequestBody body: ReorderLibrariesRequest): Map<String, Any> {
        service.reorder(body.ids)
        return mapOf("status" to "ok")
    }

    @PostMapping
    fun create(@Valid @RequestBody body: CreateMediaLibraryRequest): MediaLibraryView =
        service.create(body.name, body.kind, body.rootPath).toView(0, "WRITE")

    @DeleteMapping("/{id}")
    fun delete(@PathVariable id: Long): Map<String, Any> {
        service.delete(id)
        return mapOf("id" to id, "status" to "deleted")
    }

    @PostMapping("/{id}/scan")
    fun scan(@PathVariable id: Long): Map<String, Any> {
        service.scan(id)
        return mapOf("id" to id, "status" to "queued")
    }

    private fun accessOf(libraryId: Long): String =
        if (libraryAccess.canWrite(libraryId)) "WRITE" else "READ"
}

private fun MediaLibraryDetail.toView(workCount: Long, access: String) = MediaLibraryView(
    id = requireNotNull(library.id),
    name = library.name,
    kind = library.kind.name,
    rootPath = library.rootPath,
    files = files.map { it.toView() },
    createdAt = library.createdAt,
    workCount = workCount,
    access = access,
)

private fun LibraryFile.toView() = MediaLibraryFileView(
    id = requireNotNull(id),
    fileName = fileName,
    locator = locator,
    status = matchStatus.name,
)

private fun BrowseResult.toView() = BrowseView(
    path = path,
    parent = parent,
    directories = directories.map { BrowseEntryView(it.name, it.path) },
)

