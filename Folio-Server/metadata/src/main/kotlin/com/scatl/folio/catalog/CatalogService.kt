package com.scatl.folio.catalog

import com.scatl.folio.entity.Artwork
import com.scatl.folio.repository.ArtworkRepository
import com.scatl.folio.entity.Company
import com.scatl.folio.repository.CompanyRepository
import com.scatl.folio.entity.Credit
import com.scatl.folio.repository.CreditRepository
import com.scatl.folio.entity.Episode
import com.scatl.folio.repository.EpisodeRepository
import com.scatl.folio.entity.ExternalId
import com.scatl.folio.repository.ExternalIdRepository
import com.scatl.folio.entity.Genre
import com.scatl.folio.repository.GenreRepository
import com.scatl.folio.entity.Keyword
import com.scatl.folio.repository.KeywordRepository
import com.scatl.folio.entity.Person
import com.scatl.folio.repository.PersonRepository
import com.scatl.folio.entity.ProviderSnapshot
import com.scatl.folio.repository.ProviderSnapshotRepository
import com.scatl.folio.entity.Rating
import com.scatl.folio.repository.RatingRepository
import com.scatl.folio.entity.Season
import com.scatl.folio.repository.SeasonRepository
import com.scatl.folio.entity.Video
import com.scatl.folio.repository.VideoRepository
import com.scatl.folio.entity.Work
import com.scatl.folio.entity.WorkCompany
import com.scatl.folio.repository.WorkCompanyRepository
import com.scatl.folio.entity.WorkCountry
import com.scatl.folio.repository.WorkCountryRepository
import com.scatl.folio.entity.WorkGenre
import com.scatl.folio.repository.WorkGenreRepository
import com.scatl.folio.entity.WorkKeyword
import com.scatl.folio.repository.WorkKeywordRepository
import com.scatl.folio.entity.WorkLanguage
import com.scatl.folio.repository.WorkLanguageRepository
import com.scatl.folio.repository.WorkRepository
import com.scatl.folio.entity.WorkTranslation
import com.scatl.folio.repository.WorkTranslationRepository
import com.scatl.folio.parse.TitleScore
import com.scatl.folio.provider.CanonicalWork
import com.scatl.folio.provider.SeriesEnrichment
import org.springframework.dao.DataIntegrityViolationException
import org.springframework.stereotype.Service
import org.springframework.transaction.support.TransactionTemplate
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.Instant
import java.time.LocalDate
import java.util.concurrent.locks.ReentrantLock

@Service
open class CatalogService(
    private val works: WorkRepository,
    private val translations: WorkTranslationRepository,
    private val seasons: SeasonRepository,
    private val episodes: EpisodeRepository,
    private val externalIds: ExternalIdRepository,
    private val people: PersonRepository,
    private val credits: CreditRepository,
    private val ratings: RatingRepository,
    private val artworks: ArtworkRepository,
    private val snapshots: ProviderSnapshotRepository,
    private val genres: GenreRepository,
    private val workGenres: WorkGenreRepository,
    private val companies: CompanyRepository,
    private val workCompanies: WorkCompanyRepository,
    private val workCountries: WorkCountryRepository,
    private val workLanguages: WorkLanguageRepository,
    private val keywords: KeywordRepository,
    private val workKeywords: WorkKeywordRepository,
    private val videos: VideoRepository,
    private val transactions: TransactionTemplate,
) {
    /** 串行化目录落库，避免并发写 credits/people 触发 InnoDB 死锁。 */
    private val writeLock = ReentrantLock(true)

    /**
     * 电影已经在目录里时返回作品编号，供自动刮削跳过 TMDB。
     * 文件名里的 IMDb 编号能对上一部电影时直接用它。编号指向的不是电影时不沿用。
     * 编号不在库里时，再要求原名或译名完全一致、年份不冲突，并且只能确定一部。
     */
    fun findKnownMovie(title: String?, year: Int?, imdbId: String?): Long? {
        if (!imdbId.isNullOrBlank()) {
            val ownerId = externalIds.findByOwnerTypeAndProviderAndExternalId(
                OwnerType.work,
                ExternalProvider.imdb,
                imdbId,
            ).orElse(null)?.ownerId
            if (ownerId != null) {
                val work = works.findById(ownerId).orElse(null)
                return if (work?.kind == WorkKind.movie) work.id else null
            }
        }
        val key = TitleScore.key(title)
        if (key.isEmpty()) return null
        val movies = works.findByKind(WorkKind.movie)
        if (movies.isEmpty()) return null
        val titlesByWork = translations.findByWorkIdIn(movies.mapNotNull { it.id }).groupBy { it.workId }
        val matches = movies.filter { work ->
            val workId = work.id ?: return@filter false
            val titles = listOf(work.originalTitle) + titlesByWork[workId].orEmpty().map { it.title }
            titles.any { TitleScore.key(it) == key } &&
                (work.releaseYear == null || year == null || work.releaseYear == year)
        }
        if (year != null) {
            val exactYear = matches.filter { it.releaseYear == year }
            if (exactYear.size == 1) return exactYear.first().id
            if (exactYear.size > 1) return null
        }
        return matches.singleOrNull()?.id
    }

    /** 这部剧的这一集已经入库时返回引用。剧还不存在，或这一集还没有写入时返回 null。 */
    fun findSavedEpisode(provider: ExternalProvider, externalId: String, seasonNumber: Int, episodeNumber: Int): SavedRef? {
        val workId = externalIds.findByOwnerTypeAndProviderAndExternalId(OwnerType.work, provider, externalId)
            .orElse(null)
            ?.ownerId
            ?: return null
        val seasonId = seasons.findByWorkIdAndSeasonNumber(workId, seasonNumber).orElse(null)?.id ?: return null
        val episodeId = episodes.findBySeasonIdAndEpisodeNumber(seasonId, episodeNumber).orElse(null)?.id ?: return null
        return SavedRef(workId, episodeId)
    }

    fun save(canonical: CanonicalWork, seasonNumber: Int?, episodeNumber: Int?): SavedRef {
        writeLock.lock()
        try {
            return requireNotNull(transactions.execute { saveInTx(canonical, seasonNumber, episodeNumber) })
        } finally {
            writeLock.unlock()
        }
    }

    fun applyRatings(workId: Long, incoming: List<CanonicalWork.RatingValue>) {
        applyOmdb(workId, incoming, awards = null)
    }

    fun applyOmdb(workId: Long, incoming: List<CanonicalWork.RatingValue>, awards: String?, tomatoUrl: String? = null) {
        if (incoming.isEmpty() && awards == null && tomatoUrl.isNullOrBlank()) return
        writeLock.lock()
        try {
            transactions.executeWithoutResult {
                incoming.forEach { upsertRating(OwnerType.work, workId, it) }
                if (!tomatoUrl.isNullOrBlank()) {
                    rememberExternalId(OwnerType.work, workId, ExternalProvider.rottentomatoes, tomatoUrl.trim())
                }
                if (awards != null) {
                    val work = works.findById(workId).orElse(null) ?: return@executeWithoutResult
                    work.awards = awards
                    work.updatedAt = Instant.now()
                }
            }
        } finally {
            writeLock.unlock()
        }
    }

    fun applySupplement(workId: Long, enrichment: SeriesEnrichment) {
        if (enrichment.isEmpty()) return
        writeLock.lock()
        try {
            transactions.executeWithoutResult { applySupplementInTx(workId, enrichment) }
        } finally {
            writeLock.unlock()
        }
    }

    private fun saveInTx(canonical: CanonicalWork, seasonNumber: Int?, episodeNumber: Int?): SavedRef {
        val source = canonical.externalIds.firstOrNull { it.provider == canonical.sourceProvider }
            ?: throw IllegalStateException("外部编号缺失")
        val now = Instant.now()
        val existingId = externalIds.findByOwnerTypeAndProviderAndExternalId(OwnerType.work, source.provider, source.externalId)
            .orElse(null)?.ownerId
        val work = existingId?.let { works.findById(it).orElse(null) } ?: Work()
        val isNew = work.id == null
        if (isNew) {
            work.createdAt = now
        }
        work.kind = WorkKind.valueOf(canonical.kind)
        work.originalTitle = limit(canonical.originalTitle?.takeIf { it.isNotBlank() } ?: "未命名", 512)!!
        work.originalLanguage = canonical.originalLanguage
        work.releaseYear = canonical.year
        work.premiereDate = canonical.premiereDate
        work.runtimeMinutes = canonical.runtimeMinutes
        work.workStatus = canonical.status
        work.homepage = limit(canonical.homepage, 1024)
        work.popularity = canonical.popularity
        work.budget = canonical.budget
        work.revenue = canonical.revenue
        work.adult = canonical.adult
        work.showType = limit(canonical.showType, 64)
        work.inProduction = canonical.inProduction
        work.lastAirDate = canonical.lastAirDate
        work.numberOfSeasons = canonical.numberOfSeasons
        work.numberOfEpisodes = canonical.numberOfEpisodes
        work.collectionExternalId = canonical.collectionExternalId
        work.collectionName = limit(canonical.collectionName, 512)
        work.sourceProvider = canonical.sourceProvider
        work.updatedAt = now
        val saved = works.saveAndFlush(work)
        val workId = requireNotNull(saved.id)

        canonical.externalIds.forEach { rememberExternalId(OwnerType.work, workId, it.provider, it.externalId) }
        canonical.translations.forEach { upsertTranslation(workId, it, overwrite = true) }
        canonical.ratings.forEach { upsertRating(OwnerType.work, workId, it) }
        canonical.artworks.forEach { rememberArtwork(OwnerType.work, workId, it) }
        replaceCredits(OwnerType.work, workId, source.provider, canonical.credits)
        replacePersonImages(source.provider, canonical.personImages)
        replaceGenres(workId, source.provider, canonical.genres)
        replaceCompanies(workId, source.provider, canonical.companies)
        replaceCountries(workId, canonical.countries)
        replaceLanguages(workId, canonical.spokenLanguages)
        replaceKeywords(workId, source.provider, canonical.keywords)
        replaceVideos(workId, source.provider, canonical.videos)
        canonical.seasons.forEach {
            val season = upsertSeason(workId, it.seasonNumber, it.name, it.episodeCount, it.airDate, it.overview)
            rememberSeasonPoster(season, it.posterUrl, source.provider)
        }

        var episodeId: Long? = null
        canonical.fetchedSeasons.forEach { detail ->
            val season = upsertSeason(
                workId,
                detail.seasonNumber,
                detail.name,
                detail.episodeCount,
                detail.airDate,
                detail.overview,
            )
            rememberSeasonPoster(season, detail.posterUrl, source.provider)
            for (item in detail.episodes) {
                val episode = upsertEpisode(workId, season, item)
                replaceEpisodeStills(requireNotNull(episode.id), source.provider, item.stills)
                if (episodeNumber != null && seasonNumber == detail.seasonNumber && item.episodeNumber == episodeNumber) {
                    episodeId = episode.id
                }
            }
        }
        if (episodeId == null && seasonNumber != null && episodeNumber != null) {
            episodeId = seasons.findByWorkIdAndSeasonNumber(workId, seasonNumber).orElse(null)?.id?.let { seasonId ->
                episodes.findBySeasonIdAndEpisodeNumber(seasonId, episodeNumber).orElse(null)?.id
            }
        }
        rememberSnapshot(source.provider, canonical.snapshotKey, canonical.snapshotBody, now)
        return SavedRef(workId, episodeId)
    }

    private fun applySupplementInTx(workId: Long, enrichment: SeriesEnrichment) {
        enrichment.translations.forEach { upsertTranslation(workId, it, overwrite = false) }
        enrichment.externalIds.forEach { rememberExternalId(OwnerType.work, workId, it.provider, it.externalId) }
        enrichment.ratings.forEach { upsertRating(OwnerType.work, workId, it) }
        enrichment.artworks.forEach { rememberArtwork(OwnerType.work, workId, it) }
        for (patch in enrichment.episodes) {
            val seasonId = seasons.findByWorkIdAndSeasonNumber(workId, patch.seasonNumber).orElse(null)?.id ?: continue
            val episode = episodes.findBySeasonIdAndEpisodeNumber(seasonId, patch.episodeNumber).orElse(null) ?: continue
            fillEpisode(episode, patch)
        }
        rememberSnapshot(ExternalProvider.tvdb, enrichment.snapshotKey, enrichment.snapshotBody, Instant.now())
    }

    private fun upsertTranslation(workId: Long, incoming: CanonicalWork.Translation, overwrite: Boolean) {
        if (incoming.title.isNullOrBlank()) return
        val existing = translations.findByWorkIdAndLocale(workId, incoming.locale).orElse(null)
        if (existing == null) {
            translations.save(WorkTranslation().apply {
                this.workId = workId
                locale = incoming.locale
                title = limit(incoming.title, 512)!!
                overview = incoming.overview
                tagline = limit(incoming.tagline, 1024)
            })
            return
        }
        if (overwrite || existing.title.isBlank()) {
            existing.title = limit(incoming.title, 512)!!
        }
        if (overwrite || existing.overview.isNullOrBlank()) {
            existing.overview = incoming.overview
        }
        if (overwrite || existing.tagline.isNullOrBlank()) {
            existing.tagline = limit(incoming.tagline, 1024)
        }
    }

    private fun upsertRating(ownerType: OwnerType, ownerId: Long, incoming: CanonicalWork.RatingValue) {
        val value = incoming.value.setScale(2, RoundingMode.HALF_UP)
        val scale = incoming.scale.setScale(2, RoundingMode.HALF_UP)
        val existing = ratings.findByOwnerTypeAndOwnerIdAndProvider(ownerType, ownerId, incoming.provider).orElse(null)
        if (existing == null) {
            ratings.save(Rating().apply {
                this.ownerType = ownerType
                this.ownerId = ownerId
                provider = incoming.provider
                scoreValue = value
                votes = incoming.votes
                scoreScale = scale
            })
        } else {
            existing.scoreValue = value
            existing.votes = incoming.votes
            existing.scoreScale = scale
        }
    }

    private fun upsertSeason(
        workId: Long,
        seasonNumber: Int,
        name: String?,
        episodeCount: Int?,
        airDate: LocalDate?,
        overview: String?,
    ): Season {
        val season = seasons.findByWorkIdAndSeasonNumber(workId, seasonNumber).orElse(null)
            ?: seasons.save(Season().apply {
                this.workId = workId
                this.seasonNumber = seasonNumber
            })
        if (name != null) season.name = limit(name, 512)
        if (episodeCount != null) season.episodeCount = episodeCount
        if (airDate != null) season.airDate = airDate
        if (overview != null) season.overview = overview
        return season
    }

    private fun upsertEpisode(workId: Long, season: Season, item: CanonicalWork.EpisodeDetail): Episode {
        val seasonId = requireNotNull(season.id)
        val episode = episodes.findBySeasonIdAndEpisodeNumber(seasonId, item.episodeNumber).orElse(null)
            ?: episodes.save(Episode().apply {
                this.workId = workId
                this.seasonId = seasonId
                episodeNumber = item.episodeNumber
            })
        episode.title = limit(item.title, 512)
        episode.overview = item.overview
        episode.airDate = item.airDate
        episode.runtimeMinutes = item.runtimeMinutes
        val voteAverage = item.voteAverage
        if (voteAverage != null) {
            episode.voteAverage = BigDecimal.valueOf(voteAverage).setScale(2, RoundingMode.HALF_UP)
        }
        episode.voteCount = item.voteCount
        if (item.absoluteNumber != null) episode.absoluteNumber = item.absoluteNumber
        return episode
    }

    private fun fillEpisode(episode: Episode, patch: SeriesEnrichment.EpisodePatch) {
        if (patch.absoluteNumber != null) episode.absoluteNumber = patch.absoluteNumber
        if (episode.title.isNullOrBlank() && patch.title != null) episode.title = limit(patch.title, 512)
        if (episode.overview.isNullOrBlank() && patch.overview != null) episode.overview = patch.overview
    }

    private fun replaceCredits(ownerType: OwnerType, ownerId: Long, provider: ExternalProvider, incoming: List<CanonicalWork.CreditRef>) {
        credits.deleteByOwnerAndProvider(ownerType, ownerId, provider)
        val ordered = incoming
            .filter { it.provider == provider }
            .sortedWith(compareBy({ it.personId }, { it.order }))
        for (ref in ordered) {
            val person = resolvePerson(provider, ref.personId, ref.name, ref.profileUrl)
            credits.save(Credit().apply {
                this.ownerType = ownerType
                this.ownerId = ownerId
                this.person = person
                department = ref.department
                jobName = limit(ref.job, 64)
                characterName = limit(ref.character, 512)
                sortOrder = ref.order
            })
        }
    }

    private fun resolvePerson(
        provider: ExternalProvider,
        personId: String,
        name: String?,
        profileUrl: String?,
    ): Person {
        val existing = people.findByProviderAndProviderPersonId(provider, personId).orElse(null)
        if (existing != null) {
            existing.name = limit(name, 512)!!
            if (!profileUrl.isNullOrBlank()) {
                existing.profileUrl = limit(profileUrl, 1024)
            }
            return existing
        }
        return try {
            people.saveAndFlush(
                Person().apply {
                    this.provider = provider
                    providerPersonId = personId
                    this.name = limit(name, 512)!!
                    if (!profileUrl.isNullOrBlank()) {
                        this.profileUrl = limit(profileUrl, 1024)
                    }
                },
            )
        } catch (ex: DataIntegrityViolationException) {
            people.findByProviderAndProviderPersonId(provider, personId).orElseThrow { ex }
        }
    }

    private fun rememberExternalId(ownerType: OwnerType, ownerId: Long, provider: ExternalProvider, externalId: String?) {
        if (externalId.isNullOrBlank()) return
        if (externalIds.findByOwnerTypeAndProviderAndExternalId(ownerType, provider, externalId).isPresent) return
        externalIds.save(ExternalId().apply {
            this.ownerType = ownerType
            this.ownerId = ownerId
            this.provider = provider
            this.externalId = externalId
        })
    }

    private fun rememberArtwork(ownerType: OwnerType, ownerId: Long, artwork: CanonicalWork.ArtworkRef) {
        if (artwork.remoteUrl.isBlank()) return
        if (artworks.existsByOwnerTypeAndOwnerIdAndProviderAndRemoteUrl(ownerType, ownerId, artwork.provider, artwork.remoteUrl)) return
        artworks.save(Artwork().apply {
            this.ownerType = ownerType
            this.ownerId = ownerId
            kind = artwork.kind
            locale = artwork.locale
            provider = artwork.provider
            remoteUrl = limit(artwork.remoteUrl, 1024)!!
        })
    }

    private fun replaceGenres(workId: Long, provider: ExternalProvider, incoming: List<CanonicalWork.NamedRef>) {
        workGenres.deleteByWorkId(workId)
        incoming.distinctBy { it.externalId }.forEach { ref ->
            val genre = genres.findByProviderAndExternalId(provider, ref.externalId).orElse(null)
                ?: genres.save(Genre().apply {
                    this.provider = provider
                    externalId = ref.externalId
                    name = limit(ref.name, 255)!!
                })
            genre.name = limit(ref.name, 255)!!
            workGenres.save(WorkGenre().apply {
                this.workId = workId
                genreId = requireNotNull(genre.id)
            })
        }
    }

    private fun replaceCompanies(workId: Long, provider: ExternalProvider, incoming: List<CanonicalWork.CompanyRef>) {
        workCompanies.deleteByWorkId(workId)
        incoming.distinctBy { it.externalId to it.role }.forEach { ref ->
            val company = companies.findByProviderAndExternalId(provider, ref.externalId).orElse(null)
                ?: companies.save(Company().apply {
                    this.provider = provider
                    externalId = ref.externalId
                    name = limit(ref.name, 512)!!
                })
            company.name = limit(ref.name, 512)!!
            company.originCountry = limit(ref.originCountry, 8)
            company.logoUrl = limit(ref.logoUrl, 1024)
            workCompanies.save(WorkCompany().apply {
                this.workId = workId
                companyId = requireNotNull(company.id)
                companyRole = ref.role
            })
        }
    }

    private fun replaceCountries(workId: Long, incoming: List<CanonicalWork.CountryRef>) {
        workCountries.deleteByWorkId(workId)
        incoming.forEach { ref ->
            workCountries.save(WorkCountry().apply {
                this.workId = workId
                countryCode = limit(ref.code, 8)!!
                name = limit(ref.name, 255)
                countryKind = ref.kind
            })
        }
    }

    private fun replaceLanguages(workId: Long, incoming: List<CanonicalWork.LanguageRef>) {
        workLanguages.deleteByWorkId(workId)
        incoming.distinctBy { it.code }.forEach { ref ->
            workLanguages.save(WorkLanguage().apply {
                this.workId = workId
                languageCode = limit(ref.code, 16)!!
                name = limit(ref.name, 255)
            })
        }
    }

    private fun replaceKeywords(workId: Long, provider: ExternalProvider, incoming: List<CanonicalWork.NamedRef>) {
        workKeywords.deleteByWorkId(workId)
        incoming.distinctBy { it.externalId }.forEach { ref ->
            val keyword = keywords.findByProviderAndExternalId(provider, ref.externalId).orElse(null)
                ?: keywords.save(Keyword().apply {
                    this.provider = provider
                    externalId = ref.externalId
                    name = limit(ref.name, 255)!!
                })
            keyword.name = limit(ref.name, 255)!!
            workKeywords.save(WorkKeyword().apply {
                this.workId = workId
                keywordId = requireNotNull(keyword.id)
            })
        }
    }

    private fun replaceVideos(workId: Long, provider: ExternalProvider, incoming: List<CanonicalWork.VideoRef>) {
        videos.deleteByOwnerAndProvider(OwnerType.work, workId, provider)
        incoming.distinctBy { it.externalId }.forEach { ref ->
            videos.save(Video().apply {
                ownerType = OwnerType.work
                ownerId = workId
                this.provider = provider
                externalId = limit(ref.externalId, 64)!!
                site = limit(ref.site, 64)
                videoType = limit(ref.type, 64)
                name = limit(ref.name, 512)
                videoKey = limit(ref.key, 128)
                language = limit(ref.language, 16)
                official = ref.official
            })
        }
    }

    private fun rememberSeasonPoster(season: Season, posterUrl: String?, provider: ExternalProvider) {
        val seasonId = season.id ?: return
        if (posterUrl.isNullOrBlank()) return
        artworks.deleteByOwnerAndProvider(OwnerType.season, seasonId, provider)
        rememberArtwork(
            OwnerType.season,
            seasonId,
            CanonicalWork.ArtworkRef(provider, ArtworkKind.poster, null, posterUrl),
        )
    }

    private fun replaceEpisodeStills(episodeId: Long, provider: ExternalProvider, stills: List<CanonicalWork.ArtworkRef>) {
        artworks.deleteByOwnerAndProvider(OwnerType.episode, episodeId, provider)
        stills.distinctBy { it.remoteUrl }.forEach { rememberArtwork(OwnerType.episode, episodeId, it) }
    }

    private fun replacePersonImages(provider: ExternalProvider, incoming: List<CanonicalWork.PersonImages>) {
        incoming.forEach { set ->
            val person = people.findByProviderAndProviderPersonId(provider, set.personId).orElse(null) ?: return@forEach
            val personId = person.id ?: return@forEach
            artworks.deleteByOwnerAndProvider(OwnerType.person, personId, provider)
            set.images.distinctBy { it.remoteUrl }.forEach { rememberArtwork(OwnerType.person, personId, it) }
        }
    }

    private fun rememberStill(episodeId: Long, stillUrl: String?) {
        if (stillUrl == null) return
        rememberArtwork(
            OwnerType.episode,
            episodeId,
            CanonicalWork.ArtworkRef(ExternalProvider.tmdb, ArtworkKind.still, null, stillUrl),
        )
    }

    private fun rememberSnapshot(provider: ExternalProvider, key: String?, body: String?, fetchedAt: Instant) {
        if (key.isNullOrBlank() || body.isNullOrBlank()) return
        snapshots.save(ProviderSnapshot().apply {
            this.provider = provider
            resourceKey = limit(key, 255)!!
            this.body = limit(body, SNAPSHOT_LIMIT)!!
            this.fetchedAt = fetchedAt
        })
    }

    private fun limit(value: String?, max: Int): String? {
        if (value == null) return null
        return if (value.length <= max) value else value.substring(0, max)
    }

    companion object {
        private const val SNAPSHOT_LIMIT = 1_000_000
    }
}
