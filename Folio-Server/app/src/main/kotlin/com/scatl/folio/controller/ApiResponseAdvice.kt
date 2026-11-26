package com.scatl.folio.controller

import com.scatl.folio.dto.ApiResponse
import org.springframework.core.MethodParameter
import org.springframework.http.MediaType
import org.springframework.http.ResponseEntity
import org.springframework.http.converter.HttpMessageConverter
import org.springframework.http.server.ServerHttpRequest
import org.springframework.http.server.ServerHttpResponse
import org.springframework.web.bind.annotation.RestControllerAdvice
import org.springframework.web.servlet.mvc.method.annotation.ResponseBodyAdvice
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter
import java.lang.reflect.ParameterizedType

@RestControllerAdvice
class ApiResponseAdvice : ResponseBodyAdvice<Any> {
    override fun supports(returnType: MethodParameter, converterType: Class<out HttpMessageConverter<*>>): Boolean {
        val raw = returnType.parameterType
        if (raw == Void.TYPE || raw == Void::class.java || raw.name == "kotlin.Unit") return false
        if (isSse(raw, returnType.genericParameterType)) return false
        return true
    }

    override fun beforeBodyWrite(
        body: Any?,
        returnType: MethodParameter,
        selectedContentType: MediaType,
        selectedConverterType: Class<out HttpMessageConverter<*>>,
        request: ServerHttpRequest,
        response: ServerHttpResponse,
    ): Any? {
        if (body is SseEmitter || body is ApiResponse<*>) return body
        if (selectedContentType.includes(MediaType.TEXT_EVENT_STREAM)) return body
        return ApiResponse.ok(body)
    }

    private fun isSse(raw: Class<*>, generic: java.lang.reflect.Type): Boolean {
        if (SseEmitter::class.java.isAssignableFrom(raw)) return true
        if (generic.typeName.contains("SseEmitter")) return true
        if (ResponseEntity::class.java.isAssignableFrom(raw) && generic is ParameterizedType) {
            val arg = generic.actualTypeArguments.firstOrNull() ?: return false
            if (arg.typeName.contains("SseEmitter")) return true
            if (arg is Class<*> && SseEmitter::class.java.isAssignableFrom(arg)) return true
        }
        return false
    }
}
