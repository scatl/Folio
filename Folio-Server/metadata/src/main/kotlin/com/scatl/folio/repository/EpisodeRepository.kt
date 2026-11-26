package com.scatl.folio.repository

import com.scatl.folio.entity.Episode
import org.springframework.data.jpa.repository.JpaRepository

interface EpisodeRepository : JpaRepository<Episode, Long> {
    fun findBySeasonIdAndEpisodeNumber(seasonId: Long, episodeNumber: Int): java.util.Optional<Episode>
    fun findByWorkIdOrderByEpisodeNumberAsc(workId: Long): List<Episode>
    fun findBySeasonIdOrderByEpisodeNumberAsc(seasonId: Long): List<Episode>
}
