package com.scatl.folio.util

import com.scatl.folio.catalog.ExternalProvider

object ProviderLogos {
    private const val BASE = "/assets/providers"

    /** Official brand assets under classpath:/static/assets/providers (see SOURCES.txt). */
    private val files: Map<ExternalProvider, String?> =
        mapOf(
            ExternalProvider.tmdb to "$BASE/tmdb.svg",
            ExternalProvider.tvdb to "$BASE/tvdb.png",
            ExternalProvider.imdb to "$BASE/imdb.svg",
            ExternalProvider.rottentomatoes to "$BASE/rt.svg",
            ExternalProvider.rt_audience to "$BASE/rt-audience.svg",
            ExternalProvider.metacritic to "$BASE/metacritic.svg",
            ExternalProvider.wikidata to "$BASE/wikidata.svg",
            ExternalProvider.facebook to "$BASE/facebook.svg",
            ExternalProvider.instagram to "$BASE/instagram.svg",
            ExternalProvider.twitter to "$BASE/twitter.svg",
            ExternalProvider.tvrage to null, // site defunct; no redistributable official mark found
            ExternalProvider.freebase to "$BASE/freebase.svg",
        )

    fun url(provider: ExternalProvider): String? = files[provider]

    fun url(provider: String): String? {
        val key = provider.trim().lowercase()
        return ExternalProvider.entries.firstOrNull { it.name == key }?.let(::url)
    }
}
