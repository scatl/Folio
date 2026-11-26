package com.scatl.folio.repository

import com.scatl.folio.entity.Video
import com.scatl.folio.catalog.ExternalProvider
import com.scatl.folio.catalog.OwnerType
import org.springframework.data.jpa.repository.JpaRepository
import org.springframework.data.jpa.repository.Modifying
import org.springframework.data.jpa.repository.Query
import org.springframework.data.repository.query.Param

interface VideoRepository : JpaRepository<Video, Long> {
    fun findByOwnerTypeAndOwnerIdOrderByIdAsc(ownerType: OwnerType, ownerId: Long): List<Video>

    @Modifying(flushAutomatically = true)
    @Query("delete from Video v where v.ownerType = :ownerType and v.ownerId = :ownerId and v.provider = :provider")
    fun deleteByOwnerAndProvider(
        @Param("ownerType") ownerType: OwnerType,
        @Param("ownerId") ownerId: Long,
        @Param("provider") provider: ExternalProvider,
    )
}
