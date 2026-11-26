package com.scatl.folio.provider

import org.springframework.boot.json.JsonParserFactory
import org.springframework.http.HttpHeaders
import org.springframework.http.HttpStatusCode
import org.springframework.http.MediaType
import org.springframework.web.client.RestClient
import org.springframework.web.client.body
import org.springframework.web.util.UriBuilder
import java.net.URI
import java.nio.charset.StandardCharsets
import java.time.LocalDate
import java.time.format.DateTimeParseException
import java.util.concurrent.TimeUnit

class ProviderException(val provider: String, val status: Int, message: String) : RuntimeException(message)

class RateLimitException(val provider: String, val retryAfterSeconds: Long) :
    RuntimeException("$provider 触发频率限制") {
    val delaySeconds: Long = retryAfterSeconds.coerceAtLeast(1)
}

class RequestPacer(requestsPerSecond: Double) {
    private val intervalNanos: Long
    private var nextAllowed: Long = 0

    init {
        require(requestsPerSecond > 0) { "requestsPerSecond 必须大于 0" }
        intervalNanos = (1_000_000_000.0 / requestsPerSecond).toLong()
    }

    fun acquire() {
        val waitNanos = synchronized(this) {
            val now = System.nanoTime()
            if (now < nextAllowed) {
                val wait = nextAllowed - now
                nextAllowed += intervalNanos
                wait
            } else {
                nextAllowed = now + intervalNanos
                0
            }
        }
        if (waitNanos > 0) {
            try {
                TimeUnit.NANOSECONDS.sleep(waitNanos)
            } catch (ex: InterruptedException) {
                Thread.currentThread().interrupt()
                throw IllegalStateException("请求被中断", ex)
            }
        }
    }
}

internal object Dates {
    fun parse(value: String?): LocalDate? {
        if (value == null || value.length < 10) {
            return null
        }
        return try {
            LocalDate.parse(value.substring(0, 10))
        } catch (_: DateTimeParseException) {
            null
        }
    }
}

internal object JsonBodies {
    fun read(provider: String, body: String?): Map<String, Any?> {
        if (body.isNullOrBlank()) {
            throw ProviderException(provider, 200, "$provider 响应为空")
        }
        return try {
            @Suppress("UNCHECKED_CAST")
            JsonParserFactory.getJsonParser().parseMap(body) as Map<String, Any?>
        } catch (ex: RuntimeException) {
            throw ProviderException(provider, 200, "$provider 响应无法解析")
        }
    }

    fun map(value: Any?): Map<String, Any?> {
        val raw = value as? Map<*, *> ?: return emptyMap()
        return raw.entries.associate { it.key.toString() to it.value }
    }

    fun maps(value: Any?): List<Map<String, Any?>> {
        val list = value as? List<*> ?: return emptyList()
        return list.mapNotNull { item ->
            if (item is Map<*, *>) item.entries.associate { it.key.toString() to it.value } else null
        }
    }

    fun text(map: Map<String, Any?>, key: String): String? {
        val value = map[key] ?: return null
        val text = value.toString().trim()
        return if (text.isEmpty() || text == "null") null else text
    }

    fun integer(map: Map<String, Any?>, key: String): Int? = when (val value = map[key]) {
        is Number -> value.toInt()
        is String -> value.trim().toIntOrNull()
        else -> null
    }

    fun decimal(map: Map<String, Any?>, key: String): Double? = when (val value = map[key]) {
        is Number -> value.toDouble()
        is String -> value.trim().toDoubleOrNull()
        else -> null
    }

    fun longValue(map: Map<String, Any?>, key: String): Long? = when (val value = map[key]) {
        is Number -> value.toLong()
        is String -> value.trim().toLongOrNull()
        else -> null
    }

    fun bool(map: Map<String, Any?>, key: String): Boolean? = when (val value = map[key]) {
        is Boolean -> value
        is String -> value.equals("true", ignoreCase = true)
        else -> null
    }
}

internal object ProviderHttp {
    fun get(
        client: RestClient,
        pacer: RequestPacer,
        provider: String,
        uri: (UriBuilder) -> URI,
        authorization: String? = null,
    ): String {
        pacer.acquire()
        var spec = client.get().uri(uri)
        if (authorization != null) {
            spec = spec.header(HttpHeaders.AUTHORIZATION, authorization)
        }
        return spec.retrieve()
            .onStatus({ it.value() == 429 }) { _, response ->
                throw RateLimitException(provider, retryAfter(response.headers))
            }
            .onStatus(HttpStatusCode::isError) { _, response ->
                throw ProviderException(provider, response.statusCode.value(), "$provider 请求失败，HTTP ${response.statusCode.value()}")
            }
            .body<String>()!!
    }

    fun postJson(client: RestClient, pacer: RequestPacer, provider: String, path: String, json: String): String {
        pacer.acquire()
        return client.post()
            .uri(path)
            .contentType(MediaType.APPLICATION_JSON)
            .body(json.toByteArray(StandardCharsets.UTF_8))
            .retrieve()
            .onStatus({ it.value() == 429 }) { _, response ->
                throw RateLimitException(provider, retryAfter(response.headers))
            }
            .onStatus(HttpStatusCode::isError) { _, response ->
                throw ProviderException(provider, response.statusCode.value(), "$provider 请求失败，HTTP ${response.statusCode.value()}")
            }
            .body<String>()!!
    }

    private fun retryAfter(headers: HttpHeaders): Long {
        val header = headers.getFirst(HttpHeaders.RETRY_AFTER)
        return header?.trim()?.toLongOrNull()?.coerceAtLeast(1) ?: 10
    }
}
