package com.scatl.folio.repository

import com.scatl.folio.entity.Rating
import com.scatl.folio.catalog.ExternalProvider
import com.scatl.folio.catalog.OwnerType
import org.springframework.data.jpa.repository.JpaRepository

interface RatingRepository : JpaRepository<Rating, Long> {
    fun findByOwnerTypeAndOwnerIdAndProvider(
        ownerType: OwnerType,
        ownerId: Long,
        provider: ExternalProvider,
    ): java.util.Optional<Rating>

    fun findByOwnerTypeAndOwnerIdOrderByProviderAsc(ownerType: OwnerType, ownerId: Long): List<Rating>

    fun findByOwnerTypeAndOwnerIdIn(ownerType: OwnerType, ownerIds: Collection<Long>): List<Rating>
}
