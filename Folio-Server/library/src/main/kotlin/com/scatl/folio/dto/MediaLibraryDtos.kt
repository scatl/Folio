package com.scatl.folio.dto

import com.scatl.folio.catalog.WorkKind
import com.scatl.folio.entity.LibraryFile
import com.scatl.folio.entity.MediaLibrary
import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.NotEmpty
import jakarta.validation.constraints.NotNull
import jakarta.validation.constraints.Size
import java.time.Instant

data class ReorderLibrariesRequest(
    @field:NotEmpty(message = "不能为空")
    val ids: List<Long>,
)

data class CreateMediaLibraryRequest(
    @field:Size(max = 128, message = "最长 128 个字符")
    val name: String? = null,
    @field:NotNull(message = "不能为空")
    val kind: WorkKind,
    @field:NotBlank(message = "不能为空")
    @field:Size(max = 1024, message = "最长 1024 个字符")
    val rootPath: String,
)

data class MediaLibraryFileView(
    val id: Long,
    val fileName: String,
    val locator: String,
    val status: String,
)

data class MediaLibraryView(
    val id: Long,
    val name: String,
    val kind: String,
    val rootPath: String,
    val files: List<MediaLibraryFileView>,
    val createdAt: Instant,
    val workCount: Long = 0,
    /** READ 或 WRITE；管理员对所有库为 WRITE。 */
    val access: String = "READ",
)

data class BrowseEntryView(
    val name: String,
    val path: String,
)

data class BrowseView(
    val path: String,
    val parent: String?,
    val directories: List<BrowseEntryView>,
)

data class BrowseEntry(
    val name: String,
    val path: String,
)

data class BrowseResult(
    val path: String,
    val parent: String?,
    val directories: List<BrowseEntry>,
)

data class MediaLibraryDetail(
    val library: MediaLibrary,
    val files: List<LibraryFile>,
)

