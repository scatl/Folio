package com.scatl.folio.repository

import com.scatl.folio.entity.FileFingerprint
import org.springframework.data.jpa.repository.JpaRepository

interface FileFingerprintRepository : JpaRepository<FileFingerprint, Long> {
    fun findByFileSizeAndContentHash(fileSize: Long, contentHash: String): FileFingerprint?
}
