package com.scatl.folio.repository

import com.scatl.folio.entity.WorkTranslation
import org.springframework.data.jpa.repository.JpaRepository

interface WorkTranslationRepository : JpaRepository<WorkTranslation, Long> {
    fun findByWorkIdAndLocale(workId: Long, locale: String): java.util.Optional<WorkTranslation>
    fun findByWorkIdOrderByLocaleAsc(workId: Long): List<WorkTranslation>
    fun findByWorkIdIn(workIds: Collection<Long>): List<WorkTranslation>
}
