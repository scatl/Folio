package com.scatl.folio.library

/**
 * 电影：任一文件看完即已看；只有未看完进度则在看。
 * 剧集：范围内的文件全部看完才算已看；看过一部分则在看。
 */
object WatchStates {
    const val UNWATCHED = "unwatched"
    const val WATCHING = "watching"
    const val WATCHED = "watched"

    fun of(kind: String, files: Int, completed: Int, started: Int): String {
        if (files <= 0) return UNWATCHED
        if (kind == "movie") {
            if (completed > 0) return WATCHED
            if (started > 0) return WATCHING
            return UNWATCHED
        }
        if (completed >= files) return WATCHED
        if (completed > 0 || started > 0) return WATCHING
        return UNWATCHED
    }
}
