package com.scatl.folio.home

import com.scatl.folio.dto.HomeView
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/api/home")
class HomeController(
    private val home: HomeService,
) {
    @GetMapping
    fun get(): HomeView = home.home()
}
