package com.scatl.folio.library

import org.springframework.stereotype.Component
import java.time.Duration
import java.time.Instant
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.locks.ReentrantLock

/**
 * 同一个标题只有一个任务去搜索并写入别名。详情按剧集编号串行拉取。
 * 别名确定之后，TVDB 和文件特征值不再占用这把锁。
 */
@Component
class SeriesFetchCoordinator {
    private val locks = ConcurrentHashMap<Long, ReentrantLock>()
    private val titleLocks = ConcurrentHashMap<String, ReentrantLock>()
    private val refreshedAt = ConcurrentHashMap<Long, Instant>()

    fun refreshedRecently(tmdbId: Long, within: Duration): Boolean {
        val at = refreshedAt[tmdbId] ?: return false
        return Duration.between(at, Instant.now()) < within
    }

    fun markRefreshed(tmdbId: Long) {
        refreshedAt[tmdbId] = Instant.now()
    }

    fun <T> call(tmdbId: Long, action: () -> T): T = locked(locks, tmdbId, action)

    /** 同一个解析标题只有一个任务去搜索。其余任务等别名写入后再沿用。 */
    fun <T> callTitle(titleKey: String, action: () -> T): T = locked(titleLocks, titleKey, action)

    private fun <K, T> locked(guard: ConcurrentHashMap<K, ReentrantLock>, key: K, action: () -> T): T {
        val lock = guard.computeIfAbsent(key) { ReentrantLock(true) }
        lock.lock()
        try {
            return action()
        } finally {
            lock.unlock()
        }
    }
}
