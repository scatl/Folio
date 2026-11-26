package com.scatl.folio.repository

import com.scatl.folio.entity.Credit
import com.scatl.folio.catalog.ExternalProvider
import com.scatl.folio.catalog.OwnerType
import org.springframework.data.jpa.repository.JpaRepository
import org.springframework.data.jpa.repository.Modifying
import org.springframework.data.jpa.repository.Query
import org.springframework.data.repository.query.Param

interface CreditRepository : JpaRepository<Credit, Long> {
    @Modifying(flushAutomatically = true)
    @Query("delete from Credit c where c.ownerType = :ownerType and c.ownerId = :ownerId and c.person.provider = :provider")
    fun deleteByOwnerAndProvider(
        @Param("ownerType") ownerType: OwnerType,
        @Param("ownerId") ownerId: Long,
        @Param("provider") provider: ExternalProvider,
    )

    @Query("select c from Credit c join fetch c.person where c.ownerType = :ownerType and c.ownerId = :ownerId order by c.sortOrder")
    fun findForOwner(@Param("ownerType") ownerType: OwnerType, @Param("ownerId") ownerId: Long): List<Credit>

    @Query(
        "select c from Credit c join fetch c.person p " +
            "where p.id = :personId and c.ownerType = :ownerType order by c.sortOrder",
    )
    fun findByPersonAndOwnerType(
        @Param("personId") personId: Long,
        @Param("ownerType") ownerType: OwnerType,
    ): List<Credit>
}
