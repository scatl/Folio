package com.scatl.folio.provider

import com.scatl.folio.catalog.ArtworkKind
import com.scatl.folio.catalog.ExternalProvider
import java.math.BigDecimal
import java.time.LocalDate

data class MediaHit(
    val kind: String,
    val id: Long,
    val title: String?,
    val originalTitle: String?,
    val year: Int?,
    val seasonNumber: Int?,
    val episodeNumber: Int?,
)

data class SearchCandidate(
    val kind: String,
    val id: Long,
    val title: String?,
    val originalTitle: String?,
    val year: Int?,
    val overview: String?,
    val posterUrl: String?,
)

data class TmdbCollection(
    val id: Long,
    val name: String,
    val overview: String?,
    val posterUrl: String?,
    val backdropUrl: String?,
    val parts: List<Part>,
) {
    data class Part(
        val id: Long,
        val title: String?,
        val originalTitle: String?,
        val overview: String?,
        val releaseDate: LocalDate?,
        val posterUrl: String?,
        val backdropUrl: String?,
        val originalLanguage: String? = null,
        val voteAverage: BigDecimal? = null,
        val voteCount: Int? = null,
        val genreIds: List<Int> = emptyList(),
    )
}

data class TmdbEpisodeDetail(
    val productionCode: String?,
    val credits: List<CanonicalWork.CreditRef>,
    val stills: List<CanonicalWork.ArtworkRef>,
    val videos: List<CanonicalWork.VideoRef>,
    val externalIds: List<CanonicalWork.ExternalRef>,
)

data class TmdbPerson(
    val id: Long,
    val name: String,
    val biography: String?,
    val birthday: LocalDate?,
    val deathday: LocalDate?,
    val placeOfBirth: String?,
    val profileUrl: String?,
    val knownForDepartment: String?,
    val alsoKnownAs: List<String>,
)

data class TmdbPersonCredit(
    val mediaType: String,
    val id: Long,
    val title: String?,
    val originalTitle: String?,
    val year: Int?,
    val releaseDate: LocalDate?,
    val posterUrl: String?,
    val character: String?,
    val job: String?,
    val department: String?,
)

data class CanonicalWork(
    val sourceProvider: ExternalProvider,
    val kind: String,
    val originalTitle: String?,
    val originalLanguage: String?,
    val year: Int?,
    val premiereDate: LocalDate?,
    val runtimeMinutes: Int?,
    val status: String?,
    val snapshotKey: String?,
    val snapshotBody: String?,
    val translations: List<Translation>,
    val externalIds: List<ExternalRef>,
    val ratings: List<RatingValue>,
    val artworks: List<ArtworkRef>,
    val credits: List<CreditRef>,
    val seasons: List<SeasonShell>,
    val fetchedSeasons: List<SeasonDetail>,
    val homepage: String?,
    val popularity: BigDecimal?,
    val budget: Long?,
    val revenue: Long?,
    val adult: Boolean?,
    val showType: String?,
    val inProduction: Boolean?,
    val lastAirDate: LocalDate?,
    val numberOfSeasons: Int?,
    val numberOfEpisodes: Int?,
    val collectionExternalId: String?,
    val collectionName: String?,
    val genres: List<NamedRef>,
    val companies: List<CompanyRef>,
    val countries: List<CountryRef>,
    val spokenLanguages: List<LanguageRef>,
    val keywords: List<NamedRef>,
    val videos: List<VideoRef>,
    val personImages: List<PersonImages>,
) {
    data class Translation(val locale: String, val title: String?, val overview: String?, val tagline: String?)
    data class ExternalRef(val provider: ExternalProvider, val externalId: String)
    data class RatingValue(val provider: ExternalProvider, val value: BigDecimal, val votes: Int?, val scale: BigDecimal)
    data class ArtworkRef(val provider: ExternalProvider, val kind: ArtworkKind, val locale: String?, val remoteUrl: String)
    data class CreditRef(
        val provider: ExternalProvider,
        val personId: String,
        val name: String,
        val department: String?,
        val job: String?,
        val character: String?,
        val order: Int,
        val profileUrl: String?,
    )
    data class PersonImages(val personId: String, val images: List<ArtworkRef>)
    data class SeasonShell(
        val seasonNumber: Int,
        val name: String?,
        val episodeCount: Int?,
        val airDate: LocalDate?,
        val overview: String?,
        val posterUrl: String?,
    )
    data class SeasonDetail(
        val seasonNumber: Int,
        val name: String?,
        val episodeCount: Int?,
        val airDate: LocalDate?,
        val overview: String?,
        val posterUrl: String?,
        val episodes: List<EpisodeDetail>,
    )
    data class EpisodeDetail(
        val episodeNumber: Int,
        val absoluteNumber: Int?,
        val title: String?,
        val overview: String?,
        val airDate: LocalDate?,
        val runtimeMinutes: Int?,
        val stills: List<ArtworkRef>,
        val voteAverage: Double?,
        val voteCount: Int?,
    )
    data class NamedRef(val externalId: String, val name: String)
    data class CompanyRef(
        val externalId: String,
        val name: String,
        val originCountry: String?,
        val logoUrl: String?,
        val role: String,
    )
    data class CountryRef(val code: String, val name: String?, val kind: String)
    data class LanguageRef(val code: String, val name: String?)
    data class VideoRef(
        val externalId: String,
        val site: String?,
        val type: String?,
        val name: String?,
        val key: String?,
        val language: String?,
        val official: Boolean?,
    )
}

data class SeriesEnrichment(
    val snapshotKey: String?,
    val snapshotBody: String?,
    val translations: List<CanonicalWork.Translation>,
    val externalIds: List<CanonicalWork.ExternalRef>,
    val ratings: List<CanonicalWork.RatingValue>,
    val artworks: List<CanonicalWork.ArtworkRef>,
    val episodes: List<EpisodePatch>,
) {
    data class EpisodePatch(
        val seasonNumber: Int,
        val episodeNumber: Int,
        val absoluteNumber: Int?,
        val title: String?,
        val overview: String?,
    )

    fun isEmpty(): Boolean =
        externalIds.isEmpty() && translations.isEmpty() && ratings.isEmpty() && artworks.isEmpty() && episodes.isEmpty()

    companion object {
        fun empty() = SeriesEnrichment(null, null, emptyList(), emptyList(), emptyList(), emptyList(), emptyList())

        fun rating(value: Double, votes: Int?) = CanonicalWork.RatingValue(
            ExternalProvider.tvdb,
            BigDecimal.valueOf(value),
            votes,
            BigDecimal.TEN,
        )

        fun artwork(kind: ArtworkKind, locale: String?, url: String) =
            CanonicalWork.ArtworkRef(ExternalProvider.tvdb, kind, locale, url)
    }
}
