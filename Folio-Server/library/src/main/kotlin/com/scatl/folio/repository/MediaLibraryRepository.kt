package com.scatl.folio.repository

import com.scatl.folio.entity.MediaLibrary
import org.springframework.data.jpa.repository.JpaRepository
import org.springframework.data.jpa.repository.Query

interface MediaLibraryRepository : JpaRepository<MediaLibrary, Long> {
    fun findAllByOrderBySortOrderAscIdAsc(): List<MediaLibrary>

    @Query("select min(m.sortOrder) from MediaLibrary m")
    fun findMinSortOrder(): Int?
}
