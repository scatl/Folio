package com.scatl.folio.parse

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class FilenameParserTest {
    private val parser = FilenameParser()

    @Test
    fun parsesMovieReleaseName() {
        val parsed = parser.parse("The.Matrix.1999.1080p.BluRay.x264-GROUP.mkv")
        assertEquals("The Matrix", parsed.title)
        assertEquals(1999, parsed.year)
        assertNull(parsed.season)
        assertNull(parsed.episode)
        assertNull(parsed.imdbId)
    }

    @Test
    fun parsesSeasonEpisodeAndChineseTitle() {
        val parsed = parser.parse("D:/media/权力的游戏.S01E02.1080p.mkv")
        assertEquals("权力的游戏", parsed.title)
        assertEquals(1, parsed.season)
        assertEquals(2, parsed.episode)
    }

    @Test
    fun parsesParenthesizedYearAndImdbId() {
        val parsed = parser.parse("Arrival (2016) tt2543164.mp4")
        assertEquals("Arrival", parsed.title)
        assertEquals(2016, parsed.year)
        assertEquals("tt2543164", parsed.imdbId)
    }

    @Test
    fun parsesXEpisodePattern() {
        val parsed = parser.parse("Show.Name.1x03.mkv")
        assertEquals("Show Name", parsed.title)
        assertEquals(1, parsed.season)
        assertEquals(3, parsed.episode)
    }

    @Test
    fun keepsYearWhenItIsTheWholeTitle() {
        val parsed = parser.parse("1922.mkv")
        assertEquals("1922", parsed.title)
        assertEquals(1922, parsed.year)
    }

    @Test
    fun stripsTechTagsAfterYear() {
        val parsed = parser.parse(
            "The.Twilight.Saga.Eclipse.2010.2160p.AMZN.WEB-DL.x265.10bit.HDR10Plus.DTS-HD.MA.5.1-NOGRP",
        )
        assertEquals("The Twilight Saga Eclipse", parsed.title)
        assertEquals(2010, parsed.year)
    }

    @Test
    fun episodeAirYearIsNotUsedAsSeriesYear() {
        val parsed = parser.parse("Better.Call.Saul.S05E10.2020.NF.WEB-DL.2160p.HEVC.DDP-Xiaomi.mkv")
        assertEquals("Better Call Saul", parsed.title)
        assertEquals(2020, parsed.year)
        assertEquals(5, parsed.season)
        assertEquals(10, parsed.episode)
        assertNull(parsed.catalogYear())
    }

    @Test
    fun keepsYearInsideTitleWhenReleaseYearFollows() {
        val parsed = parser.parse("Blade.Runner.2049.2017.1080p.BluRay.x264.mkv")
        assertEquals("Blade Runner 2049", parsed.title)
        assertEquals(2017, parsed.year)
    }

    @Test
    fun parsesJohnWickAndChapter3AsDistinctMovies() {
        val first = parser.parse(
            "John.Wick.2014.2160p.UHD.BluRay.x265.10bit.HDR.TrueHD.7.1.Atmos-RARBG.mkv",
        )
        assertEquals("John Wick", first.title)
        assertEquals(2014, first.year)
        assertNull(first.season)
        assertNull(first.episode)

        val third = parser.parse(
            "John.Wick.Chapter.3.Parabellum.2019.2160p.UHD.BluRay.x265.10bit.HDR.TrueHD.7.1.Atmos-RARBG.mkv",
        )
        // 第三部不能被收成系列根名「John Wick」，否则会命中已入库的第一部。
        assertEquals(
            "John Wick Chapter 3 Parabellum",
            third.title,
            "got title=${third.title} year=${third.year} season=${third.season} episode=${third.episode}",
        )
        assertEquals(2019, third.year)
        assertNull(third.season)
        assertNull(third.episode)
        assertTrue(TitleScore.key(first.title) != TitleScore.key(third.title))
    }
}

class TitleScoreTest {
    @Test
    fun exactTitleAndYearScoreHighest() {
        val score = TitleScore.of("The Matrix", 1999, "黑客帝国", "The Matrix", 1999)
        assertEquals(1.0, score, 0.001)
    }

    @Test
    fun titleKeyIgnoresPunctuationAndCase() {
        assertEquals(TitleScore.key("Young Justice Bao"), TitleScore.key("young.justice.bao"))
        assertTrue(TitleScore.key("Young Justice Bao").isNotEmpty())
    }

    @Test
    fun nonLatinTitleNeedsLocalizedSearch() {
        assertTrue(TitleScore.needsLocalizedSearch("潘神的迷宫"))
        assertTrue(TitleScore.needsLocalizedSearch("進撃の巨人"))
        assertFalse(TitleScore.needsLocalizedSearch("Pan's Labyrinth"))
    }

    @Test
    fun differentYearDropsBelowAutoMatch() {
        val score = TitleScore.of("The Matrix", 1999, "The Matrix", "The Matrix", 2003)
        assertTrue(score < 0.72)
    }

    @Test
    fun sequelTitleDoesNotExactMatchFranchiseRoot() {
        assertTrue(TitleScore.key("John Wick") != TitleScore.key("John Wick Chapter 3 Parabellum"))
        val againstFirst = TitleScore.of(
            "John Wick Chapter 3 Parabellum",
            2019,
            "John Wick",
            "John Wick",
            2014,
        )
        assertTrue(againstFirst < 0.72)
        val againstThird = TitleScore.of(
            "John Wick Chapter 3 Parabellum",
            2019,
            "John Wick: Chapter 3 - Parabellum",
            "John Wick: Chapter 3 - Parabellum",
            2019,
        )
        assertTrue(againstThird >= 0.72)
    }
}
