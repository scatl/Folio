package com.scatl.folio.server

import com.scatl.folio.dto.LocalEndpointView
import java.net.Inet4Address
import java.net.Inet6Address
import java.net.InetAddress
import java.net.NetworkInterface
import java.net.SocketException
import java.util.Collections

object LocalEndpoints {
    fun list(https: Boolean, port: Int, contextPath: String): List<LocalEndpointView> {
        val interfaces = try {
            val found = NetworkInterface.getNetworkInterfaces() ?: return emptyList()
            Collections.list(found)
        } catch (_: SocketException) {
            return emptyList()
        }
        return interfaces
            .filter { nic ->
                try {
                    nic.isUp && !nic.isLoopback
                } catch (_: SocketException) {
                    false
                }
            }
            .flatMap { nic ->
                Collections.list(nic.inetAddresses).mapNotNull { address ->
                    endpoint(nic.name, address, https, port, contextPath)
                }
            }
            .distinctBy { it.address }
            .sortedWith(compareBy({ it.name }, { it.address }))
    }

    fun isAdvertised(address: InetAddress): Boolean {
        if (address.isAnyLocalAddress || address.isLoopbackAddress || address.isLinkLocalAddress || address.isMulticastAddress) {
            return false
        }
        if (address is Inet4Address) return address.isSiteLocalAddress
        if (address is Inet6Address) return isUla(address)
        return false
    }

    fun origin(https: Boolean, host: String, port: Int, contextPath: String): String {
        val scheme = if (https) "https" else "http"
        val literal = if (host.contains(':')) "[${host.substringBefore('%')}]" else host
        return "$scheme://$literal:$port${normalizeContext(contextPath)}"
    }

    private fun endpoint(
        name: String,
        address: InetAddress,
        https: Boolean,
        port: Int,
        contextPath: String,
    ): LocalEndpointView? {
        if (!isAdvertised(address)) return null
        val host = address.hostAddress?.substringBefore('%')?.takeIf { it.isNotBlank() } ?: return null
        return LocalEndpointView(name = name, address = host, url = origin(https, host, port, contextPath))
    }

    private fun isUla(address: Inet6Address): Boolean {
        val first = address.address[0].toInt() and 0xff
        return first and 0xfe == 0xfc
    }

    private fun normalizeContext(contextPath: String): String {
        val path = contextPath.trim().trimEnd('/')
        if (path.isEmpty() || path == "/") return ""
        return if (path.startsWith("/")) path else "/$path"
    }
}
