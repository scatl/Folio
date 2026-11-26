package com.scatl.folio.repository

import com.scatl.folio.entity.UserLibraryPermission
import com.scatl.folio.entity.UserLibraryPermissionId
import org.springframework.data.jpa.repository.JpaRepository
import org.springframework.data.jpa.repository.Modifying
import org.springframework.data.jpa.repository.Query
import org.springframework.data.repository.query.Param

interface UserLibraryPermissionRepository : JpaRepository<UserLibraryPermission, UserLibraryPermissionId> {
    fun findByIdUserId(userId: Long): List<UserLibraryPermission>

    fun findByIdUserIdIn(userIds: Collection<Long>): List<UserLibraryPermission>

    @Modifying
    @Query("delete from UserLibraryPermission p where p.id.userId = :userId")
    fun deleteByUserId(@Param("userId") userId: Long)
}
