package com.scatl.folio.library

import jakarta.annotation.PreDestroy
import org.slf4j.LoggerFactory
import org.springframework.http.MediaType
import org.springframework.scheduling.annotation.Scheduled
import org.springframework.stereotype.Component
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter
import tools.jackson.databind.json.JsonMapper
import java.io.IOException
import java.util.concurrent.CopyOnWriteArrayList

@Component
class ScrapeEventHub(
    private val jsonMapper: JsonMapper,
) {
    private val log = LoggerFactory.getLogger(javaClass)
    private val emitters = CopyOnWriteArrayList<SseEmitter>()

    fun subscribe(): SseEmitter {
        val emitter = SseEmitter(0L)
        emitters.add(emitter)
        emitter.onCompletion { emitters.remove(emitter) }
        emitter.onTimeout {
            emitters.remove(emitter)
            emitter.complete()
        }
        emitter.onError {
            emitters.remove(emitter)
        }
        try {
            emitter.send(
                SseEmitter.event()
                    .name("hello")
                    .data("""{"ok":true}""", MediaType.APPLICATION_JSON),
            )
        } catch (ex: IOException) {
            emitters.remove(emitter)
            emitter.completeWithError(ex)
        }
        log.debug("SSE 已订阅 connections={}", emitters.size)
        return emitter
    }

    fun publish(eventName: String, payload: Any) {
        if (emitters.isEmpty()) return
        val json = try {
            jsonMapper.writeValueAsString(payload)
        } catch (ex: Exception) {
            log.warn("SSE 序列化失败 event={} reason={}", eventName, ex.message)
            return
        }
        val dead = mutableListOf<SseEmitter>()
        for (emitter in emitters) {
            try {
                emitter.send(
                    SseEmitter.event()
                        .name(eventName)
                        .data(json, MediaType.APPLICATION_JSON),
                )
            } catch (_: Exception) {
                dead.add(emitter)
            }
        }
        drop(dead)
    }

    @Scheduled(fixedDelayString = "20000")
    fun heartbeat() {
        if (emitters.isEmpty()) return
        val dead = mutableListOf<SseEmitter>()
        for (emitter in emitters) {
            try {
                emitter.send(SseEmitter.event().comment("ping"))
            } catch (_: Exception) {
                dead.add(emitter)
            }
        }
        drop(dead)
    }

    /** 客户端已断开时只移除，勿再 complete()，否则会二次触发 AsyncRequestNotUsableException */
    private fun drop(dead: Collection<SseEmitter>) {
        if (dead.isEmpty()) return
        emitters.removeAll(dead.toSet())
        log.debug("SSE 清理断开连接 count={} remaining={}", dead.size, emitters.size)
    }

    @PreDestroy
    fun shutdown() {
        emitters.forEach { runCatching { it.complete() } }
        emitters.clear()
    }
}
