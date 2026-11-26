package com.scatl.folio.auth

import jakarta.validation.constraints.NotBlank

data class LoginRequest(
    @field:NotBlank(message = "不能为空")
    val username: String,
    @field:NotBlank(message = "不能为空")
    val password: String,
)

data class AccountUpdateRequest(
    @field:NotBlank(message = "不能为空")
    val currentPassword: String,
    val username: String? = null,
    val newPassword: String? = null,
)

data class LibraryPermissionInput(
    val libraryId: Long,
    val access: String,
)

data class LibraryPermissionView(
    val libraryId: Long,
    val access: String,
)

data class CreateUserRequest(
    @field:NotBlank(message = "不能为空")
    val username: String,
    @field:NotBlank(message = "不能为空")
    val password: String,
    val role: String? = null,
    val libraries: List<LibraryPermissionInput>? = null,
)

data class UpdateUserRequest(
    val username: String? = null,
    val newPassword: String? = null,
    val role: String? = null,
    val disabled: Boolean? = null,
    val libraries: List<LibraryPermissionInput>? = null,
)

data class AuthUserView(
    val id: Long,
    val username: String,
    val role: String,
    val disabled: Boolean,
    val libraries: List<LibraryPermissionView> = emptyList(),
)
