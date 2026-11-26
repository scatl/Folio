package com.scatl.folio.repository

import com.scatl.folio.entity.WorkCompany
import org.springframework.data.jpa.repository.JpaRepository
import org.springframework.data.jpa.repository.Modifying
import org.springframework.data.jpa.repository.Query
import org.springframework.data.repository.query.Param

interface WorkCompanyRepository : JpaRepository<WorkCompany, Long> {
    fun findByWorkId(workId: Long): List<WorkCompany>

    @Modifying(flushAutomatically = true)
    @Query("delete from WorkCompany c where c.workId = :workId")
    fun deleteByWorkId(@Param("workId") workId: Long)
}
