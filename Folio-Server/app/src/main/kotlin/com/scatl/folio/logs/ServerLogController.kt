package com.scatl.folio.logs

import org.springframework.core.env.Environment
import org.springframework.http.HttpStatus
import org.springframework.stereotype.Service
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.RestController
import org.springframework.web.server.ResponseStatusException
import java.io.IOException
import java.io.UncheckedIOException
import java.nio.file.Files

@RestController
@RequestMapping("/api/logs/server")
class ServerLogController(
    private val logs: ServerLogService,
) {
    @GetMapping
    fun list(): ServerLogListView = logs.list()

    @GetMapping("/content")
    fun content(@RequestParam name: String): ServerLogContentView = logs.read(name)
}

@Service
class ServerLogService(
    private val environment: Environment,
) {
    fun list(): ServerLogListView {
        val dir = directory() ?: return ServerLogListView(
            directory = null,
            available = false,
            message = "没有找到日志目录。容器内日志写在 /data/logs；未设置 FOLIO_LOG_FILE 时不会生成文件。",
            files = emptyList(),
        )
        if (!Files.isDirectory(dir)) {
            return ServerLogListView(
                directory = dir.toString(),
                available = false,
                message = "日志目录不存在：$dir",
                files = emptyList(),
            )
        }
        return try {
            ServerLogListView(
                directory = dir.toString(),
                available = true,
                message = null,
                files = ServerLogFiles.list(dir),
            )
        } catch (exception: IOException) {
            throw ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR, "无法读取日志目录")
        } catch (exception: UncheckedIOException) {
            throw ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR, "无法读取日志目录")
        }
    }

    fun read(name: String): ServerLogContentView {
        val dir = directory() ?: throw ResponseStatusException(HttpStatus.NOT_FOUND, "日志目录不存在")
        if (!Files.isDirectory(dir)) {
            throw ResponseStatusException(HttpStatus.NOT_FOUND, "日志目录不存在")
        }
        return try {
            ServerLogFiles.read(dir, name)
        } catch (exception: ResponseStatusException) {
            throw exception
        } catch (exception: IOException) {
            throw ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR, "无法读取日志文件")
        } catch (exception: UncheckedIOException) {
            throw ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR, "无法读取日志文件")
        }
    }

    private fun directory() =
        ServerLogFiles.resolveDirectory(environment.getProperty("logging.file.name").orEmpty())
}
