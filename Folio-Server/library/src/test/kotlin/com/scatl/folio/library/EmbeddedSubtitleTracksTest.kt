package com.scatl.folio.library

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class EmbeddedSubtitleTracksTest {
    @Test
    fun keepsTextTracksAndSkipsImages() {
        val body = """
            {
              "streams": [
                {"codec_name":"hdmv_pgs_subtitle","codec_type":"subtitle","tags":{"language":"eng","title":"English PGS"}},
                {"codec_name":"ass","codec_type":"subtitle","tags":{"language":"chi","title":"简体"}},
                {"codec_name":"subrip","codec_type":"subtitle","tags":{"language":"und"}}
              ]
            }
        """.trimIndent()
        val tracks = parseEmbeddedSubtitles(body)
        assertEquals(2, tracks.size)
        assertEquals(1, tracks[0].index)
        assertEquals("ass", tracks[0].codec)
        assertEquals("chi", tracks[0].language)
        assertEquals("简体", tracks[0].title)
        assertEquals(2, tracks[1].index)
        assertEquals("subrip", tracks[1].codec)
        assertEquals(null, tracks[1].language)
    }

    @Test
    fun imageCodecsAreNotText() {
        assertFalse(isTextSubtitleCodec("hdmv_pgs_subtitle"))
        assertFalse(isTextSubtitleCodec("dvd_subtitle"))
        assertTrue(isTextSubtitleCodec("ASS"))
        assertTrue(isTextSubtitleCodec("webvtt"))
    }
}
