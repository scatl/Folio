package com.scatl.folio.provider

import com.scatl.folio.catalog.ExternalProvider
import com.scatl.folio.settings.FolioSettings
import org.slf4j.LoggerFactory
import org.springframework.stereotype.Component
import java.math.BigDecimal

@Component
class OmdbClient(
    private val appSettings: FolioSettings,
    private val providers: ProviderClients,
) {
    private val log = LoggerFactory.getLogger(javaClass)
    private val settings get() = appSettings.current()
    private val client get() = providers.omdb.client
    private val pacer get() = providers.omdb.pacer

    fun configured(): Boolean = settings.omdbConfigured()

    data class Payload(
        val ratings: List<CanonicalWork.RatingValue>,
        val awards: String,
        val tomatoUrl: String?,
    )

    fun enrich(imdbId: String): Payload? {
        if (!configured()) return null
        val id = imdbId.trim()
        if (id.isEmpty()) return null
        return try {
            val body = ProviderHttp.get(
                client,
                pacer,
                "omdb",
                uri = { builder ->
                    builder.queryParam("i", id)
                        .queryParam("apikey", settings.omdbApiKey)
                        .queryParam("tomatoes", "true")
                        .build()
                },
            )
            val root = JsonBodies.read("omdb", body)
            if (JsonBodies.text(root, "Response").equals("False", ignoreCase = true)) {
                log.info("OMDb 无结果 imdbId={}", id)
                return null
            }
            Payload(parseRatings(root), parseAwards(root), parseTomatoUrl(root))
        } catch (ex: RuntimeException) {
            log.warn("OMDb 拉取失败 imdbId={} reason={}", id, ex.message)
            null
        }
    }

    private fun parseAwards(root: Map<String, Any?>): String {
        val text = JsonBodies.text(root, "Awards")?.trim().orEmpty()
        return if (text.equals("N/A", ignoreCase = true)) "" else text.take(1024)
    }

    private fun parseTomatoUrl(root: Map<String, Any?>): String? =
        JsonBodies.text(root, "tomatoURL")?.trim()?.takeIf { it.startsWith("http://") || it.startsWith("https://") }

    private fun parseRatings(root: Map<String, Any?>): List<CanonicalWork.RatingValue> {
        val out = mutableListOf<CanonicalWork.RatingValue>()
        val votes = parseVotes(JsonBodies.text(root, "imdbVotes"))
        val imdbScore = parseScore(JsonBodies.text(root, "imdbRating"))
        if (imdbScore != null) {
            out += CanonicalWork.RatingValue(ExternalProvider.imdb, imdbScore, votes, BigDecimal.TEN)
        }
        var rotten: BigDecimal? = parsePercent(JsonBodies.text(root, "tomatoMeter"))
        var metascore: BigDecimal? = parseScore(JsonBodies.text(root, "Metascore"))
        for (item in JsonBodies.maps(root["Ratings"])) {
            val source = JsonBodies.text(item, "Source").orEmpty()
            val value = JsonBodies.text(item, "Value")
            when {
                source.contains("Internet Movie Database", ignoreCase = true) && imdbScore == null -> {
                    parseScore(value?.substringBefore("/"))?.let {
                        out += CanonicalWork.RatingValue(ExternalProvider.imdb, it, votes, BigDecimal.TEN)
                    }
                }
                source.contains("Rotten Tomatoes", ignoreCase = true) -> {
                    rotten = parsePercent(value) ?: rotten
                }
                source.contains("Metacritic", ignoreCase = true) -> {
                    metascore = parseScore(value?.substringBefore("/")) ?: metascore
                }
            }
        }
        if (rotten != null) {
            out += CanonicalWork.RatingValue(
                ExternalProvider.rottentomatoes,
                rotten,
                parseVotes(JsonBodies.text(root, "tomatoReviews")),
                BigDecimal.valueOf(100),
            )
        }
        val audience = parsePercent(JsonBodies.text(root, "tomatoUserMeter"))
        if (audience != null) {
            out += CanonicalWork.RatingValue(
                ExternalProvider.rt_audience,
                audience,
                parseVotes(JsonBodies.text(root, "tomatoUserReviews")),
                BigDecimal.valueOf(100),
            )
        }
        if (metascore != null) {
            out += CanonicalWork.RatingValue(
                ExternalProvider.metacritic,
                metascore,
                null,
                BigDecimal.valueOf(100),
            )
        }
        return out
    }

    private fun parseScore(raw: String?): BigDecimal? {
        val text = raw?.trim()?.takeIf { it.isNotEmpty() && !it.equals("N/A", ignoreCase = true) } ?: return null
        return text.toBigDecimalOrNull()
    }

    private fun parsePercent(raw: String?): BigDecimal? {
        val text = raw?.trim()?.removeSuffix("%")?.takeIf { it.isNotEmpty() && !it.equals("N/A", ignoreCase = true) }
            ?: return null
        return text.toBigDecimalOrNull()
    }

    private fun parseVotes(raw: String?): Int? =
        raw?.replace(",", "")?.trim()?.takeIf { it.isNotEmpty() && !it.equals("N/A", ignoreCase = true) }?.toIntOrNull()
}
