package com.scatl.folio.server

import com.scatl.folio.dto.RemoteUrlUpdateRequest
import com.scatl.folio.dto.ServerConnectionsView
import com.scatl.folio.dto.ServerIdentityView
import com.scatl.folio.entity.ServerIdentity
import com.scatl.folio.repository.ServerIdentityRepository
import org.springframework.core.env.Environment
import org.springframework.dao.DataIntegrityViolationException
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import java.time.Instant
import java.util.UUID

@Service
class ServerEndpointService(
    private val repository: ServerIdentityRepository,
    private val environment: Environment,
) {
    @Volatile
    private var cached: ServerIdentity? = null

    fun identity(): ServerIdentityView = ServerIdentityView(current().serverId)

    fun connections(): ServerConnectionsView = toView(current())

    @Transactional
    fun updateRemote(body: RemoteUrlUpdateRequest): ServerConnectionsView {
        val remoteUrl = ServerUrls.normalizeRemote(body.remoteUrl)
        synchronized(this) {
            val row = load()
            row.remoteUrl = remoteUrl
            row.updatedAt = Instant.now()
            val saved = repository.save(row)
            cached = saved
            return toView(saved)
        }
    }

    private fun current(): ServerIdentity {
        cached?.let { return it }
        synchronized(this) {
            cached?.let { return it }
            val loaded = load()
            cached = loaded
            return loaded
        }
    }

    private fun load(): ServerIdentity {
        repository.findById(ROW_ID).orElse(null)?.let { return it }
        return try {
            repository.save(
                ServerIdentity().apply {
                    id = ROW_ID
                    serverId = UUID.randomUUID().toString()
                    updatedAt = Instant.now()
                },
            )
        } catch (_: DataIntegrityViolationException) {
            repository.findById(ROW_ID).orElseThrow()
        }
    }

    private fun toView(row: ServerIdentity) = ServerConnectionsView(
        serverId = row.serverId,
        local = LocalEndpoints.list(https(), listenPort(), contextPath()),
        remoteUrl = row.remoteUrl?.takeIf { it.isNotBlank() },
    )

    private fun listenPort(): Int {
        val local = environment.getProperty("local.server.port")?.toIntOrNull()
        if (local != null && local > 0) return local
        val configured = environment.getProperty("server.port")?.toIntOrNull()
        if (configured != null && configured > 0) return configured
        return 32700
    }

    private fun https(): Boolean {
        if (environment.getProperty("server.ssl.key-store").isNullOrBlank()) return false
        return !environment.getProperty("server.ssl.enabled", "true").equals("false", ignoreCase = true)
    }

    private fun contextPath(): String = environment.getProperty("server.servlet.context-path").orEmpty()

    companion object {
        private const val ROW_ID = 1L
    }
}
