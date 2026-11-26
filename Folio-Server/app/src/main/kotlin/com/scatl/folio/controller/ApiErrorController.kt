package com.scatl.folio.controller

import com.scatl.folio.dto.ApiResponse
import jakarta.servlet.RequestDispatcher
import jakarta.servlet.http.HttpServletRequest
import org.springframework.http.HttpStatus
import org.springframework.http.ResponseEntity
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

@RestController
class ApiErrorController : org.springframework.boot.webmvc.error.ErrorController {
    @RequestMapping("/error")
    fun error(request: HttpServletRequest): ResponseEntity<ApiResponse<Nothing>> {
        val code = request.getAttribute(RequestDispatcher.ERROR_STATUS_CODE) as? Int ?: 500
        val status = HttpStatus.resolve(code) ?: HttpStatus.INTERNAL_SERVER_ERROR
        val msg = if (code == 404) "接口不存在" else "请求失败"
        return ResponseEntity.status(status).body(ApiResponse.fail(code, msg))
    }
}

