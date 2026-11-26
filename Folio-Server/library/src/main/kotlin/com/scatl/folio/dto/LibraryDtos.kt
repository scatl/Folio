package com.scatl.folio.dto

import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.NotNull
import jakarta.validation.constraints.Positive
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate

data class FileAccepted(val id: Long, val status: String)

data class TranslationView(val locale: String, val title: String, val overview: String?, val tagline: String? = null)

data class WorkSummary(
    val id: Long,
    val kind: String,
    val originalTitle: String,
    val year: Int?,
    val sourceProvider: String,
    val translations: List<TranslationView>,
)

data class CollectionCard(
    val id: String,
    val name: String,
    val posterUrl: String?,
    val count: Int,
)

data class CollectionPartView(
    val tmdbId: String,
    val title: String,
    val originalTitle: String?,
    val overview: String?,
    val year: Int?,
    val releaseDate: String?,
    val posterUrl: String?,
    val backdropUrl: String?,
    val workId: Long?,
    /** 是否有本地视频文件（与是否已有元数据行无关）。 */
    val hasLocalMedia: Boolean = false,
    val rating: BigDecimal? = null,
    val voteCount: Int? = null,
    val genres: List<String> = emptyList(),
    val originalLanguage: String? = null,
)

data class CollectionView(
    val id: String,
    val name: String,
    val overview: String?,
    val posterUrl: String?,
    val backdropUrl: String?,
    val parts: List<CollectionPartView>,
    val localCount: Int,
)

data class WorkCard(
    val id: Long,
    val kind: String,
    val originalTitle: String,
    val title: String,
    val year: Int?,
    val posterUrl: String?,
    val backdropUrl: String?,
    val rating: BigDecimal?,
    val voteCount: Int?,
    val genres: List<String>,
    val popularity: BigDecimal?,
    val overview: String?,
    val watchState: String? = null,
)

data class FacetOption(
    val id: String,
    val label: String,
    val count: Int,
)

data class WorkFacets(
    val genres: List<FacetOption>,
    val countries: List<FacetOption>,
    val languages: List<FacetOption>,
    val keywords: List<FacetOption>,
    val companies: List<FacetOption>,
    val collections: List<FacetOption>,
    val videoCodecs: List<String>,
    val dynamicRanges: List<String>,
    val audioCodecs: List<String>,
    val yearMin: Int?,
    val yearMax: Int?,
    val people: List<FacetOption>,
)

/** 海报墙筛选。字段由查询参数绑定，缺省表示不限。 */
class WorkBrowseQuery {
    var kind: String? = null
    var libraryId: Long? = null
    var q: String? = null
    var page: Int = 0
    var size: Int = 48
    var sort: String? = null
    var watch: String? = null
    /** 多选时用逗号分隔，作品命中其中任意一项即可。 */
    var genreId: String? = null
    var yearFrom: Int? = null
    var yearTo: Int? = null
    var ratingProvider: String? = null
    var ratingMin: Double? = null
    var country: String? = null
    var language: String? = null
    var runtime: String? = null
    var keywordId: String? = null
    var personId: Long? = null
    var companyId: String? = null
    var collectionId: String? = null
    var inCollection: Boolean? = null
    var showStatus: String? = null
    var resolution: String? = null
    var dynamicRange: String? = null
    var videoCodec: String? = null
    var audioCodec: String? = null
    var subtitle: String? = null
    var personQ: String? = null
}

data class PageResult<T>(
    val items: List<T>,
    val page: Int,
    val size: Int,
    val total: Long,
    val totalPages: Int,
)

data class FileView(
    val id: Long,
    val fileName: String,
    val locator: String,
    val status: String,
    val parsedTitle: String?,
    val parsedYear: Int?,
    val parsedSeason: Int?,
    val parsedEpisode: Int?,
    val parsedImdbId: String?,
    val confidence: BigDecimal?,
    val message: String?,
    val workId: Long?,
    val episodeId: Long?,
    val work: WorkSummary?,
)

data class AudioTrackView(
    val codec: String?,
    val channels: Int?,
    val language: String?,
    val bitrate: Long?,
    val sampleRate: Int? = null,
    val channelLayout: String? = null,
    val profile: String? = null,
)

data class SubtitleTrackView(
    val codec: String?,
    val language: String?,
)

data class EmbeddedSubtitleView(
    val index: Int,
    val codec: String?,
    val language: String?,
    val title: String?,
)

data class ReviewFileRow(
    val id: Long,
    val fileName: String,
    val locator: String,
    val status: String,
    val parsedTitle: String?,
    val parsedYear: Int?,
    val parsedSeason: Int?,
    val parsedEpisode: Int?,
    val confidence: BigDecimal?,
    val message: String?,
    val fileSize: Long? = null,
    val sourceModifiedAt: Instant? = null,
    val container: String? = null,
    val durationMs: Long? = null,
    val videoCodec: String? = null,
    val videoWidth: Int? = null,
    val videoHeight: Int? = null,
    val videoFrameRate: Double? = null,
    val videoBitrate: Long? = null,
    val videoBitDepth: Int? = null,
    val videoDynamicRange: String? = null,
    val videoProfile: String? = null,
    val videoPixelFormat: String? = null,
    val audioTracks: List<AudioTrackView> = emptyList(),
    val subtitleTracks: List<SubtitleTrackView> = emptyList(),
)

data class MatchCandidateView(
    val provider: String,
    val kind: String,
    val externalId: String,
    val title: String?,
    val originalTitle: String?,
    val year: Int?,
    val overview: String?,
    val posterUrl: String?,
    val score: Double,
)

data class ManualMatchRequest(
    @field:NotBlank(message = "不能为空")
    val kind: String,
    @field:NotNull(message = "不能为空")
    @field:Positive(message = "必须为正数")
    val tmdbId: Long,
    val year: Int? = null,
    val season: Int? = null,
    val episode: Int? = null,
    /** `work`：把当前作品下的分集按各自文件名里的季、集改挂。空或 `file` 只改这一个文件。 */
    val scope: String? = null,
)

data class ManualMatchResult(
    val fileId: Long,
    val workId: Long?,
    val status: String,
)

data class ExternalIdView(val provider: String, val externalId: String, val logoUrl: String?)
data class RatingView(val provider: String, val value: BigDecimal, val votes: Int?, val scale: BigDecimal, val logoUrl: String?)
data class ArtworkView(val provider: String, val kind: String, val locale: String?, val remoteUrl: String)
data class CreditView(
    val provider: String,
    val externalId: String,
    val name: String,
    val profileUrl: String?,
    val department: String?,
    val job: String?,
    val character: String?,
    val order: Int,
)
data class PersonView(
    val provider: String,
    val externalId: String,
    val name: String,
    val profileUrl: String?,
    val images: List<ArtworkView>,
)

data class PersonWorkCreditView(
    val mediaType: String,
    val tmdbId: String,
    val title: String,
    val originalTitle: String?,
    val year: Int?,
    val releaseDate: String?,
    val posterUrl: String?,
    val character: String?,
    val job: String?,
    val department: String?,
    val workId: Long?,
    /** 是否有本地视频文件（与是否已有元数据行无关）。 */
    val hasLocalMedia: Boolean = false,
)

data class PersonDetailView(
    val provider: String,
    val externalId: String,
    val name: String,
    val biography: String?,
    val birthday: LocalDate?,
    val deathday: LocalDate?,
    val placeOfBirth: String?,
    val profileUrl: String?,
    val knownForDepartment: String?,
    val alsoKnownAs: List<String> = emptyList(),
    val credits: List<PersonWorkCreditView> = emptyList(),
    val localCount: Int = 0,
    val detailFetchedAt: Instant? = null,
)
data class EpisodeView(
    val id: Long,
    val episodeNumber: Int,
    val absoluteNumber: Int?,
    val title: String?,
    val overview: String?,
    val airDate: LocalDate?,
    val runtimeMinutes: Int?,
    val voteAverage: BigDecimal?,
    val voteCount: Int?,
    val artworks: List<ArtworkView>,
    val files: List<ReviewFileRow> = emptyList(),
)
data class SeasonView(
    val id: Long,
    val seasonNumber: Int,
    val name: String?,
    val episodeCount: Int?,
    val localEpisodeCount: Int,
    val airDate: LocalDate?,
    val overview: String?,
    val artworks: List<ArtworkView>,
    val episodes: List<EpisodeView>,
)

data class SeasonDetailView(
    val workId: Long,
    val workKind: String,
    val workTitle: String,
    val originalTitle: String,
    val season: SeasonView,
)

data class EpisodeDetailView(
    val workId: Long,
    val workKind: String,
    val workTitle: String,
    val originalTitle: String,
    val seasonNumber: Int,
    val seasonName: String?,
    val episode: EpisodeView,
    val productionCode: String? = null,
    val credits: List<CreditView> = emptyList(),
    val externalIds: List<ExternalIdView> = emptyList(),
    val videos: List<VideoView> = emptyList(),
)
data class NameView(val externalId: String, val name: String)
data class CompanyView(
    val externalId: String,
    val name: String,
    val originCountry: String?,
    val logoUrl: String?,
    val role: String,
)
data class CountryView(val code: String, val name: String?, val kind: String)
data class LanguageView(val code: String, val name: String?)
data class VideoView(
    val externalId: String,
    val site: String?,
    val type: String?,
    val name: String?,
    val key: String?,
    val language: String?,
    val official: Boolean?,
)
data class WorkView(
    val id: Long,
    val kind: String,
    val originalTitle: String,
    val originalLanguage: String?,
    val year: Int?,
    val premiereDate: LocalDate?,
    val runtimeMinutes: Int?,
    val status: String?,
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
    val awards: String?,
    val sourceProvider: String,
    val translations: List<TranslationView>,
    val externalIds: List<ExternalIdView>,
    val ratings: List<RatingView>,
    val artworks: List<ArtworkView>,
    val credits: List<CreditView>,
    val people: List<PersonView>,
    val genres: List<NameView>,
    val companies: List<CompanyView>,
    val countries: List<CountryView>,
    val spokenLanguages: List<LanguageView>,
    val keywords: List<NameView>,
    val videos: List<VideoView>,
    val seasons: List<SeasonView>,
    val libraryFiles: List<ReviewFileRow>,
)

data class VideoDetail(
    val id: Long,
    val fileName: String,
    val locator: String,
    val status: String,
    val parsedTitle: String?,
    val parsedYear: Int?,
    val parsedSeason: Int?,
    val parsedEpisode: Int?,
    val parsedImdbId: String?,
    val confidence: BigDecimal?,
    val message: String?,
    val episodeId: Long?,
    val work: WorkView?,
)

