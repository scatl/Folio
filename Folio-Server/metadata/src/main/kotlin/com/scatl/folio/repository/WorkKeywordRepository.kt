package com.scatl.folio.repository

import com.scatl.folio.entity.WorkKeyword
import org.springframework.data.jpa.repository.JpaRepository
import org.springframework.data.jpa.repository.Modifying
import org.springframework.data.jpa.repository.Query
import org.springframework.data.repository.query.Param

interface WorkKeywordRepository : JpaRepository<WorkKeyword, Long> {
    fun findByWorkId(workId: Long): List<WorkKeyword>

    @Modifying(flushAutomatically = true)
    @Query("delete from WorkKeyword k where k.workId = :workId")
    fun deleteByWorkId(@Param("workId") workId: Long)
}
