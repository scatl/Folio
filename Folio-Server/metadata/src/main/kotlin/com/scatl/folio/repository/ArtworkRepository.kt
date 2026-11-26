package com.scatl.folio.repository

import com.scatl.folio.entity.Artwork
import com.scatl.folio.catalog.ArtworkKind
import com.scatl.folio.catalog.ExternalProvider
import com.scatl.folio.catalog.OwnerType
import org.springframework.data.domain.Page
import org.springframework.data.domain.Pageable
import org.springframework.data.jpa.repository.JpaRepository
import org.springframework.data.jpa.repository.Modifying
import org.springframework.data.jpa.repository.Query
import org.springframework.data.repository.query.Param

interface ArtworkRepository : JpaRepository<Artwork, Long> {
    fun findByOwnerTypeAndOwnerIdOrderByIdAsc(ownerType: OwnerType, ownerId: Long): List<Artwork>

    fun existsByOwnerTypeAndOwnerIdAndProviderAndRemoteUrl(
        ownerType: OwnerType,
        ownerId: Long,
        provider: ExternalProvider,
        remoteUrl: String,
    ): Boolean

    fun findByOwnerTypeAndOwnerIdIn(ownerType: OwnerType, ownerIds: Collection<Long>): List<Artwork>

    fun findByOwnerTypeAndOwnerIdInAndKindIn(
        ownerType: OwnerType,
        ownerIds: Collection<Long>,
        kinds: Collection<ArtworkKind>,
    ): List<Artwork>

    fun findByOwnerTypeAndKind(ownerType: OwnerType, kind: ArtworkKind, pageable: Pageable): Page<Artwork>

    @Query(
        value = """
            SELECT a.remote_url
            FROM artworks a
            INNER JOIN (
                SELECT MIN(id) AS id
                FROM artworks
                WHERE owner_type = :ownerType
                  AND kind = :kind
                  AND remote_url <> ''
                GROUP BY owner_id
                ORDER BY RAND()
                LIMIT 60
            ) picked ON picked.id = a.id
            ORDER BY RAND()
        """,
        nativeQuery = true,
    )
    fun findRandomWorkPosterUrls(
        @Param("ownerType") ownerType: String,
        @Param("kind") kind: String,
    ): List<String>

    @Modifying(flushAutomatically = true)
    @Query("delete from Artwork a where a.ownerType = :ownerType and a.ownerId = :ownerId and a.provider = :provider")
    fun deleteByOwnerAndProvider(
        @Param("ownerType") ownerType: OwnerType,
        @Param("ownerId") ownerId: Long,
        @Param("provider") provider: ExternalProvider,
    )
}
