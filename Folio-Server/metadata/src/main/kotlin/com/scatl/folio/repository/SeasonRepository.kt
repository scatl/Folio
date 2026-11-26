package com.scatl.folio.repository

import com.scatl.folio.entity.Season
import org.springframework.data.jpa.repository.JpaRepository

interface SeasonRepository : JpaRepository<Season, Long> {
    fun findByWorkIdAndSeasonNumber(workId: Long, seasonNumber: Int): java.util.Optional<Season>
    fun findByWorkIdOrderBySeasonNumberAsc(workId: Long): List<Season>
}
