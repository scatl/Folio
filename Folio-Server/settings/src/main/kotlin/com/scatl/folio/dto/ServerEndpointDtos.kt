package com.scatl.folio.dto

data class ServerIdentityView(
    val serverId: String,
)

data class LocalEndpointView(
    val name: String,
    val address: String,
    val url: String,
)

data class ServerConnectionsView(
    val serverId: String,
    val local: List<LocalEndpointView>,
    val remoteUrl: String?,
)

data class RemoteUrlUpdateRequest(
    val remoteUrl: String?,
)
