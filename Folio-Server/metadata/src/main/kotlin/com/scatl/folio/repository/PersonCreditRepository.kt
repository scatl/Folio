package com.scatl.folio.repository

import com.scatl.folio.entity.PersonCredit
import org.springframework.data.jpa.repository.JpaRepository
import org.springframework.data.jpa.repository.Modifying
import org.springframework.data.jpa.repository.Query
import org.springframework.data.repository.query.Param

interface PersonCreditRepository : JpaRepository<PersonCredit, Long> {
    fun findByPersonId(personId: Long): List<PersonCredit>

    @Modifying(flushAutomatically = true, clearAutomatically = true)
    @Query("delete from PersonCredit c where c.person.id = :personId")
    fun deleteByPersonId(@Param("personId") personId: Long)
}