package com.scatl.folio.repository

import com.scatl.folio.entity.Keyword
import com.scatl.folio.catalog.ExternalProvider
import org.springframework.data.jpa.repository.JpaRepository

interface KeywordRepository : JpaRepository<Keyword, Long> {
    fun findByProviderAndExternalId(provider: ExternalProvider, externalId: String): java.util.Optional<Keyword>
}
