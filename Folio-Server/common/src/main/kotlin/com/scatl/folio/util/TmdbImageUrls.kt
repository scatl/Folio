package com.scatl.folio.util

/**
 * 入库始终用官方地址；接口返回时按设置的图片前缀重写。
 */
object TmdbImageUrls {
    const val CANONICAL_BASE = "https://image.tmdb.org/t/p/original"

    /** 刮削入库用：相对路径 → 官方完整 URL */
    fun store(path: String?): String? {
        if (path.isNullOrBlank()) return null
        val suffix = if (path.startsWith("/")) path else "/$path"
        return trimSlash(CANONICAL_BASE) + suffix
    }

    /** 读接口用：已存 URL 按当前图片前缀重写 */
    fun resolve(stored: String?, imageBaseUrl: String, size: String? = null): String? {
        if (stored.isNullOrBlank()) return stored
        val path = filePath(stored) ?: return stored
        val base = baseWithSize(imageBaseUrl, size)
        return trimSlash(base) + path
    }

    /** 从完整 URL 中取出 `/xxxx.jpg` 这类文件路径；非 TMDB 形态则返回 null。 */
    fun filePath(url: String): String? {
        val marker = "/t/p/"
        val idx = url.indexOf(marker, ignoreCase = true)
        if (idx >= 0) {
            val after = url.substring(idx + marker.length)
                .substringBefore('&')
                .substringBefore('?')
            val slash = after.indexOf('/')
            if (slash < 0) return null
            val path = after.substring(slash)
            return if (path.startsWith("/")) path else "/$path"
        }
        // 仅文件路径：/abc.jpg
        if (
            url.startsWith("/") &&
            !url.startsWith("//") &&
            !url.contains("://") &&
            url.count { it == '/' } == 1 &&
            url.contains('.')
        ) {
            return url
        }
        return null
    }

    private fun baseWithSize(imageBaseUrl: String, size: String?): String {
        var base = imageBaseUrl.trim().trimEnd('/')
        if (size.isNullOrBlank()) return base
        val marker = "/t/p/"
        val idx = base.lastIndexOf(marker)
        if (idx < 0) return base
        return base.substring(0, idx + marker.length) + size
    }

    private fun trimSlash(value: String): String = value.trimEnd('/')
}
