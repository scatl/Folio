package com.scatl.folio.repository

import com.scatl.folio.entity.Company
import com.scatl.folio.catalog.ExternalProvider
import org.springframework.data.jpa.repository.JpaRepository

interface CompanyRepository : JpaRepository<Company, Long> {
    fun findByProviderAndExternalId(provider: ExternalProvider, externalId: String): java.util.Optional<Company>
}
