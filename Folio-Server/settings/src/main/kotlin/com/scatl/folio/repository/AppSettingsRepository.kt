package com.scatl.folio.repository

import com.scatl.folio.entity.AppSettings
import org.springframework.data.jpa.repository.JpaRepository

interface AppSettingsRepository : JpaRepository<AppSettings, Long>
