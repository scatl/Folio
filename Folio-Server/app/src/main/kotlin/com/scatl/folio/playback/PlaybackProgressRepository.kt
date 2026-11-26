package com.scatl.folio.playback

import org.springframework.data.jpa.repository.JpaRepository
import org.springframework.data.jpa.repository.Modifying
import org.springframework.data.jpa.repository.Query
import org.springframework.data.repository.query.Param

interface PlaybackProgressRepository : JpaRepository<PlaybackProgress, Long> {
    fun findByUserIdAndLibraryFileId(userId: Long, libraryFileId: Long): PlaybackProgress?

    @Modifying(clearAutomatically = true)
    @Query("delete from PlaybackProgress p where p.userId = :userId and p.libraryFileId in :fileIds")
    fun deleteByUserIdAndLibraryFileIdIn(
        @Param("userId") userId: Long,
        @Param("fileIds") fileIds: Collection<Long>,
    )

    fun findByUserIdAndWorkIdOrderByUpdatedAtDesc(userId: Long, workId: Long): List<PlaybackProgress>

    /** 每部作品只取最新一条。整部标已看会把每一集都写成同一时间，不能用原始最近记录挤掉其他作品。 */
    @Query(
        """
        select p from PlaybackProgress p
        where p.userId = :userId
          and p.workId is not null
          and p.updatedAt = (
            select max(other.updatedAt) from PlaybackProgress other
            where other.userId = p.userId and other.workId = p.workId
          )
        order by p.updatedAt desc, p.id desc
        """,
    )
    fun findLatestRowsPerWork(@Param("userId") userId: Long): List<PlaybackProgress>
}
