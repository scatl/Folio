package com.scatl.folio.auth

import com.scatl.folio.entity.LibraryAccess
import com.scatl.folio.repository.AppUserRepository
import com.scatl.folio.repository.UserLibraryPermissionRepository
import jakarta.persistence.EntityManager
import org.springframework.http.HttpStatus
import org.springframework.security.core.context.SecurityContextHolder
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import org.springframework.web.server.ResponseStatusException

/**
 * 资料库 ACL。返回 `null` 表示管理员、不限制；空集合表示普通用户无任何库权限。
 */
@Service
open class LibraryAccessService(
    private val users: AppUserRepository,
    private val permissions: UserLibraryPermissionRepository,
    private val entityManager: EntityManager,
) {
    @Transactional(readOnly = true)
    open fun readableLibraryIds(): Set<Long>? = libraryIds(minAccess = LibraryAccess.READ)

    @Transactional(readOnly = true)
    open fun writableLibraryIds(): Set<Long>? = libraryIds(minAccess = LibraryAccess.WRITE)

    @Transactional(readOnly = true)
    open fun canRead(libraryId: Long): Boolean = allows(libraryId, LibraryAccess.READ)

    @Transactional(readOnly = true)
    open fun canWrite(libraryId: Long): Boolean = allows(libraryId, LibraryAccess.WRITE)

    open fun requireRead(libraryId: Long) {
        if (!canRead(libraryId)) forbidden()
    }

    open fun requireWrite(libraryId: Long) {
        if (!canWrite(libraryId)) forbidden()
    }

    @Transactional(readOnly = true)
    open fun requireWorkReadable(workId: Long) {
        if (isAdmin()) return
        val allowed = readableLibraryIds().orEmpty()
        if (allowed.isEmpty() || !workInLibraries(workId, allowed)) forbidden()
    }

    @Transactional(readOnly = true)
    open fun requireWorkWritable(workId: Long) {
        if (isAdmin()) return
        val allowed = writableLibraryIds().orEmpty()
        if (allowed.isEmpty() || !workInLibraries(workId, allowed)) forbidden()
    }

    @Transactional(readOnly = true)
    open fun requireFileReadable(fileId: Long) {
        requireRead(libraryIdOfFile(fileId))
    }

    @Transactional(readOnly = true)
    open fun requireFileWritable(fileId: Long) {
        requireWrite(libraryIdOfFile(fileId))
    }

    @Transactional(readOnly = true)
    open fun isAdmin(): Boolean {
        val auth = SecurityContextHolder.getContext().authentication ?: return false
        return auth.authorities.any { it.authority == "ROLE_ADMIN" }
    }

    @Transactional(readOnly = true)
    open fun currentUserId(): Long? {
        val name = SecurityContextHolder.getContext().authentication?.name?.trim().orEmpty()
        if (name.isEmpty() || name == "anonymousUser") return null
        return users.findByUsername(name)?.id
    }

    private fun libraryIds(minAccess: LibraryAccess): Set<Long>? {
        if (isAdmin()) return null
        val userId = currentUserId() ?: return emptySet()
        return permissions.findByIdUserId(userId)
            .filter { row ->
                when (minAccess) {
                    LibraryAccess.READ -> true
                    LibraryAccess.WRITE -> row.access == LibraryAccess.WRITE
                }
            }
            .map { it.id.libraryId }
            .toSet()
    }

    private fun allows(libraryId: Long, minAccess: LibraryAccess): Boolean {
        val ids = libraryIds(minAccess) ?: return true
        return libraryId in ids
    }

    private fun workInLibraries(workId: Long, libraryIds: Set<Long>): Boolean {
        if (libraryIds.isEmpty()) return false
        val count = entityManager.createNativeQuery(
            """
            SELECT COUNT(*) FROM library_files
            WHERE work_id = :workId AND media_library_id IN (:libraryIds)
            """.trimIndent(),
        )
            .setParameter("workId", workId)
            .setParameter("libraryIds", libraryIds)
            .singleResult as Number
        return count.toLong() > 0L
    }

    private fun libraryIdOfFile(fileId: Long): Long {
        val id = entityManager.createNativeQuery(
            "SELECT media_library_id FROM library_files WHERE id = :fileId",
        )
            .setParameter("fileId", fileId)
            .resultList
            .firstOrNull()
            ?: throw ResponseStatusException(HttpStatus.NOT_FOUND, "文件不存在")
        return (id as Number).toLong()
    }

    private fun forbidden(): Nothing =
        throw ResponseStatusException(HttpStatus.FORBIDDEN, "没有权限")
}
