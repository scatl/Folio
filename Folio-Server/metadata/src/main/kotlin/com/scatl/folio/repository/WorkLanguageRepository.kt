package com.scatl.folio.repository

import com.scatl.folio.entity.WorkLanguage
import org.springframework.data.jpa.repository.JpaRepository
import org.springframework.data.jpa.repository.Modifying
import org.springframework.data.jpa.repository.Query
import org.springframework.data.repository.query.Param

interface WorkLanguageRepository : JpaRepository<WorkLanguage, Long> {
    fun findByWorkId(workId: Long): List<WorkLanguage>

    @Modifying(flushAutomatically = true)
    @Query("delete from WorkLanguage l where l.workId = :workId")
    fun deleteByWorkId(@Param("workId") workId: Long)
}
