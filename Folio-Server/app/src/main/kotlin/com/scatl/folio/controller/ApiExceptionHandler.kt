package com.scatl.folio.controller

import com.scatl.folio.dto.ApiResponse
import org.apache.catalina.connector.ClientAbortException
import org.slf4j.LoggerFactory
import org.springframework.http.HttpStatus
import org.springframework.http.ResponseEntity
import org.springframework.web.bind.MethodArgumentNotValidException
import org.springframework.web.bind.MissingServletRequestParameterException
import org.springframework.web.bind.annotation.ExceptionHandler
import org.springframework.web.bind.annotation.RestControllerAdvice
import org.springframework.web.context.request.async.AsyncRequestNotUsableException
import org.springframework.web.method.annotation.HandlerMethodValidationException
import org.springframework.web.servlet.resource.NoResourceFoundException
import org.springframework.web.server.ResponseStatusException
import java.io.IOException

@RestControllerAdvice
class ApiExceptionHandler {
    private val log = LoggerFactory.getLogger(javaClass)

    @ExceptionHandler(
        AsyncRequestNotUsableException::class,
        ClientAbortException::class,
    )
    fun clientGone(exception: Exception) {
        // SSE / 长连接：浏览器刷新或关掉页时连接已断，无需写 JSON 响应
        log.debug("客户端已断开: {}", exception.message)
    }

    @ExceptionHandler(ResponseStatusException::class)
    fun status(exception: ResponseStatusException): ResponseEntity<ApiResponse<Nothing>> {
        val code = exception.statusCode.value()
        return ResponseEntity.status(exception.statusCode)
            .body(ApiResponse.fail(code, exception.reason ?: "请求失败"))
    }

    @ExceptionHandler(MethodArgumentNotValidException::class)
    fun invalid(exception: MethodArgumentNotValidException): ResponseEntity<ApiResponse<Nothing>> {
        val message = exception.bindingResult.fieldErrors.firstOrNull()
            ?.let { "${it.field} ${it.defaultMessage}" }
            ?: "请求无效"
        return ResponseEntity.badRequest().body(ApiResponse.fail(400, message))
    }

    @ExceptionHandler(HandlerMethodValidationException::class)
    fun paramInvalid(exception: HandlerMethodValidationException): ResponseEntity<ApiResponse<Nothing>> {
        val message = exception.parameterValidationResults
            .flatMap { it.resolvableErrors }
            .firstNotNullOfOrNull { it.defaultMessage }
            ?: "请求无效"
        return ResponseEntity.badRequest().body(ApiResponse.fail(400, message))
    }

    @ExceptionHandler(MissingServletRequestParameterException::class)
    fun missingParam(exception: MissingServletRequestParameterException): ResponseEntity<ApiResponse<Nothing>> =
        ResponseEntity.badRequest().body(ApiResponse.fail(400, "${exception.parameterName} 不能为空"))

    @ExceptionHandler(NoResourceFoundException::class)
    fun missing(): ResponseEntity<ApiResponse<Nothing>> =
        ResponseEntity.status(HttpStatus.NOT_FOUND).body(ApiResponse.fail(404, "接口不存在"))

    @ExceptionHandler(Exception::class)
    fun unexpected(exception: Exception): ResponseEntity<ApiResponse<Nothing>>? {
        if (isClientDisconnect(exception)) {
            log.debug("客户端已断开: {}", exception.message)
            return null
        }
        log.error("接口处理失败", exception)
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(ApiResponse.fail(500, "服务器错误"))
    }

    private fun isClientDisconnect(exception: Throwable): Boolean {
        var current: Throwable? = exception
        while (current != null) {
            when (current) {
                is AsyncRequestNotUsableException,
                is ClientAbortException,
                -> return true
                is IOException -> {
                    val msg = current.message.orEmpty()
                    if (
                        msg.contains("中止了一个已建立的连接") ||
                        msg.contains("Broken pipe", ignoreCase = true) ||
                        msg.contains("Connection reset", ignoreCase = true)
                    ) {
                        return true
                    }
                }
            }
            current = current.cause
        }
        return false
    }
}
