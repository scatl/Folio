package com.scatl.folio.library

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

class MediaSegmentLogicTest {
    @Test
    fun readsTheIntroDbNullEnds() {
        val rows = MediaSegmentLogic.fromTheIntroDb(
            mapOf(
                "intro" to listOf(mapOf("start_ms" to null, "end_ms" to 90_000)),
                "credits" to listOf(mapOf("start_ms" to 1_800_000, "end_ms" to null)),
            ),
        )
        assertEquals(2, rows.size)
        assertEquals(MediaSegmentLogic.INTRO, rows[0].kind)
        assertEquals(0L, rows[0].startMs)
        assertEquals(90_000L, rows[0].endMs)
        assertEquals(MediaSegmentLogic.CREDITS, rows[1].kind)
        assertNull(rows[1].endMs)
    }

    @Test
    fun dropsIntroThatRunsTooLong() {
        val rows = MediaSegmentLogic.fromTheIntroDb(
            mapOf("intro" to listOf(mapOf("start_ms" to 0, "end_ms" to 20 * 60_000))),
        )
        assertEquals(0, rows.size)
    }

    @Test
    fun mapsIntroDbOutroToCredits() {
        val rows = MediaSegmentLogic.fromIntroDb(
            mapOf(
                "intro" to mapOf("start_sec" to 2.5, "end_sec" to 58),
                "outro" to mapOf("start_ms" to 1_800_000, "end_ms" to 2_100_000),
                "post_credits" to mapOf("start_ms" to 2_050_000, "end_ms" to 2_090_000),
            ),
        )
        assertEquals(listOf(MediaSegmentLogic.INTRO, MediaSegmentLogic.CREDITS, MediaSegmentLogic.POST_CREDITS), rows.map { it.kind })
        assertEquals(2_500L, rows[0].startMs)
        assertEquals(58_000L, rows[0].endMs)
    }

    @Test
    fun mergeKeepsPrimaryKindAndFillsGaps() {
        val primary = listOf(MediaSegment(MediaSegmentLogic.INTRO, 0, 40_000))
        val extra = listOf(
            MediaSegment(MediaSegmentLogic.INTRO, 1_000, 50_000),
            MediaSegment(MediaSegmentLogic.CREDITS, 1_200_000, null),
        )
        val merged = MediaSegmentLogic.merge(primary, extra)
        assertEquals(2, merged.size)
        assertEquals(40_000L, merged[0].endMs)
        assertEquals(MediaSegmentLogic.CREDITS, merged[1].kind)
    }

    @Test
    fun theIntroDbQueryUsesSnakeCase() {
        val movie = MediaSegmentLogic.theIntroDbQuery(
            movie = true,
            tmdbId = 10783,
            imdbId = "tt0120731",
            season = null,
            episode = null,
            durationMs = 9_900_000,
        )
        assertEquals(mapOf("tmdb_id" to 10783L, "duration_ms" to 9_900_000L), movie)
        val episode = MediaSegmentLogic.theIntroDbQuery(
            movie = false,
            tmdbId = null,
            imdbId = "tt0903747",
            season = 1,
            episode = 1,
            durationMs = null,
        )
        assertEquals(mapOf("imdb_id" to "tt0903747", "season" to 1, "episode" to 1), episode)
        assertNull(
            MediaSegmentLogic.theIntroDbQuery(
                movie = true,
                tmdbId = null,
                imdbId = null,
                season = null,
                episode = null,
                durationMs = null,
            ),
        )
    }

    @Test
    fun bucketsDurationToNearestMinute() {
        assertEquals(0, MediaSegmentLogic.durationBucket(null))
        assertEquals(0, MediaSegmentLogic.durationBucket(0))
        assertEquals(40, MediaSegmentLogic.durationBucket(40 * 60_000L - 20_000L))
        assertEquals(41, MediaSegmentLogic.durationBucket(40 * 60_000L + 30_000L))
    }
}
