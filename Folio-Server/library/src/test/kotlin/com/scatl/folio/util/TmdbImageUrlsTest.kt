package com.scatl.folio.util

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class TmdbImageUrlsTest {
    @Test
    fun storesWithCanonicalBase() {
        assertEquals(
            "https://image.tmdb.org/t/p/original/abc123.jpg",
            TmdbImageUrls.store("/abc123.jpg"),
        )
        assertEquals(
            "https://image.tmdb.org/t/p/original/abc123.jpg",
            TmdbImageUrls.store("abc123.jpg"),
        )
    }

    @Test
    fun rewritesOfficialCdnWithNewBase() {
        val stored = "https://image.tmdb.org/t/p/original/abc123.jpg"
        val resolved = TmdbImageUrls.resolve(stored, "https://cdn.example.com/t/p/original")
        assertEquals("https://cdn.example.com/t/p/original/abc123.jpg", resolved)
    }

    @Test
    fun rewritesProxyAndOverridesSize() {
        val stored = "https://old.example.com/t/p/original/abc123.jpg"
        val resolved = TmdbImageUrls.resolve(stored, "https://new.example.com/t/p/original", size = "w342")
        assertEquals("https://new.example.com/t/p/w342/abc123.jpg", resolved)
    }

    @Test
    fun leavesNonTmdbUrlsAlone() {
        val stored = "https://artworks.thetvdb.com/banners/posters/123.jpg"
        assertEquals(stored, TmdbImageUrls.resolve(stored, "https://cdn.example.com/t/p/original"))
    }

    @Test
    fun extractsRelativeFilePath() {
        assertEquals("/abc123.jpg", TmdbImageUrls.filePath("https://image.tmdb.org/t/p/w500/abc123.jpg"))
        assertEquals("/abc123.jpg", TmdbImageUrls.filePath("/abc123.jpg"))
        assertNull(TmdbImageUrls.filePath("https://example.com/foo.jpg"))
    }
}
