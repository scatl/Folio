package com.scatl.folio.repository

import com.scatl.folio.entity.ExternalId
import com.scatl.folio.catalog.ExternalProvider
import com.scatl.folio.catalog.OwnerType
import org.springframework.data.jpa.repository.JpaRepository

interface ExternalIdRepository : JpaRepository<ExternalId, Long> {
    fun findByOwnerTypeAndProviderAndExternalId(
        ownerType: OwnerType,
        provider: ExternalProvider,
        externalId: String,
    ): java.util.Optional<ExternalId>

    fun findByOwnerTypeAndProviderAndExternalIdIn(
        ownerType: OwnerType,
        provider: ExternalProvider,
        externalIds: Collection<String>,
    ): List<ExternalId>

    fun findByOwnerTypeAndOwnerIdOrderByProviderAsc(ownerType: OwnerType, ownerId: Long): List<ExternalId>
}
