package com.scatl.folio.parse

import io.guessit.GuessResult
import io.guessit.Guessit
import io.guessit.OptionsBuilder
import org.springframework.stereotype.Component

@Component
class FilenameParser {
    fun parse(fileName: String?): ParsedName {
        if (fileName.isNullOrBlank()) {
            return ParsedName(null, null, null, null, null)
        }
        val imdbId = IMDB.find(fileName)?.let { "tt" + it.groupValues[1] }
        val input = if (imdbId == null) fileName else IMDB.replace(fileName, " ")
        val guessed = resolveGuess(input)
        val year = guessed.year()
        val title = firstNonBlank(guessed.title(), guessed.filmTitle())
            ?: year?.toString()
        val season = guessed.season() ?: guessed.seasonList()?.firstOrNull()
        val episode = guessed.episode() ?: guessed.episodeList()?.firstOrNull()
        return ParsedName(title, year, season, episode, imdbId)
    }

    /**
     * guessit 会把 `Chapter.3` 收成 episode=3、标题截成系列根名并丢掉年份
     *（例如 John.Wick.Chapter.3.Parabellum.2019 → title=John Wick, episode=3, year=null）。
     * 没有季号的「裸集数」对电影不可信，再按 type=movie 解析一次。
     */
    private fun resolveGuess(input: String): GuessResult {
        val guessed = Guessit.parse(input)
        val season = guessed.season() ?: guessed.seasonList()?.firstOrNull()
        val episode = guessed.episode() ?: guessed.episodeList()?.firstOrNull()
        if (season != null || episode == null) {
            return guessed
        }
        val asMovie = Guessit.parse(input, OptionsBuilder.options().type("movie").build())
        val movieSeason = asMovie.season() ?: asMovie.seasonList()?.firstOrNull()
        val movieEpisode = asMovie.episode() ?: asMovie.episodeList()?.firstOrNull()
        return if (movieSeason == null && movieEpisode == null) asMovie else guessed
    }

    private fun firstNonBlank(first: String?, second: String?): String? {
        val a = first?.trim()?.takeIf { it.isNotEmpty() }
        if (a != null) return a
        return second?.trim()?.takeIf { it.isNotEmpty() }
    }

    private companion object {
        val IMDB = Regex("(?i)(?<![a-z0-9])tt(\\d{5,9})(?!\\d)")
    }
}
