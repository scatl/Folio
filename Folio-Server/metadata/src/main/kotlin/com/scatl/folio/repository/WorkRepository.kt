package com.scatl.folio.repository

import com.scatl.folio.catalog.OwnerType
import com.scatl.folio.catalog.WorkKind
import com.scatl.folio.entity.Work
import org.springframework.data.domain.Page
import org.springframework.data.domain.Pageable
import org.springframework.data.jpa.repository.JpaRepository
import org.springframework.data.jpa.repository.Query
import org.springframework.data.repository.query.Param

interface WorkRepository : JpaRepository<Work, Long> {
    fun findByKind(kind: WorkKind): List<Work>

    @Query(
        """
        select w from Work w
        where w.collectionExternalId is not null
          and w.collectionExternalId <> ''
          and exists (
            select 1 from LibraryFile f
            where f.work = w and f.mediaLibrary.id = :libraryId
          )
        """,
    )
    fun findCollectedInLibrary(@Param("libraryId") libraryId: Long): List<Work>

    @Query(
        """
        select w from Work w
        where w.collectionExternalId = :collectionId
          and exists (
            select 1 from LibraryFile f
            where f.work = w
              and (:restrictLibraries = false or f.mediaLibrary.id in :libraryIds)
          )
        order by w.releaseYear asc, w.id asc
        """,
    )
    fun findLocalInCollection(
        @Param("collectionId") collectionId: String,
        @Param("restrictLibraries") restrictLibraries: Boolean,
        @Param("libraryIds") libraryIds: Collection<Long>,
    ): List<Work>

    @Query(
        """
        select w from Work w
        where (:kind is null or w.kind = :kind)
          and exists (
            select 1 from LibraryFile f
            where f.work = w
              and (:restrictLibraries = false or f.mediaLibrary.id in :libraryIds)
          )
          and (
            :raw is null or :raw = ''
            or $MATCH_RAW
            or (
              :year is not null
              and w.releaseYear = :year
              and (:text is null or :text = '' or $MATCH_TEXT)
            )
          )
        """,
        countQuery = """
        select count(w.id) from Work w
        where (:kind is null or w.kind = :kind)
          and exists (
            select 1 from LibraryFile f
            where f.work = w
              and (:restrictLibraries = false or f.mediaLibrary.id in :libraryIds)
          )
          and (
            :raw is null or :raw = ''
            or $MATCH_RAW
            or (
              :year is not null
              and w.releaseYear = :year
              and (:text is null or :text = '' or $MATCH_TEXT)
            )
          )
        """,
    )
    fun search(
        @Param("kind") kind: WorkKind?,
        @Param("restrictLibraries") restrictLibraries: Boolean,
        @Param("libraryIds") libraryIds: Collection<Long>,
        @Param("raw") raw: String?,
        @Param("text") text: String?,
        @Param("year") year: Int?,
        @Param("ownerType") ownerType: OwnerType,
        pageable: Pageable,
    ): Page<Work>
}

private const val MATCH_RAW = """
    lower(w.originalTitle) like lower(concat('%', :raw, '%'))
    or lower(w.collectionName) like lower(concat('%', :raw, '%'))
    or exists (
        select 1 from WorkTranslation translation
        where translation.workId = w.id
          and lower(translation.title) like lower(concat('%', :raw, '%'))
    )
    or exists (
        select 1 from LibraryFile named
        where named.work = w and lower(named.fileName) like lower(concat('%', :raw, '%'))
    )
    or exists (
        select 1 from WorkGenre link, Genre genre
        where link.workId = w.id and genre.id = link.genreId
          and lower(genre.name) like lower(concat('%', :raw, '%'))
    )
    or exists (
        select 1 from Credit credit
        where credit.ownerType = :ownerType
          and credit.ownerId = w.id
          and lower(credit.person.name) like lower(concat('%', :raw, '%'))
    )
"""

private const val MATCH_TEXT = """
    lower(w.originalTitle) like lower(concat('%', :text, '%'))
    or lower(w.collectionName) like lower(concat('%', :text, '%'))
    or exists (
        select 1 from WorkTranslation translation
        where translation.workId = w.id
          and lower(translation.title) like lower(concat('%', :text, '%'))
    )
    or exists (
        select 1 from LibraryFile named
        where named.work = w and lower(named.fileName) like lower(concat('%', :text, '%'))
    )
    or exists (
        select 1 from WorkGenre link, Genre genre
        where link.workId = w.id and genre.id = link.genreId
          and lower(genre.name) like lower(concat('%', :text, '%'))
    )
    or exists (
        select 1 from Credit credit
        where credit.ownerType = :ownerType
          and credit.ownerId = w.id
          and lower(credit.person.name) like lower(concat('%', :text, '%'))
    )
"""
