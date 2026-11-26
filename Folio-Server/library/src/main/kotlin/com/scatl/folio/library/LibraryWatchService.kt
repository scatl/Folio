package com.scatl.folio.library

import com.scatl.folio.entity.MediaLibrary
import com.scatl.folio.repository.MediaLibraryRepository
import com.scatl.folio.settings.AppSettingsChangedEvent
import com.scatl.folio.settings.FolioSettings
import jakarta.annotation.PreDestroy
import org.slf4j.LoggerFactory
import org.springframework.boot.context.event.ApplicationReadyEvent
import org.springframework.context.event.EventListener
import org.springframework.scheduling.annotation.Scheduled
import org.springframework.stereotype.Service
import java.nio.file.ClosedWatchServiceException
import java.nio.file.FileSystems
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardWatchEventKinds.ENTRY_CREATE
import java.nio.file.StandardWatchEventKinds.ENTRY_DELETE
import java.nio.file.StandardWatchEventKinds.ENTRY_MODIFY
import java.nio.file.StandardWatchEventKinds.OVERFLOW
import java.nio.file.WatchKey
import java.nio.file.WatchService
import java.util.concurrent.ConcurrentHashMap
import kotlin.concurrent.thread
import kotlin.io.path.isDirectory

@Service
class LibraryWatchService(
    private val libraries: MediaLibraryRepository,
    private val appSettings: FolioSettings,
    private val reconcile: LibraryReconcileService,
) {
    private val log = LoggerFactory.getLogger(javaClass)
    private val keys = ConcurrentHashMap<WatchKey, Long>()
    private val registered = ConcurrentHashMap.newKeySet<String>()
    private val dirtyAt = ConcurrentHashMap<Long, Long>()
    private var watcher: WatchService? = null
    @Volatile private var watchThread: Thread? = null
    private val lock = Any()

    @EventListener(ApplicationReadyEvent::class)
    fun start() {
        applyWatchSetting()
    }

    @EventListener
    fun onSettings(event: AppSettingsChangedEvent) {
        if (event.previous?.watchEnabled != event.current.watchEnabled) {
            applyWatchSetting()
        }
    }

    fun unregisterLibrary(libraryId: Long) {
        synchronized(lock) {
            dirtyAt.remove(libraryId)
            val doomed = keys.entries.filter { it.value == libraryId }.map { it.key }
            for (key in doomed) {
                val path = (key.watchable() as? Path)?.let(LibraryPaths::displayPath)
                key.cancel()
                keys.remove(key)
                if (path != null) registered.remove(path)
            }
        }
    }

    fun registerLibrary(library: MediaLibrary) {
        val service = watcher ?: return
        val libraryId = library.id ?: return
        val root = Path.of(library.rootPath).toAbsolutePath().normalize()
        if (!root.isDirectory() || !LibraryPaths.isUnderMediaRoots(root)) {
            log.warn("资料库根目录无法监听 libraryId={} path={}", libraryId, library.rootPath)
            return
        }
        try {
            Files.walk(root).use { stream ->
                stream.filter { it.isDirectory() }.forEach { dir ->
                    registerDir(service, libraryId, dir)
                }
            }
        } catch (e: Exception) {
            log.error("注册资料库监听失败 libraryId={} path={}", libraryId, root, e)
        }
    }

    @Scheduled(fixedDelay = 2000)
    fun flushDirty() {
        val now = System.currentTimeMillis()
        val ready = dirtyAt.entries.filter { now - it.value >= DEBOUNCE_MS }
        for ((libraryId, markedAt) in ready) {
            if (dirtyAt.remove(libraryId, markedAt)) {
                reconcile.requestScan(libraryId)
            }
        }
    }

    @PreDestroy
    fun stop() {
        stopWatching()
    }

    private fun applyWatchSetting() {
        if (appSettings.current().watchEnabled) {
            startWatching()
        } else {
            log.info("目录监听已关闭")
            stopWatching()
        }
    }

    private fun startWatching() {
        synchronized(lock) {
            if (watcher != null) return
            val service = try {
                FileSystems.getDefault().newWatchService()
            } catch (e: Exception) {
                log.error("无法创建目录监听，改为只使用定时扫描", e)
                return
            }
            watcher = service
            keys.clear()
            registered.clear()
            libraries.findAll().forEach { registerLibrary(it) }
            watchThread = thread(name = "library-watch", isDaemon = true) {
                loop(service)
            }
            log.info("目录监听已开启")
        }
    }

    private fun stopWatching() {
        synchronized(lock) {
            watchThread?.interrupt()
            watchThread = null
            try {
                watcher?.close()
            } catch (e: Exception) {
                log.debug("关闭目录监听失败: {}", e.message)
            }
            watcher = null
            keys.clear()
            registered.clear()
        }
    }

    private fun loop(service: WatchService) {
        try {
            while (!Thread.currentThread().isInterrupted) {
                val key = service.take()
                val libraryId = keys[key]
                if (libraryId != null) {
                    drain(key, libraryId)
                    dirtyAt[libraryId] = System.currentTimeMillis()
                }
                if (!key.reset()) {
                    keys.remove(key)
                    registered.remove((key.watchable() as? Path)?.let(LibraryPaths::displayPath))
                }
            }
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
        } catch (_: ClosedWatchServiceException) {
            log.info("目录监听已停止")
        } catch (e: Exception) {
            log.error("目录监听退出，后续变化交给定时扫描", e)
        }
    }

    private fun drain(key: WatchKey, libraryId: Long) {
        val service = watcher ?: return
        val dir = key.watchable() as? Path ?: return
        for (event in key.pollEvents()) {
            if (event.kind() == OVERFLOW) {
                log.warn("目录事件溢出，将整库对账 libraryId={}", libraryId)
                continue
            }
            val name = event.context() as? Path ?: continue
            if (event.kind() != ENTRY_CREATE) continue
            val child = dir.resolve(name)
            if (child.isDirectory()) {
                registerTree(service, libraryId, child)
            }
        }
    }

    private fun registerTree(service: WatchService, libraryId: Long, root: Path) {
        try {
            Files.walk(root).use { stream ->
                stream.filter { it.isDirectory() }.forEach { dir ->
                    registerDir(service, libraryId, dir)
                }
            }
        } catch (e: Exception) {
            log.warn("注册新目录监听失败 libraryId={} path={} reason={}", libraryId, root, e.message)
        }
    }

    private fun registerDir(service: WatchService, libraryId: Long, dir: Path) {
        val display = LibraryPaths.displayPath(dir)
        if (!registered.add(display)) return
        try {
            val key = dir.register(service, ENTRY_CREATE, ENTRY_DELETE, ENTRY_MODIFY)
            keys[key] = libraryId
        } catch (e: Exception) {
            registered.remove(display)
            log.warn("监听目录失败 libraryId={} path={} reason={}", libraryId, display, e.message)
        }
    }

    companion object {
        private const val DEBOUNCE_MS = 4_000L
    }
}
