package com.scatl.folio.repository

import com.scatl.folio.entity.WorkGenre
import org.springframework.data.jpa.repository.JpaRepository
import org.springframework.data.jpa.repository.Modifying
import org.springframework.data.jpa.repository.Query
import org.springframework.data.repository.query.Param

interface WorkGenreRepository : JpaRepository<WorkGenre, Long> {
    fun findByWorkId(workId: Long): List<WorkGenre>

    fun findByWorkIdIn(workIds: Collection<Long>): List<WorkGenre>

    @Modifying(flushAutomatically = true)
    @Query("delete from WorkGenre g where g.workId = :workId")
    fun deleteByWorkId(@Param("workId") workId: Long)
}
