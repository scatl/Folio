package com.scatl.folio.auth

import com.scatl.folio.catalog.ArtworkKind
import com.scatl.folio.catalog.OwnerType
import com.scatl.folio.entity.AppUser
import com.scatl.folio.entity.LibraryAccess
import com.scatl.folio.entity.UserLibraryPermission
import com.scatl.folio.entity.UserLibraryPermissionId
import com.scatl.folio.entity.UserRole
import com.scatl.folio.repository.AppUserRepository
import com.scatl.folio.repository.ArtworkRepository
import com.scatl.folio.repository.UserLibraryPermissionRepository
import com.scatl.folio.settings.FolioSettings
import com.scatl.folio.util.TmdbImageUrls
import jakarta.persistence.EntityManager
import org.springframework.http.HttpStatus
import org.springframework.security.crypto.password.PasswordEncoder
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import org.springframework.web.server.ResponseStatusException
import java.time.Instant

@Service
open class AuthService(
    private val users: AppUserRepository,
    private val passwords: PasswordEncoder,
    private val artworks: ArtworkRepository,
    private val appSettings: FolioSettings,
    private val sessions: UserSessionService,
    private val libraryPermissions: UserLibraryPermissionRepository,
    private val entityManager: EntityManager,
) {
    @Transactional
    open fun ensureDefaultUser() {
        if (users.count() > 0) return
        val now = Instant.now()
        users.save(AppUser().apply {
            username = "folio"
            passwordHash = hash("folio")
            role = UserRole.ADMIN
            disabled = false
            createdAt = now
            updatedAt = now
        })
    }

    @Transactional(readOnly = true)
    open fun viewByUsername(username: String): AuthUserView {
        val user = users.findByUsername(username.trim())
            ?: throw ResponseStatusException(HttpStatus.UNAUTHORIZED, "未登录")
        return view(user)
    }

    @Transactional(readOnly = true)
    open fun listUsers(): List<AuthUserView> {
        val rows = users.findAllByOrderByIdAsc()
        val byUser = libraryPermissions
            .findByIdUserIdIn(rows.mapNotNull { it.id })
            .groupBy { it.id.userId }
        return rows.map { view(it, byUser[it.id].orEmpty()) }
    }

    @Transactional
    open fun createUser(body: CreateUserRequest): AuthUserView {
        val username = body.username.trim()
        validateUsername(username)
        validatePassword(body.password)
        if (users.existsByUsername(username)) {
            throw ResponseStatusException(HttpStatus.BAD_REQUEST, "用户名已被使用")
        }
        val now = Instant.now()
        val role = body.role?.let(::parseRole) ?: UserRole.USER
        val saved = users.save(AppUser().apply {
            this.username = username
            passwordHash = hash(body.password)
            this.role = role
            disabled = false
            createdAt = now
            updatedAt = now
        })
        replaceLibraries(requireNotNull(saved.id), role, body.libraries.orEmpty())
        return view(saved)
    }

    @Transactional
    open fun updateUser(id: Long, actor: String, body: UpdateUserRequest): AuthUserView {
        val user = users.findById(id).orElseThrow {
            ResponseStatusException(HttpStatus.NOT_FOUND, "用户不存在")
        }
        val nextUsername = body.username?.trim().orEmpty()
        val nextPassword = body.newPassword?.takeIf { it.isNotBlank() }
        val nextRole = body.role?.let(::parseRole)
        val nextDisabled = body.disabled
        val libraries = body.libraries
        if (
            nextUsername.isEmpty() &&
            nextPassword == null &&
            nextRole == null &&
            nextDisabled == null &&
            libraries == null
        ) {
            throw ResponseStatusException(HttpStatus.BAD_REQUEST, "没有要修改的内容")
        }
        val role = nextRole ?: user.role
        val disabled = nextDisabled ?: user.disabled
        if (disabled && !user.disabled && user.username == actor) {
            throw ResponseStatusException(HttpStatus.BAD_REQUEST, "不能停用当前登录的账号")
        }
        ensureAdminRemains(user, deleting = false, nextRole = role, nextDisabled = disabled)
        val previousUsername = user.username
        if (nextUsername.isNotEmpty() && nextUsername != user.username) {
            validateUsername(nextUsername)
            if (users.existsByUsername(nextUsername)) {
                throw ResponseStatusException(HttpStatus.BAD_REQUEST, "用户名已被使用")
            }
            user.username = nextUsername
        }
        if (nextPassword != null) {
            validatePassword(nextPassword)
            user.passwordHash = hash(nextPassword)
        }
        val roleChanged = nextRole != null && nextRole != user.role
        val disabledChanged = nextDisabled != null && nextDisabled != user.disabled
        val credentialChanged = previousUsername != (if (nextUsername.isNotEmpty()) nextUsername else user.username) ||
            nextPassword != null
        user.role = role
        user.disabled = disabled
        user.updatedAt = Instant.now()
        users.save(user)
        if (libraries != null || nextRole != null) {
            replaceLibraries(requireNotNull(user.id), role, libraries.orEmpty())
        }
        if (credentialChanged || roleChanged || disabledChanged) {
            if (previousUsername != user.username) sessions.expire(previousUsername)
            sessions.expire(user.username)
        }
        return view(user)
    }

    @Transactional
    open fun deleteUser(id: Long, actor: String) {
        val user = users.findById(id).orElseThrow {
            ResponseStatusException(HttpStatus.NOT_FOUND, "用户不存在")
        }
        if (user.username == actor) {
            throw ResponseStatusException(HttpStatus.BAD_REQUEST, "不能删除当前登录的账号")
        }
        ensureAdminRemains(user, deleting = true, nextRole = UserRole.USER, nextDisabled = true)
        val username = user.username
        users.delete(user)
        sessions.expire(username)
    }

    @Transactional
    open fun updateAccount(currentUsername: String, body: AccountUpdateRequest): AuthUserView {
        val user = users.findByUsername(currentUsername)
            ?: throw ResponseStatusException(HttpStatus.UNAUTHORIZED, "未登录")
        if (!passwords.matches(body.currentPassword, user.passwordHash)) {
            throw ResponseStatusException(HttpStatus.BAD_REQUEST, "当前密码不正确")
        }
        val nextUsername = body.username?.trim().orEmpty()
        val nextPassword = body.newPassword?.takeIf { it.isNotBlank() }
        if (nextUsername.isEmpty() && nextPassword == null) {
            throw ResponseStatusException(HttpStatus.BAD_REQUEST, "没有要修改的内容")
        }
        val previousUsername = user.username
        if (nextUsername.isNotEmpty() && nextUsername != user.username) {
            validateUsername(nextUsername)
            if (users.existsByUsername(nextUsername)) {
                throw ResponseStatusException(HttpStatus.BAD_REQUEST, "用户名已被使用")
            }
            user.username = nextUsername
        }
        if (nextPassword != null) {
            validatePassword(nextPassword)
            user.passwordHash = hash(nextPassword)
        }
        user.updatedAt = Instant.now()
        users.save(user)
        if (previousUsername != user.username) sessions.expire(previousUsername)
        sessions.expire(user.username)
        return view(user)
    }

    private fun hash(raw: String): String =
        passwords.encode(raw) ?: error("无法生成密码哈希")

    private fun view(user: AppUser): AuthUserView =
        view(user, libraryPermissions.findByIdUserId(requireNotNull(user.id)))

    private fun view(user: AppUser, rows: List<UserLibraryPermission>) = AuthUserView(
        id = requireNotNull(user.id),
        username = user.username,
        role = user.role.name,
        disabled = user.disabled,
        libraries = if (user.role == UserRole.ADMIN) {
            emptyList()
        } else {
            rows
                .sortedBy { it.id.libraryId }
                .map { LibraryPermissionView(it.id.libraryId, it.access.name) }
        },
    )

    private fun replaceLibraries(userId: Long, role: UserRole, inputs: List<LibraryPermissionInput>) {
        libraryPermissions.deleteByUserId(userId)
        entityManager.flush()
        if (role == UserRole.ADMIN) return
        if (inputs.isEmpty()) return
        val normalized = linkedMapOf<Long, LibraryAccess>()
        for (item in inputs) {
            val access = parseAccess(item.access)
            val previous = normalized[item.libraryId]
            if (previous == null || access == LibraryAccess.WRITE) {
                normalized[item.libraryId] = access
            }
        }
        ensureLibrariesExist(normalized.keys)
        libraryPermissions.saveAll(
            normalized.map { (libraryId, access) ->
                UserLibraryPermission().apply {
                    id = UserLibraryPermissionId().apply {
                        this.userId = userId
                        this.libraryId = libraryId
                    }
                    this.access = access
                }
            },
        )
    }

    private fun ensureLibrariesExist(ids: Collection<Long>) {
        if (ids.isEmpty()) return
        @Suppress("UNCHECKED_CAST")
        val found = (entityManager.createNativeQuery(
            "SELECT id FROM media_libraries WHERE id IN (:ids)",
        ).setParameter("ids", ids).resultList as List<Number>).map { it.toLong() }.toSet()
        val missing = ids.filterNot { it in found }
        if (missing.isNotEmpty()) {
            throw ResponseStatusException(HttpStatus.BAD_REQUEST, "资料库不存在: ${missing.joinToString()}")
        }
    }

    private fun parseAccess(raw: String): LibraryAccess =
        when (raw.trim().uppercase()) {
            "READ" -> LibraryAccess.READ
            "WRITE" -> LibraryAccess.WRITE
            else -> throw ResponseStatusException(HttpStatus.BAD_REQUEST, "资料库权限无效")
        }

    private fun parseRole(raw: String): UserRole =
        when (raw.trim().uppercase()) {
            "ADMIN" -> UserRole.ADMIN
            "USER" -> UserRole.USER
            else -> throw ResponseStatusException(HttpStatus.BAD_REQUEST, "角色无效")
        }

    private fun validateUsername(name: String) {
        if (!USERNAME.matches(name)) {
            throw ResponseStatusException(HttpStatus.BAD_REQUEST, "用户名只能包含字母、数字、点、下划线和短横线")
        }
    }

    private fun validatePassword(raw: String) {
        if (raw.length < 4) {
            throw ResponseStatusException(HttpStatus.BAD_REQUEST, "密码至少 4 个字符")
        }
    }

    private fun ensureAdminRemains(
        user: AppUser,
        deleting: Boolean,
        nextRole: UserRole,
        nextDisabled: Boolean,
    ) {
        val activeAdmin = user.role == UserRole.ADMIN && !user.disabled
        val staysActiveAdmin = !deleting && nextRole == UserRole.ADMIN && !nextDisabled
        if (activeAdmin && !staysActiveAdmin && users.countByRoleAndDisabled(UserRole.ADMIN, false) <= 1) {
            throw ResponseStatusException(HttpStatus.BAD_REQUEST, "至少保留一个可用的管理员")
        }
    }

    @Transactional(readOnly = true)
    open fun loginPosters(): List<String> {
        val base = appSettings.current().tmdbImageBaseUrl
        return artworks.findRandomWorkPosterUrls(OwnerType.work.name, ArtworkKind.poster.name)
            .mapNotNull { TmdbImageUrls.resolve(it, base, size = "w342") }
            .filter { it.isNotBlank() }
    }

    companion object {
        private val USERNAME = Regex("^[\\p{L}\\p{N}._-]{2,64}$")
    }
}
