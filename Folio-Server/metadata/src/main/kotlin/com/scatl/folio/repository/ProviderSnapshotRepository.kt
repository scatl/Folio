package com.scatl.folio.repository

import com.scatl.folio.entity.ProviderSnapshot
import org.springframework.data.jpa.repository.JpaRepository

interface ProviderSnapshotRepository : JpaRepository<ProviderSnapshot, Long>
