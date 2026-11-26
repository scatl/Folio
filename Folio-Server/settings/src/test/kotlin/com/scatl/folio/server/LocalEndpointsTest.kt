package com.scatl.folio.server

import org.springframework.web.server.ResponseStatusException
import java.net.InetAddress
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class LocalEndpointsTest {
    @Test
    fun advertisesPrivateLanAddressesOnly() {
        assertTrue(LocalEndpoints.isAdvertised(InetAddress.getByName("192.168.1.8")))
        assertTrue(LocalEndpoints.isAdvertised(InetAddress.getByName("10.1.2.3")))
        assertTrue(LocalEndpoints.isAdvertised(InetAddress.getByName("172.16.0.1")))
        assertTrue(LocalEndpoints.isAdvertised(InetAddress.getByName("172.31.255.255")))
        assertTrue(LocalEndpoints.isAdvertised(InetAddress.getByName("fd00::1")))
        assertFalse(LocalEndpoints.isAdvertised(InetAddress.getByName("8.8.8.8")))
        assertFalse(LocalEndpoints.isAdvertised(InetAddress.getByName("127.0.0.1")))
        assertFalse(LocalEndpoints.isAdvertised(InetAddress.getByName("169.254.1.1")))
        assertFalse(LocalEndpoints.isAdvertised(InetAddress.getByName("172.15.255.255")))
        assertFalse(LocalEndpoints.isAdvertised(InetAddress.getByName("172.32.0.1")))
        assertFalse(LocalEndpoints.isAdvertised(InetAddress.getByName("fe80::1")))
        assertFalse(LocalEndpoints.isAdvertised(InetAddress.getByName("::1")))
    }

    @Test
    fun buildsProbeOrigins() {
        assertEquals("http://192.168.1.8:32700", LocalEndpoints.origin(false, "192.168.1.8", 32700, ""))
        assertEquals("http://[fd00::1]:32700", LocalEndpoints.origin(false, "fd00::1", 32700, ""))
        assertEquals("https://192.168.1.8:443/folio", LocalEndpoints.origin(true, "192.168.1.8", 443, "/folio/"))
    }

    @Test
    fun normalizesRemoteUrl() {
        assertNull(ServerUrls.normalizeRemote(null))
        assertNull(ServerUrls.normalizeRemote("  "))
        assertEquals("https://folio.example.com", ServerUrls.normalizeRemote("https://folio.example.com/"))
        assertEquals("http://203.0.113.8:8443", ServerUrls.normalizeRemote("http://203.0.113.8:8443"))
        assertFailsWith<ResponseStatusException> { ServerUrls.normalizeRemote("folio.example.com") }
        assertFailsWith<ResponseStatusException> { ServerUrls.normalizeRemote("http://") }
    }
}
