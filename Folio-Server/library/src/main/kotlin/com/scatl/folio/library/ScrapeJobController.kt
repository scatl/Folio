package com.scatl.folio.library

import com.scatl.folio.dto.DeletedId
import com.scatl.folio.dto.PageResult
import com.scatl.folio.dto.ScrapeJobRow
import com.scatl.folio.dto.ScrapeJobStats
import com.scatl.folio.dto.toRow
import org.springframework.web.bind.annotation.DeleteMapping
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/api/scrape-jobs")
class ScrapeJobController(
    private val query: ScrapeJobQueryService,
) {
    @GetMapping
    fun list(
        @RequestParam(required = false) status: String?,
        @RequestParam(defaultValue = "0") page: Int,
        @RequestParam(defaultValue = "50") size: Int,
    ): PageResult<ScrapeJobRow> {
        val result = query.list(status, page, size)
        return PageResult(
            result.content.map { it.toRow() },
            result.number,
            result.size,
            result.totalElements,
            result.totalPages,
        )
    }

    @GetMapping("/stats")
    fun stats(): ScrapeJobStats = ScrapeJobStats(query.activeCount())

    @PostMapping("/{id}/retry")
    fun retry(@PathVariable id: Long): ScrapeJobRow = query.retry(id).toRow()

    @DeleteMapping("/{id}")
    fun delete(@PathVariable id: Long): DeletedId {
        query.delete(id)
        return DeletedId(id)
    }
}

