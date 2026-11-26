package com.scatl.folio.repository

import com.scatl.folio.entity.Person
import com.scatl.folio.catalog.ExternalProvider
import org.springframework.data.jpa.repository.JpaRepository

interface PersonRepository : JpaRepository<Person, Long> {
    fun findByProviderAndProviderPersonId(
        provider: ExternalProvider,
        providerPersonId: String,
    ): java.util.Optional<Person>
}
