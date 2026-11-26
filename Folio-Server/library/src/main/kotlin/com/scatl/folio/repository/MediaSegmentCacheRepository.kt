package com.scatl.folio.repository

import com.scatl.folio.entity.MediaSegmentCache
import org.springframework.data.jpa.repository.JpaRepository

interface MediaSegmentCacheRepository : JpaRepository<MediaSegmentCache, Long> {
    fun findByWorkIdAndSeasonNumberAndEpisodeNumberAndDurationBucket(
        workId: Long,
        seasonNumber: Int,
        episodeNumber: Int,
        durationBucket: Int,
    ): MediaSegmentCache?
}
