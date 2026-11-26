package com.scatl.folio.repository

import com.scatl.folio.entity.ServerIdentity
import org.springframework.data.jpa.repository.JpaRepository

interface ServerIdentityRepository : JpaRepository<ServerIdentity, Long>
