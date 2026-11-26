package com.scatl.folio.repository

import com.scatl.folio.entity.Genre
import com.scatl.folio.catalog.ExternalProvider
import org.springframework.data.jpa.repository.JpaRepository

interface GenreRepository : JpaRepository<Genre, Long> {
    fun findByProviderAndExternalId(provider: ExternalProvider, externalId: String): java.util.Optional<Genre>
}
