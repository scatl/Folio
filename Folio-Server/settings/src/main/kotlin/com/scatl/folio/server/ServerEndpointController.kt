package com.scatl.folio.server

import com.scatl.folio.dto.RemoteUrlUpdateRequest
import com.scatl.folio.dto.ServerConnectionsView
import com.scatl.folio.dto.ServerIdentityView
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PutMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/api/server")
class ServerEndpointController(
    private val endpoints: ServerEndpointService,
) {
    @GetMapping("/identity")
    fun identity(): ServerIdentityView = endpoints.identity()

    @GetMapping("/connections")
    fun connections(): ServerConnectionsView = endpoints.connections()

    @PutMapping("/remote")
    fun updateRemote(@RequestBody body: RemoteUrlUpdateRequest): ServerConnectionsView = endpoints.updateRemote(body)
}
