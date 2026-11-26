package com.scatl.folio.server

import org.springframework.http.HttpStatus
import org.springframework.web.server.ResponseStatusException
import java.net.URI
import java.net.URISyntaxException

object ServerUrls {
    fun normalizeRemote(raw: String?): String? {
        val url = raw?.trim()?.trimEnd('/')?.takeIf { it.isNotEmpty() } ?: return null
        if (url.length > 512) {
            throw ResponseStatusException(HttpStatus.BAD_REQUEST, "外网地址过长")
        }
        if (!url.startsWith("https://") && !url.startsWith("http://")) {
            throw ResponseStatusException(HttpStatus.BAD_REQUEST, "外网地址必须以 http:// 或 https:// 开头")
        }
        val uri = try {
            URI(url)
        } catch (_: URISyntaxException) {
            throw ResponseStatusException(HttpStatus.BAD_REQUEST, "外网地址无效")
        }
        if (uri.host.isNullOrBlank()) {
            throw ResponseStatusException(HttpStatus.BAD_REQUEST, "外网地址无效")
        }
        return url
    }
}
