package com.scatl.folio.entity

import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.Id
import jakarta.persistence.Table
import java.time.Instant

@Entity
@Table(name = "server_identity")
open class ServerIdentity {
    @Id
    open var id: Long = 1

    @Column(name = "server_id", nullable = false, length = 36)
    open var serverId: String = ""

    @Column(name = "remote_url", length = 512)
    open var remoteUrl: String? = null

    @Column(name = "updated_at", nullable = false)
    open var updatedAt: Instant = Instant.EPOCH
}
