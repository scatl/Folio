package com.scatl.folio.library

import com.scatl.folio.auth.LibraryAccessService
import com.scatl.folio.catalog.WorkKind
import com.scatl.folio.dto.BrowseEntry
import com.scatl.folio.dto.BrowseResult
import com.scatl.folio.dto.MediaLibraryDetail
import com.scatl.folio.dto.MediaLibraryFileView
import com.scatl.folio.dto.MediaLibraryView
import com.scatl.folio.entity.LibraryFile
import com.scatl.folio.entity.MediaLibrary
import com.scatl.folio.repository.LibraryFileRepository
import com.scatl.folio.repository.MediaLibraryRepository
import jakarta.persistence.EntityManager
import org.slf4j.LoggerFactory
import org.springframework.http.HttpStatus
import org.springframework.stereotype.Service
import org.springframework.transaction.PlatformTransactionManager
import org.springframework.transaction.annotation.Transactional
import org.springframework.transaction.support.TransactionTemplate
import org.springframework.web.server.ResponseStatusException
import java.nio.file.Files
import java.nio.file.Path
import java.time.Instant
import kotlin.io.path.isDirectory
import kotlin.io.path.listDirectoryEntries
import kotlin.io.path.name

@Service
open class MediaLibraryService(
    private val libraries: MediaLibraryRepository,
    private val files: LibraryFileRepository,
    private val reconcile: LibraryReconcileService,
    private val watch: LibraryWatchService,
    private val events: ScrapeEventPublisher,
    private val entityManager: EntityManager,
    private val libraryAccess: LibraryAccessService,
    transactionManager: PlatformTransactionManager,
) {
    private val log = LoggerFactory.getLogger(javaClass)
    private val tx = TransactionTemplate(transactionManager)
    @Transactional(readOnly = true)
    open fun workCounts(): Map<Long, Long> =
        files.countDistinctWorksByLibrary().associate { row ->
            (row[0] as Number).toLong() to (row[1] as Number).toLong()
        }

    @Transactional(readOnly = true)
    open fun workCount(libraryId: Long): Long = files.countDistinctWorks(libraryId)

    @Transactional(readOnly = true)
    open fun list(): List<MediaLibraryDetail> =
        libraries.findAllByOrderBySortOrderAscIdAsc().map { library ->
            MediaLibraryDetail(
                library = library,
                files = files.findByMediaLibrary_IdOrderByIdAsc(requireNotNull(library.id)),
            )
        }

    @Transactional(readOnly = true)
    open fun listViews(): List<MediaLibraryView> {
        val counts = workCounts()
        val readable = libraryAccess.readableLibraryIds()
        val writable = libraryAccess.writableLibraryIds()
        return list()
            .asSequence()
            .filter { detail ->
                val id = requireNotNull(detail.library.id)
                readable == null || id in readable
            }
            .map { detail ->
                val id = requireNotNull(detail.library.id)
                val access = when {
                    writable == null || id in writable -> "WRITE"
                    else -> "READ"
                }
                MediaLibraryView(
                    id = id,
                    name = detail.library.name,
                    kind = detail.library.kind.name,
                    rootPath = detail.library.rootPath,
                    files = detail.files.map { it.toFileView() },
                    createdAt = detail.library.createdAt,
                    workCount = counts[detail.library.id] ?: 0,
                    access = access,
                )
            }
            .toList()
    }

    private fun LibraryFile.toFileView() =
        MediaLibraryFileView(
            id = requireNotNull(id),
            fileName = fileName,
            locator = locator,
            status = matchStatus.name,
        )

    @Transactional(readOnly = true)
    open fun get(id: Long): MediaLibraryDetail {
        libraryAccess.requireRead(id)
        val library = libraries.findById(id)
            .orElseThrow { ResponseStatusException(HttpStatus.NOT_FOUND, "资料库不存在") }
        return MediaLibraryDetail(
            library = library,
            files = files.findByMediaLibrary_IdOrderByIdAsc(id),
        )
    }

    open fun create(name: String?, kind: WorkKind, rootPath: String): MediaLibraryDetail {
        val root = resolveAllowedDirectory(rootPath)
        val displayPath = toDisplayPath(root)
        val library = tx.execute {
            val now = Instant.now()
            libraries.save(
                MediaLibrary().apply {
                    this.name = name?.trim()?.takeIf { it.isNotEmpty() } ?: defaultName(kind, displayPath)
                    this.kind = kind
                    this.rootPath = displayPath
                    createdAt = now
                    updatedAt = now
                    sortOrder = (libraries.findMinSortOrder() ?: 1) - 1
                },
            )
        } ?: throw ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR, "创建资料库失败")

        val libraryId = requireNotNull(library.id)
        watch.registerLibrary(library)
        reconcile.requestScan(libraryId)
        return MediaLibraryDetail(library = library, files = emptyList())
    }

    @Transactional
    open fun reorder(ids: List<Long>) {
        val rows = libraries.findAll()
        val known = rows.mapNotNull { it.id }
        if (ids.size != known.size || ids.toSet() != known.toSet()) {
            throw ResponseStatusException(HttpStatus.BAD_REQUEST, "资料库顺序不完整")
        }
        val byId = rows.associateBy { it.id }
        val now = Instant.now()
        ids.forEachIndexed { index, id ->
            val row = byId.getValue(id)
            row.sortOrder = index
            row.updatedAt = now
        }
        libraries.saveAll(rows)
    }

    fun scan(libraryId: Long) {
        libraryAccess.requireWrite(libraryId)
        reconcile.requireLibrary(libraryId)
        reconcile.requestScan(libraryId)
    }

    fun delete(libraryId: Long) {
        if (!libraries.existsById(libraryId)) {
            throw ResponseStatusException(HttpStatus.NOT_FOUND, "资料库不存在")
        }
        reconcile.abandon(libraryId)
        watch.unregisterLibrary(libraryId)
        val removed = tx.execute {
            @Suppress("UNCHECKED_CAST")
            val jobIds = (entityManager.createNativeQuery(
                """
                SELECT j.id FROM scrape_jobs j
                INNER JOIN library_files f ON f.id = j.library_file_id
                WHERE f.media_library_id = :id
                """.trimIndent(),
            ).setParameter("id", libraryId).resultList as List<Number>).map { it.toLong() }
            @Suppress("UNCHECKED_CAST")
            val workIds = (entityManager.createNativeQuery(
                """
                SELECT DISTINCT f.work_id FROM library_files f
                WHERE f.media_library_id = :id AND f.work_id IS NOT NULL
                """.trimIndent(),
            ).setParameter("id", libraryId).resultList as List<Number>).map { it.toLong() }
            entityManager.createNativeQuery(
                """
                DELETE j FROM scrape_jobs j
                INNER JOIN library_files f ON f.id = j.library_file_id
                WHERE f.media_library_id = :id
                """.trimIndent(),
            ).setParameter("id", libraryId).executeUpdate()
            entityManager.createNativeQuery(
                "DELETE FROM library_files WHERE media_library_id = :id",
            ).setParameter("id", libraryId).executeUpdate()
            val orphanWorks = workIds.filter { workId ->
                val count = entityManager.createNativeQuery(
                    "SELECT COUNT(*) FROM library_files WHERE work_id = :workId",
                ).setParameter("workId", workId).singleResult as Number
                count.toLong() == 0L
            }
            entityManager.createNativeQuery(
                "DELETE FROM media_libraries WHERE id = :id",
            ).setParameter("id", libraryId).executeUpdate()
            RemovedLibrary(jobIds, orphanWorks)
        } ?: throw ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR, "删除资料库失败")
        removed.jobIds.forEach { events.notifyDeletedAfterCommit(it) }
        removed.workIds.forEach { events.notifyWorkRemovedAfterCommit(it) }
        if (removed.jobIds.isEmpty()) events.notifyStats()
        log.info(
            "资料库已删除 libraryId={} jobs={} worksRemoved={}",
            libraryId,
            removed.jobIds.size,
            removed.workIds.size,
        )
    }

    fun browse(path: String?): BrowseResult {
        val roots = mediaRoots()
        if (roots.isEmpty()) {
            throw ResponseStatusException(
                HttpStatus.BAD_REQUEST,
                "片库根目录 /media 不存在或不可用，请把视频目录映射到容器 /media",
            )
        }

        val requested = path?.trim().orEmpty()
        if (requested.isEmpty()) {
            return BrowseResult(
                path = "",
                parent = null,
                directories = roots.map { root ->
                    val display = toDisplayPath(root)
                    BrowseEntry(
                        name = root.fileName?.toString()?.ifBlank { display } ?: display,
                        path = display,
                    )
                },
            )
        }

        val current = resolveAllowedDirectory(requested)
        val display = toDisplayPath(current)
        val parentDisplay = parentWithinRoots(current)

        val directories = try {
            current.listDirectoryEntries()
                .filter { it.isDirectory() && !Files.isHidden(it) && !it.name.startsWith('.') }
                .sortedBy { it.name.lowercase() }
                .map { child ->
                    BrowseEntry(name = child.name, path = toDisplayPath(child))
                }
        } catch (e: Exception) {
            throw ResponseStatusException(HttpStatus.BAD_REQUEST, "无法读取目录: ${e.message}")
        }

        return BrowseResult(path = display, parent = parentDisplay, directories = directories)
    }

    private fun mediaRoots(): List<Path> = LibraryPaths.mediaRoots()

    private fun resolveAllowedDirectory(raw: String): Path {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) {
            throw ResponseStatusException(HttpStatus.BAD_REQUEST, "目录路径不能为空")
        }
        val path = Path.of(trimmed).toAbsolutePath().normalize()
        if (!isUnderMediaRoots(path)) {
            throw ResponseStatusException(HttpStatus.BAD_REQUEST, "路径必须位于 /media 下")
        }
        if (!path.isDirectory()) {
            throw ResponseStatusException(HttpStatus.BAD_REQUEST, "目录不存在或不可用")
        }
        return path
    }

    private fun isUnderMediaRoots(path: Path): Boolean = LibraryPaths.isUnderMediaRoots(path)

    private fun parentWithinRoots(current: Path): String? {
        val roots = mediaRoots()
        if (roots.any { it == current }) {
            return ""
        }
        val parent = current.parent ?: return ""
        if (!isUnderMediaRoots(parent)) {
            return ""
        }
        return toDisplayPath(parent)
    }

    private fun defaultName(kind: WorkKind, rootPath: String): String {
        val folder = rootPath.trimEnd('/').substringAfterLast('/').ifBlank { rootPath }
        val kindLabel = when (kind) {
            WorkKind.movie -> "电影"
            WorkKind.series -> "剧集"
        }
        return "$folder ($kindLabel)"
    }

    private fun toDisplayPath(path: Path): String =
        path.toAbsolutePath().normalize().toString().replace('\\', '/')

    private data class RemovedLibrary(val jobIds: List<Long>, val workIds: List<Long>)
}
