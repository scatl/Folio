package com.scatl.folio.config

import org.springframework.stereotype.Controller
import org.springframework.web.bind.annotation.GetMapping

/**
 * Vue history 模式：仅转发前端路由到 index.html，不拦截 /api 与静态资源。
 */
@Controller
class SpaForwardController {
    @GetMapping(
        value = [
            "/login",
            "/login/",
            "/tasks",
            "/tasks/",
            "/settings",
            "/settings/",
            "/logs",
            "/logs/",
            "/review",
            "/review/",
            "/works/**",
            "/playlists/**",
            "/collections/**",
            "/people/**",
            "/play/**",
        ],
    )
    fun forward(): String = "forward:/index.html"
}
