package com.scatl.folio.repository

import com.scatl.folio.entity.LibraryFile
import com.scatl.folio.entity.MatchStatus
import com.scatl.folio.library.SeriesFileLink
import org.springframework.data.domain.Page
import org.springframework.data.domain.Pageable
import org.springframework.data.jpa.repository.EntityGraph
import org.springframework.data.jpa.repository.JpaRepository
import org.springframework.data.jpa.repository.Query
import org.springframework.data.repository.query.Param

interface LibraryFileRepository : JpaRepository<LibraryFile, Long> {
    @EntityGraph(attributePaths = ["work", "episode"])
    @Query("select f from LibraryFile f where f.id = :id")
    fun findWithMatchById(@Param("id") id: Long): java.util.Optional<LibraryFile>

    fun findByMatchStatus(
        status: MatchStatus,
        pageable: Pageable,
    ): Page<LibraryFile>

    fun findByWork_IdOrderByIdAsc(workId: Long): List<LibraryFile>

    fun findFirstByEpisode_IdOrderByIdAsc(episodeId: Long): LibraryFile?

    @Query("select f.work.id from LibraryFile f where f.id = :id")
    fun findWorkIdById(@Param("id") id: Long): Long?

    fun findByMediaLibrary_IdOrderByIdAsc(mediaLibraryId: Long): List<LibraryFile>

    @Query(
        """
        select count(distinct f.work.id) from LibraryFile f
        where f.mediaLibrary.id = :libraryId and f.work is not null
        """,
    )
    fun countDistinctWorks(@Param("libraryId") libraryId: Long): Long

    @Query(
        """
        select f.mediaLibrary.id, count(distinct f.work.id)
        from LibraryFile f
        where f.work is not null
        group by f.mediaLibrary.id
        """,
    )
    fun countDistinctWorksByLibrary(): List<Array<Any>>

    @Query(
        """
        select f from LibraryFile f
        where f.matchStatus = com.scatl.folio.entity.MatchStatus.matched
          and f.parsedSeason is not null
          and f.work is not null
          and f.parsedTitle is not null
        """,
    )
    fun findMatchedSeriesFiles(): List<LibraryFile>

    @Query(
        """
        select new com.scatl.folio.library.SeriesFileLink(
            f.id, f.work.id, f.episode.id, f.parsedTitle, f.parsedYear, f.parsedSeason, f.parsedEpisode
        )
        from LibraryFile f
        where f.matchStatus = com.scatl.folio.entity.MatchStatus.matched
          and f.parsedSeason is not null
          and f.parsedEpisode is not null
          and f.parsedTitle is not null
          and f.work is not null
        """,
    )
    fun findMatchedSeriesLinks(): List<SeriesFileLink>

    fun countByWork_IdAndIdNot(workId: Long, id: Long): Long

    @Query(
        """
        select f.episode.id
        from LibraryFile f
        where f.work.id = :workId and f.episode is not null
        """,
    )
    fun findEpisodeIdsByWorkId(@Param("workId") workId: Long): List<Long>

    @Query(
        """
        select distinct f.work.id
        from LibraryFile f
        where f.work.id in :workIds
        """,
    )
    fun findWorkIdsWithFiles(@Param("workIds") workIds: Collection<Long>): List<Long>

    @EntityGraph(attributePaths = ["work", "episode"])
    @Query(
        """
        select f from LibraryFile f
        where f.matchStatus = com.scatl.folio.entity.MatchStatus.matched
          and f.work is not null
          and f.fingerprintedAt is null
          and f.id > :afterId
        order by f.id asc
        """,
    )
    fun findPendingFingerprints(@Param("afterId") afterId: Long, pageable: Pageable): List<LibraryFile>

    /** 按作品去重后的最近匹配时间倒序（电影=单文件作品，剧集=整部剧）。 */
    @Query(
        """
        select f.work.id
        from LibraryFile f
        where f.matchStatus = :matched
          and f.work is not null
          and (:restrictLibraries = false or f.mediaLibrary.id in :libraryIds)
        group by f.work.id
        order by max(f.updatedAt) desc, f.work.id desc
        """,
    )
    fun findRecentlyMatchedWorkIds(
        @Param("matched") matched: MatchStatus,
        @Param("restrictLibraries") restrictLibraries: Boolean,
        @Param("libraryIds") libraryIds: Collection<Long>,
        pageable: Pageable,
    ): List<Long>

    @Query(
        """
        select count(distinct f.work.id)
        from LibraryFile f
        where f.matchStatus = :matched
          and f.work is not null
          and (:restrictLibraries = false or f.mediaLibrary.id in :libraryIds)
        """,
    )
    fun countDistinctMatchedWorks(
        @Param("matched") matched: MatchStatus,
        @Param("restrictLibraries") restrictLibraries: Boolean,
        @Param("libraryIds") libraryIds: Collection<Long>,
    ): Long
}
