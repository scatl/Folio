package com.scatl.folio.repository

import com.scatl.folio.entity.JobStatus
import com.scatl.folio.entity.MatchStatus
import com.scatl.folio.entity.ScrapeJob
import org.springframework.data.domain.Page
import org.springframework.data.domain.Pageable
import org.springframework.data.jpa.repository.EntityGraph
import org.springframework.data.jpa.repository.JpaRepository
import org.springframework.data.jpa.repository.Query
import org.springframework.data.repository.query.Param

interface ScrapeJobRepository : JpaRepository<ScrapeJob, Long> {
    @EntityGraph(attributePaths = ["libraryFile", "libraryFile.work", "libraryFile.mediaLibrary"])
    @Query(
        """
        select j from ScrapeJob j
        left join j.libraryFile f
        where (f is null or f.matchStatus <> :matched)
          and (
               (:mode = 'all')
            or (:mode = 'queued' and j.status = :queued)
            or (:mode = 'running' and j.status = :running)
            or (:mode = 'needs_review' and f.matchStatus = :needsReview)
            or (:mode = 'failed' and (f is null or f.matchStatus <> :needsReview)
                 and (j.status = :jobFailed or f.matchStatus = :matchFailed))
          )
        """,
    )
    fun search(
        @Param("mode") mode: String,
        @Param("queued") queued: JobStatus,
        @Param("running") running: JobStatus,
        @Param("jobFailed") jobFailed: JobStatus,
        @Param("matched") matched: MatchStatus,
        @Param("matchFailed") matchFailed: MatchStatus,
        @Param("needsReview") needsReview: MatchStatus,
        pageable: Pageable,
    ): Page<ScrapeJob>

    @EntityGraph(attributePaths = ["libraryFile"])
    @Query("select j from ScrapeJob j where j.id = :id")
    fun findDetailedById(@Param("id") id: Long): java.util.Optional<ScrapeJob>

    fun countByStatusIn(statuses: Collection<JobStatus>): Long

    @EntityGraph(attributePaths = ["libraryFile", "libraryFile.work", "libraryFile.mediaLibrary"])
    fun findByLibraryFile_Id(libraryFileId: Long): java.util.Optional<ScrapeJob>
}
