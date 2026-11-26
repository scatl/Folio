package com.scatl.folio.settings

import com.scatl.folio.dto.AppSettingsUpdateRequest
import com.scatl.folio.dto.AppSettingsView
import jakarta.validation.Valid
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PutMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/api/settings")
class SettingsController(
    private val settings: AppSettingsService,
) {
    @GetMapping
    fun get(): AppSettingsView = settings.view()

    @PutMapping
    fun update(@Valid @RequestBody body: AppSettingsUpdateRequest): AppSettingsView = settings.update(body)
}
