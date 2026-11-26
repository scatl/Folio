package com.scatl.folio.dto

data class ApiResponse<T>(
    val code: Int,
    val data: T?,
    val msg: String,
) {
    companion object {
        fun <T> ok(data: T?): ApiResponse<T> = ApiResponse(0, data, "")

        fun fail(code: Int, msg: String): ApiResponse<Nothing> = ApiResponse(code, null, msg)
    }
}

