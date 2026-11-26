package com.scatl.folio.library

import com.scatl.folio.auth.LibraryAccessService
import com.scatl.folio.util.DisplayLabels
import com.scatl.folio.util.ProviderLogos
import com.scatl.folio.util.TmdbImageUrls
import com.scatl.folio.catalog.ArtworkKind
import com.scatl.folio.catalog.CatalogService
import com.scatl.folio.catalog.OwnerType
import com.scatl.folio.catalog.WorkKind
import com.scatl.folio.dto.ArtworkView
import com.scatl.folio.catalog.ExternalProvider
import com.scatl.folio.dto.CollectionCard
import com.scatl.folio.dto.CollectionPartView
import com.scatl.folio.dto.CollectionView
import com.scatl.folio.dto.CompanyView
import com.scatl.folio.provider.ProviderException
import com.scatl.folio.provider.TmdbClient
import com.scatl.folio.provider.TmdbCollection
import com.scatl.folio.provider.TmdbEpisodeDetail
import com.scatl.folio.provider.CanonicalWork
import com.scatl.folio.dto.CountryView
import com.scatl.folio.dto.CreditView
import com.scatl.folio.dto.EpisodeView
import com.scatl.folio.dto.ExternalIdView
import com.scatl.folio.dto.FileView
import com.scatl.folio.dto.LanguageView
import com.scatl.folio.dto.NameView
import com.scatl.folio.dto.PageResult
import com.scatl.folio.dto.PersonDetailView
import com.scatl.folio.dto.PersonView
import com.scatl.folio.dto.PersonWorkCreditView
import com.scatl.folio.dto.RatingView
import com.scatl.folio.dto.ReviewFileRow
import com.scatl.folio.dto.EpisodeDetailView
import com.scatl.folio.dto.SeasonDetailView
import com.scatl.folio.dto.SeasonView
import com.scatl.folio.dto.TranslationView
import com.scatl.folio.dto.VideoDetail
import com.scatl.folio.dto.VideoView
import com.scatl.folio.dto.WorkBrowseQuery
import com.scatl.folio.dto.WorkCard
import com.scatl.folio.dto.WorkFacets
import com.scatl.folio.dto.WorkSummary
import com.scatl.folio.dto.WorkView
import com.scatl.folio.entity.Artwork
import com.scatl.folio.entity.Episode
import com.scatl.folio.entity.LibraryFile
import com.scatl.folio.entity.MatchStatus
import com.scatl.folio.entity.Season
import com.scatl.folio.entity.Work
import com.scatl.folio.entity.WorkTranslation
import com.scatl.folio.entity.Person
import com.scatl.folio.entity.PersonCredit
import com.scatl.folio.provider.TmdbPerson
import com.scatl.folio.provider.TmdbPersonCredit
import com.scatl.folio.repository.ArtworkRepository
import com.scatl.folio.repository.CompanyRepository
import com.scatl.folio.repository.CreditRepository
import com.scatl.folio.repository.EpisodeRepository
import com.scatl.folio.repository.ExternalIdRepository
import com.scatl.folio.repository.GenreRepository
import com.scatl.folio.repository.KeywordRepository
import com.scatl.folio.repository.LibraryFileRepository
import com.scatl.folio.repository.PersonCreditRepository
import com.scatl.folio.repository.PersonRepository
import com.scatl.folio.repository.RatingRepository
import com.scatl.folio.repository.SeasonRepository
import com.scatl.folio.repository.VideoRepository
import com.scatl.folio.repository.WorkCompanyRepository
import com.scatl.folio.repository.WorkCountryRepository
import com.scatl.folio.repository.WorkGenreRepository
import com.scatl.folio.repository.WorkKeywordRepository
import com.scatl.folio.repository.WorkLanguageRepository
import com.scatl.folio.repository.WorkRepository
import com.scatl.folio.repository.WorkTranslationRepository
import com.scatl.folio.settings.FolioSettings
import org.slf4j.LoggerFactory
import org.springframework.dao.DataIntegrityViolationException
import org.springframework.data.domain.PageRequest
import org.springframework.data.domain.Sort
import org.springframework.http.HttpStatus
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import org.springframework.web.server.ResponseStatusException
import tools.jackson.databind.json.JsonMapper
import java.time.Instant

@Service
open class LibraryQueryService(
    private val files: LibraryFileRepository,
    private val works: WorkRepository,
    private val translations: WorkTranslationRepository,
    private val externalIds: ExternalIdRepository,
    private val ratings: RatingRepository,
    private val artworks: ArtworkRepository,
    private val credits: CreditRepository,
    private val people: PersonRepository,
    private val personCredits: PersonCreditRepository,
    private val seasons: SeasonRepository,
    private val episodes: EpisodeRepository,
    private val genres: GenreRepository,
    private val workGenres: WorkGenreRepository,
    private val companies: CompanyRepository,
    private val workCompanies: WorkCompanyRepository,
    private val workCountries: WorkCountryRepository,
    private val workLanguages: WorkLanguageRepository,
    private val keywords: KeywordRepository,
    private val workKeywords: WorkKeywordRepository,
    private val videos: VideoRepository,
    private val appSettings: FolioSettings,
    private val probe: MediaProbeService,
    private val tmdb: TmdbClient,
    private val seriesIngest: SeriesEpisodeIngest,
    private val catalog: CatalogService,
    private val jsonMapper: JsonMapper,
    private val libraryAccess: LibraryAccessService,
    private val browse: WorkBrowse,
) {
    private val log = LoggerFactory.getLogger(javaClass)

    @Transactional(readOnly = true)
    open fun listWorks(request: WorkBrowseQuery): PageResult<WorkCard> {
        val normalized = WorkBrowse.normalize(request, libraryAccess.currentUserId())
        val scope = resolveReadableScope(request.libraryId)
            ?: return PageResult(emptyList(), normalized.page, normalized.size, 0, 0)
        val watchScope = resolveReadableScope(null) ?: scope
        val parsed = parseSearch(request.q)
        val found = browse.page(
            WorkBrowse.PageRequest(
                kind = normalized.kind,
                listRestrict = scope.restrict,
                listLibraryIds = scope.libraryIds,
                watchRestrict = watchScope.restrict,
                watchLibraryIds = watchScope.libraryIds,
                userId = normalized.userId,
                raw = parsed.raw,
                text = parsed.text,
                searchYear = parsed.year,
                sort = normalized.sort,
                watch = normalized.watch,
                genreIds = normalized.genreIds,
                yearFrom = normalized.yearFrom,
                yearTo = normalized.yearTo,
                ratingProvider = normalized.ratingProvider,
                ratingMin = normalized.ratingMin,
                countries = normalized.countries,
                languages = normalized.languages,
                runtimes = normalized.runtimes,
                keywordIds = normalized.keywordIds,
                personId = normalized.personId,
                companyIds = normalized.companyIds,
                collectionIds = normalized.collectionIds,
                inCollection = normalized.inCollection,
                showStatuses = normalized.showStatuses,
                resolutions = normalized.resolutions,
                dynamicRanges = normalized.dynamicRanges,
                videoCodecs = normalized.videoCodecs,
                audioCodecs = normalized.audioCodecs,
                subtitle = normalized.subtitle,
                offset = normalized.offset,
                limit = normalized.limit,
            ),
        )
        val totalPages = if (found.total == 0L) 0 else ((found.total + normalized.size - 1) / normalized.size).toInt()
        if (found.ids.isEmpty()) {
            return PageResult(emptyList(), normalized.page, normalized.size, found.total, totalPages)
        }
        val byId = works.findAllById(found.ids).associateBy { it.id }
        val rows = found.ids.mapNotNull { byId[it] }
        return PageResult(toCards(rows), normalized.page, normalized.size, found.total, totalPages)
    }

    @Transactional(readOnly = true)
    open fun facets(libraryId: Long?, personQ: String?): WorkFacets {
        val scope = resolveReadableScope(libraryId) ?: return browse.facets(true, emptyList(), null)
        return browse.facets(scope.restrict, scope.libraryIds, personQ)
    }

    /** 近期刮削作品：按文件最近匹配时间倒序，剧集按整部去重，一次返回最多 [limit] 条。 */
    @Transactional(readOnly = true)
    open fun listRecentScrapedWorks(limit: Int = 50): PageResult<WorkCard> {
        val size = limit.coerceIn(1, 100)
        val scope = resolveReadableScope(null) ?: return PageResult(emptyList(), 0, size, 0, 0)
        val ids = files.findRecentlyMatchedWorkIds(
            MatchStatus.matched,
            scope.restrict,
            scope.libraryIds,
            PageRequest.of(0, size),
        )
        if (ids.isEmpty()) {
            return PageResult(emptyList(), 0, size, 0, 0)
        }
        val byId = works.findAllById(ids).associateBy { requireNotNull(it.id) }
        val rows = ids.mapNotNull { byId[it] }
        val total = files.countDistinctMatchedWorks(MatchStatus.matched, scope.restrict, scope.libraryIds)
        val totalPages = if (total == 0L) 0 else ((total + size - 1) / size).toInt()
        return PageResult(toCards(rows), 0, size, total, totalPages)
    }

    @Transactional(readOnly = true)
    open fun listCollections(libraryId: Long): List<CollectionCard> {
        libraryAccess.requireRead(libraryId)
        val rows = works.findCollectedInLibrary(libraryId)
        if (rows.isEmpty()) return emptyList()
        val ids = rows.mapNotNull { it.id }
        val arts = artworks
            .findByOwnerTypeAndOwnerIdInAndKindIn(
                OwnerType.work,
                ids,
                listOf(ArtworkKind.collection_poster, ArtworkKind.poster),
            )
            .groupBy { it.ownerId }
        return rows.groupBy { requireNotNull(it.collectionExternalId) }
            .map { (collectionId, members) ->
                val poster = members.firstNotNullOfOrNull { member ->
                    arts[member.id].orEmpty().firstOrNull { it.kind == ArtworkKind.collection_poster }
                        ?.let { imageUrl(it.remoteUrl) }
                } ?: members.firstNotNullOfOrNull { member ->
                    arts[member.id].orEmpty().firstOrNull { it.kind == ArtworkKind.poster }
                        ?.let { imageUrl(it.remoteUrl) }
                }
                val name = members.firstNotNullOfOrNull { it.collectionName?.trim()?.takeIf { value -> value.isNotEmpty() } }
                    ?: collectionId
                CollectionCard(collectionId, name, poster, members.mapNotNull { it.id }.distinct().size)
            }
            .filter { it.count >= 2 }
            .sortedBy { it.name.lowercase() }
    }

    @Transactional(readOnly = true)
    open fun collectionWorks(libraryId: Long, collectionId: String): List<WorkCard> {
        libraryAccess.requireRead(libraryId)
        val id = collectionId.trim()
        if (id.isEmpty()) return emptyList()
        return toCards(works.findLocalInCollection(id, true, listOf(libraryId)))
    }

    /** 当前作品所属系列里，所有已入库的本地作品（含自身）。 */
    @Transactional(readOnly = true)
    open fun collectionSiblings(workId: Long): List<WorkCard> {
        libraryAccess.requireWorkReadable(workId)
        val work = works.findById(workId).orElseThrow { ResponseStatusException(HttpStatus.NOT_FOUND, "作品不存在") }
        val collectionId = work.collectionExternalId?.trim()?.takeIf { it.isNotEmpty() } ?: return emptyList()
        val scope = resolveReadableScope(null) ?: return emptyList()
        return toCards(works.findLocalInCollection(collectionId, scope.restrict, scope.libraryIds))
    }

    @Transactional(readOnly = true)
    open fun collection(collectionId: String): CollectionView {
        val id = collectionId.trim()
        if (id.isEmpty()) {
            throw ResponseStatusException(HttpStatus.BAD_REQUEST, "系列 ID 无效")
        }
        val scope = resolveReadableScope(null) ?: throw ResponseStatusException(HttpStatus.NOT_FOUND, "系列不存在")
        val localWorks = works.findLocalInCollection(id, scope.restrict, scope.libraryIds)
        val remote = fetchTmdbCollection(id)
        if (remote == null && localWorks.isEmpty()) {
            throw ResponseStatusException(HttpStatus.NOT_FOUND, "系列不存在")
        }
        if (remote != null) {
            val workIdByTmdb = workIdsByTmdb(remote.parts.map { it.id.toString() })
            val catalogWorkIds = workIdByTmdb.values.distinct()
            val localMediaWorkIds = workIdsWithLocalMedia(catalogWorkIds)
            val parts = remote.parts.map { part ->
                val tmdbId = part.id.toString()
                val title = part.title?.trim()?.takeIf { it.isNotEmpty() }
                    ?: part.originalTitle?.trim()?.takeIf { it.isNotEmpty() }
                    ?: "未命名"
                val workId = workIdByTmdb[tmdbId]
                CollectionPartView(
                    tmdbId = tmdbId,
                    title = title,
                    originalTitle = part.originalTitle?.trim()?.takeIf { it.isNotEmpty() },
                    overview = part.overview?.trim()?.takeIf { it.isNotEmpty() },
                    year = part.releaseDate?.year,
                    releaseDate = part.releaseDate?.toString(),
                    posterUrl = imageUrl(part.posterUrl),
                    backdropUrl = imageUrl(part.backdropUrl),
                    workId = workId,
                    hasLocalMedia = workId != null && workId in localMediaWorkIds,
                    rating = part.voteAverage,
                    voteCount = part.voteCount,
                    genres = tmdbMovieGenreNames(part.genreIds),
                    originalLanguage = part.originalLanguage?.trim()?.takeIf { it.isNotEmpty() },
                )
            }
            return CollectionView(
                id = remote.id.toString(),
                name = remote.name,
                overview = remote.overview?.trim()?.takeIf { it.isNotEmpty() },
                posterUrl = imageUrl(remote.posterUrl),
                backdropUrl = imageUrl(remote.backdropUrl),
                parts = parts,
                localCount = parts.count { it.hasLocalMedia },
            )
        }
        val cards = toCards(localWorks)
        val cardById = cards.associateBy { it.id }
        val tmdbByWork = tmdbIdsByWork(localWorks.mapNotNull { it.id })
        val parts = localWorks.mapNotNull { work ->
            val workId = work.id ?: return@mapNotNull null
            val card = cardById[workId]
            CollectionPartView(
                tmdbId = tmdbByWork[workId].orEmpty(),
                title = card?.title ?: work.originalTitle,
                originalTitle = work.originalTitle,
                overview = card?.overview,
                year = work.releaseYear,
                releaseDate = work.premiereDate?.toString(),
                posterUrl = card?.posterUrl,
                backdropUrl = card?.backdropUrl,
                workId = workId,
                hasLocalMedia = true,
                rating = card?.rating,
                voteCount = card?.voteCount,
                genres = card?.genres.orEmpty(),
                originalLanguage = work.originalLanguage?.trim()?.takeIf { it.isNotEmpty() },
            )
        }
        val name = localWorks.firstNotNullOfOrNull { it.collectionName?.trim()?.takeIf { value -> value.isNotEmpty() } } ?: id
        return CollectionView(
            id = id,
            name = name,
            overview = null,
            posterUrl = parts.firstNotNullOfOrNull { it.posterUrl },
            backdropUrl = parts.firstNotNullOfOrNull { it.backdropUrl },
            parts = parts,
            localCount = parts.size,
        )
    }

    private fun fetchTmdbCollection(id: String): TmdbCollection? {
        val numeric = id.toLongOrNull() ?: return null
        if (!tmdb.configured()) return null
        return try {
            tmdb.collection(numeric)
        } catch (ex: ProviderException) {
            if (ex.status == 404) null else throw ResponseStatusException(HttpStatus.BAD_GATEWAY, ex.message ?: "TMDB 请求失败")
        } catch (ex: RuntimeException) {
            log.warn("拉取系列详情失败 id={}: {}", id, ex.message)
            null
        }
    }

    @Transactional
    open fun workByExternal(provider: String, externalId: String, kind: String): WorkView {
        val (externalProvider, tmdbId, workKind) = parseWorkExternalKey(provider, externalId, kind)
        if (externalProvider != ExternalProvider.tmdb) {
            throw ResponseStatusException(HttpStatus.BAD_REQUEST, "仅支持按 TMDB 打开作品")
        }
        val existingId = findWorkIdByTmdbAndKind(tmdbId, workKind)
        if (existingId != null) {
            return work(existingId)
        }
        return hydrateWorkFromTmdb(tmdbId, workKind)
    }

    @Transactional
    open fun refreshWork(id: Long): WorkView {
        libraryAccess.requireWorkWritable(id)
        val work = works.findById(id).orElseThrow { ResponseStatusException(HttpStatus.NOT_FOUND, "作品不存在") }
        val tmdbId = externalIds.findByOwnerTypeAndOwnerIdOrderByProviderAsc(OwnerType.work, id)
            .firstOrNull { it.provider == ExternalProvider.tmdb }
            ?.externalId
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?: throw ResponseStatusException(HttpStatus.BAD_REQUEST, "该作品没有 TMDB 编号，无法刷新")
        return hydrateWorkFromTmdb(tmdbId, work.kind)
    }

    private fun parseWorkExternalKey(
        provider: String,
        externalId: String,
        kind: String,
    ): Triple<ExternalProvider, String, WorkKind> {
        val providerKey = provider.trim().lowercase()
        val id = externalId.trim()
        if (providerKey.isEmpty() || id.isEmpty()) {
            throw ResponseStatusException(HttpStatus.BAD_REQUEST, "作品参数无效")
        }
        val externalProvider = try {
            ExternalProvider.valueOf(providerKey)
        } catch (_: IllegalArgumentException) {
            throw ResponseStatusException(HttpStatus.BAD_REQUEST, "作品来源无效")
        }
        val workKind = mediaTypeToWorkKind(kind)
            ?: throw ResponseStatusException(HttpStatus.BAD_REQUEST, "作品类型无效，请使用 movie 或 tv")
        return Triple(externalProvider, id, workKind)
    }

    private fun findWorkIdByTmdbAndKind(tmdbId: String, kind: WorkKind): Long? {
        val ext = externalIds
            .findByOwnerTypeAndProviderAndExternalId(OwnerType.work, ExternalProvider.tmdb, tmdbId)
            .orElse(null)
            ?: return null
        val work = works.findById(ext.ownerId).orElse(null) ?: return null
        if (work.kind != kind) {
            throw ResponseStatusException(
                HttpStatus.CONFLICT,
                "TMDB $tmdbId 已对应${if (work.kind == WorkKind.movie) "电影" else "剧集"}，与请求类型冲突",
            )
        }
        return work.id
    }

    private fun hydrateWorkFromTmdb(tmdbId: String, kind: WorkKind): WorkView {
        val numeric = tmdbId.toLongOrNull()
            ?: throw ResponseStatusException(HttpStatus.BAD_REQUEST, "TMDB ID 无效")
        if (!tmdb.configured()) {
            throw ResponseStatusException(HttpStatus.BAD_GATEWAY, "TMDB 未配置")
        }
        val canonical = try {
            when (kind) {
                WorkKind.movie -> tmdb.movie(numeric)
                WorkKind.series -> tmdb.series(numeric, null)
            }
        } catch (ex: ProviderException) {
            if (ex.status == 404) throw ResponseStatusException(HttpStatus.NOT_FOUND, "作品不存在")
            throw ResponseStatusException(HttpStatus.BAD_GATEWAY, ex.message ?: "TMDB 请求失败")
        }
        val saved = try {
            catalog.save(canonical, null, null)
        } catch (ex: DataIntegrityViolationException) {
            val existingId = findWorkIdByTmdbAndKind(tmdbId, kind)
            if (existingId != null) return work(existingId)
            throw ResponseStatusException(HttpStatus.CONFLICT, "作品写入冲突")
        } catch (ex: RuntimeException) {
            log.warn("按 TMDB 入库失败 tmdbId={} kind={}: {}", tmdbId, kind, ex.message)
            throw ResponseStatusException(HttpStatus.BAD_GATEWAY, ex.message ?: "作品入库失败")
        }
        return work(saved.workId)
    }

    @Transactional
    open fun person(provider: String, externalId: String): PersonDetailView {
        val (externalProvider, personId) = parsePersonKey(provider, externalId)
        return if (externalProvider == ExternalProvider.tmdb) {
            val existing = people.findByProviderAndProviderPersonId(ExternalProvider.tmdb, personId).orElse(null)
            if (existing?.detailFetchedAt != null) {
                personDetailFromDb(existing)
            } else {
                hydrateFromTmdb(personId, existing)
            }
        } else {
            localPersonDetail(externalProvider, personId)
        }
    }

    @Transactional
    open fun refreshPerson(provider: String, externalId: String): PersonDetailView {
        val (externalProvider, personId) = parsePersonKey(provider, externalId)
        if (externalProvider != ExternalProvider.tmdb) {
            throw ResponseStatusException(HttpStatus.BAD_REQUEST, "仅支持刷新 TMDB 人物")
        }
        val existing = people.findByProviderAndProviderPersonId(ExternalProvider.tmdb, personId).orElse(null)
        return hydrateFromTmdb(personId, existing)
    }

    private fun parsePersonKey(provider: String, externalId: String): Pair<ExternalProvider, String> {
        val providerKey = provider.trim().lowercase()
        val personId = externalId.trim()
        if (providerKey.isEmpty() || personId.isEmpty()) {
            throw ResponseStatusException(HttpStatus.BAD_REQUEST, "人物 ID 无效")
        }
        val externalProvider = try {
            ExternalProvider.valueOf(providerKey)
        } catch (_: IllegalArgumentException) {
            throw ResponseStatusException(HttpStatus.BAD_REQUEST, "人物来源无效")
        }
        return externalProvider to personId
    }

    private fun hydrateFromTmdb(personId: String, existing: Person?): PersonDetailView {
        val numeric = personId.toLongOrNull()
            ?: throw ResponseStatusException(HttpStatus.BAD_REQUEST, "人物 ID 无效")
        if (!tmdb.configured()) {
            throw ResponseStatusException(HttpStatus.BAD_GATEWAY, "TMDB 未配置")
        }
        val remote = try {
            tmdb.person(numeric)
        } catch (ex: ProviderException) {
            if (ex.status == 404) throw ResponseStatusException(HttpStatus.NOT_FOUND, "人物不存在")
            throw ResponseStatusException(HttpStatus.BAD_GATEWAY, ex.message ?: "TMDB 请求失败")
        }
        val remoteCredits = try {
            tmdb.personCombinedCredits(numeric)
        } catch (ex: ProviderException) {
            if (ex.status == 404) emptyList()
            else throw ResponseStatusException(HttpStatus.BAD_GATEWAY, ex.message ?: "TMDB 请求失败")
        } catch (ex: RuntimeException) {
            log.warn("拉取人物作品失败 personId={}: {}", personId, ex.message)
            emptyList()
        }
        val person = upsertTmdbPerson(personId, remote, existing)
        val personPk = requireNotNull(person.id)
        personCredits.deleteByPersonId(personPk)
        val rows = remoteCredits.mapNotNull { credit -> toPersonCreditEntity(person, credit) }
        if (rows.isNotEmpty()) {
            personCredits.saveAll(rows)
        }
        return personDetailFromDb(person)
    }

    private fun upsertTmdbPerson(personId: String, remote: TmdbPerson, existing: Person?): Person {
        val person = existing ?: people.findByProviderAndProviderPersonId(ExternalProvider.tmdb, personId).orElse(null)
            ?: try {
                people.saveAndFlush(
                    Person().apply {
                        provider = ExternalProvider.tmdb
                        providerPersonId = personId
                        name = remote.name.take(512)
                    },
                )
            } catch (ex: DataIntegrityViolationException) {
                people.findByProviderAndProviderPersonId(ExternalProvider.tmdb, personId)
                    .orElseThrow { ResponseStatusException(HttpStatus.CONFLICT, "人物写入冲突") }
            }
        person.name = remote.name.take(512)
        val profile = remote.profileUrl?.trim()?.takeIf { it.isNotEmpty() }
        if (profile != null) {
            person.profileUrl = profile.take(1024)
        }
        person.biography = remote.biography?.trim()?.takeIf { it.isNotEmpty() }
        person.birthday = remote.birthday
        person.deathday = remote.deathday
        person.placeOfBirth = remote.placeOfBirth?.trim()?.takeIf { it.isNotEmpty() }?.take(512)
        person.knownForDepartment = remote.knownForDepartment?.trim()?.takeIf { it.isNotEmpty() }?.take(128)
        person.alsoKnownAs = encodeAlsoKnownAs(remote.alsoKnownAs)
        person.detailFetchedAt = Instant.now()
        return people.save(person)
    }

    private fun toPersonCreditEntity(person: Person, credit: TmdbPersonCredit): PersonCredit? {
        val mediaType = when (credit.mediaType.trim().lowercase()) {
            "tv" -> "tv"
            "movie" -> "movie"
            else -> return null
        }
        val title = credit.title?.trim()?.takeIf { it.isNotEmpty() }
            ?: credit.originalTitle?.trim()?.takeIf { it.isNotEmpty() }
            ?: "未命名"
        return PersonCredit().apply {
            this.person = person
            this.mediaType = mediaType
            providerMediaId = credit.id.toString()
            this.title = title.take(512)
            originalTitle = credit.originalTitle?.trim()?.takeIf { it.isNotEmpty() }?.take(512)
            releaseYear = credit.year
            releaseDate = credit.releaseDate
            posterUrl = credit.posterUrl?.trim()?.takeIf { it.isNotEmpty() }?.take(1024)
            characterName = credit.character?.trim()?.takeIf { it.isNotEmpty() }?.take(512)
            jobName = credit.job?.trim()?.takeIf { it.isNotEmpty() }?.take(64)
            department = credit.department?.trim()?.takeIf { it.isNotEmpty() }?.take(64)
        }
    }

    private fun personDetailFromDb(person: Person): PersonDetailView {
        val personPk = requireNotNull(person.id)
        val creditRows = personCredits.findByPersonId(personPk)
        val workIdByKey = workIdsByTmdbAndKind(
            creditRows.map { it.providerMediaId to mediaTypeToWorkKind(it.mediaType) },
        )
        val localMediaWorkIds = workIdsWithLocalMedia(workIdByKey.values.distinct())
        val creditViews = creditRows
            .map { row ->
                val kind = mediaTypeToWorkKind(row.mediaType)
                val workId = kind?.let { workIdByKey[row.providerMediaId to it] }
                PersonWorkCreditView(
                    mediaType = if (kind == WorkKind.series) "tv" else "movie",
                    tmdbId = row.providerMediaId,
                    title = row.title,
                    originalTitle = row.originalTitle,
                    year = row.releaseYear,
                    releaseDate = row.releaseDate?.toString(),
                    posterUrl = imageUrl(row.posterUrl),
                    character = row.characterName,
                    job = row.jobName,
                    department = row.department,
                    workId = workId,
                    hasLocalMedia = workId != null && workId in localMediaWorkIds,
                )
            }
            .sortedWith(personCreditComparator())
        return PersonDetailView(
            provider = person.provider.name,
            externalId = person.providerPersonId,
            name = person.name,
            biography = person.biography,
            birthday = person.birthday,
            deathday = person.deathday,
            placeOfBirth = person.placeOfBirth,
            profileUrl = imageUrl(person.profileUrl),
            knownForDepartment = person.knownForDepartment,
            alsoKnownAs = decodeAlsoKnownAs(person.alsoKnownAs),
            credits = creditViews,
            localCount = creditViews.count { it.hasLocalMedia },
            detailFetchedAt = person.detailFetchedAt,
        )
    }

    private fun localPersonDetail(provider: ExternalProvider, personId: String): PersonDetailView {
        val person = people.findByProviderAndProviderPersonId(provider, personId)
            .orElseThrow { ResponseStatusException(HttpStatus.NOT_FOUND, "人物不存在") }
        if (person.detailFetchedAt != null && provider == ExternalProvider.tmdb) {
            return personDetailFromDb(person)
        }
        val personPk = requireNotNull(person.id)
        val creditRows = credits.findByPersonAndOwnerType(personPk, OwnerType.work)
        val workIds = creditRows.map { it.ownerId }.distinct()
        val workById = if (workIds.isEmpty()) {
            emptyMap()
        } else {
            works.findAllById(workIds).associateBy { requireNotNull(it.id) }
        }
        val cards = toCards(workById.values.toList()).associateBy { it.id }
        val tmdbByWork = tmdbIdsByWork(workIds)
        val localMediaWorkIds = workIdsWithLocalMedia(workIds)
        val byWork = linkedMapOf<Long, PersonWorkCreditView>()
        for (credit in creditRows) {
            val work = workById[credit.ownerId] ?: continue
            val workId = requireNotNull(work.id)
            if (byWork.containsKey(workId)) {
                val existing = byWork.getValue(workId)
                byWork[workId] = existing.copy(
                    character = existing.character ?: credit.characterName?.trim()?.takeIf { it.isNotEmpty() },
                    job = existing.job ?: credit.jobName?.trim()?.takeIf { it.isNotEmpty() },
                    department = existing.department ?: credit.department?.trim()?.takeIf { it.isNotEmpty() },
                )
                continue
            }
            val card = cards[workId]
            val mediaType = if (work.kind == WorkKind.series) "tv" else "movie"
            byWork[workId] = PersonWorkCreditView(
                mediaType = mediaType,
                tmdbId = tmdbByWork[workId].orEmpty(),
                title = card?.title ?: work.originalTitle,
                originalTitle = work.originalTitle,
                year = work.releaseYear,
                releaseDate = work.premiereDate?.toString(),
                posterUrl = card?.posterUrl,
                character = credit.characterName?.trim()?.takeIf { it.isNotEmpty() },
                job = credit.jobName?.trim()?.takeIf { it.isNotEmpty() },
                department = credit.department?.trim()?.takeIf { it.isNotEmpty() },
                workId = workId,
                hasLocalMedia = workId in localMediaWorkIds,
            )
        }
        val creditViews = byWork.values.sortedWith(personCreditComparator())
        return PersonDetailView(
            provider = provider.name,
            externalId = personId,
            name = person.name,
            biography = person.biography,
            birthday = person.birthday,
            deathday = person.deathday,
            placeOfBirth = person.placeOfBirth,
            profileUrl = imageUrl(person.profileUrl),
            knownForDepartment = person.knownForDepartment,
            alsoKnownAs = decodeAlsoKnownAs(person.alsoKnownAs),
            credits = creditViews,
            localCount = creditViews.count { it.hasLocalMedia },
            detailFetchedAt = person.detailFetchedAt,
        )
    }

    private fun workIdsWithLocalMedia(workIds: Collection<Long>): Set<Long> {
        val ids = workIds.filter { it > 0 }.distinct()
        if (ids.isEmpty()) return emptySet()
        return files.findWorkIdsWithFiles(ids).toSet()
    }

    private fun personCreditComparator(): Comparator<PersonWorkCreditView> =
        compareByDescending<PersonWorkCreditView> { it.releaseDate ?: "" }
            .thenByDescending { it.year ?: Int.MIN_VALUE }
            .thenBy { it.title }

    private fun encodeAlsoKnownAs(names: List<String>): String? {
        val cleaned = names.map { it.trim() }.filter { it.isNotEmpty() }
        if (cleaned.isEmpty()) return null
        return jsonMapper.writeValueAsString(cleaned)
    }

    private fun decodeAlsoKnownAs(raw: String?): List<String> {
        val text = raw?.trim()?.takeIf { it.isNotEmpty() } ?: return emptyList()
        return try {
            jsonMapper.readValue(text, Array<String>::class.java).map { it.trim() }.filter { it.isNotEmpty() }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun workIdsByTmdb(tmdbIds: Collection<String>): Map<String, Long> {
        val ids = tmdbIds.map { it.trim() }.filter { it.isNotEmpty() }.distinct()
        if (ids.isEmpty()) return emptyMap()
        return externalIds
            .findByOwnerTypeAndProviderAndExternalIdIn(OwnerType.work, ExternalProvider.tmdb, ids)
            .associate { it.externalId to it.ownerId }
    }

    private fun workIdsByTmdbAndKind(entries: List<Pair<String, WorkKind?>>): Map<Pair<String, WorkKind>, Long> {
        val ids = entries.map { it.first }.filter { it.isNotEmpty() }.distinct()
        if (ids.isEmpty()) return emptyMap()
        val extRows = externalIds.findByOwnerTypeAndProviderAndExternalIdIn(
            OwnerType.work,
            ExternalProvider.tmdb,
            ids,
        )
        if (extRows.isEmpty()) return emptyMap()
        val workById = works.findAllById(extRows.map { it.ownerId }.distinct())
            .associateBy { requireNotNull(it.id) }
        return buildMap {
            for (ext in extRows) {
                val work = workById[ext.ownerId] ?: continue
                put(ext.externalId to work.kind, ext.ownerId)
            }
        }
    }

    private fun mediaTypeToWorkKind(mediaType: String): WorkKind? =
        when (mediaType.trim().lowercase()) {
            "movie" -> WorkKind.movie
            "tv" -> WorkKind.series
            else -> null
        }

    private fun tmdbIdsByWork(workIds: Collection<Long>): Map<Long, String> {
        if (workIds.isEmpty()) return emptyMap()
        return workIds.flatMap { ownerId ->
            externalIds.findByOwnerTypeAndOwnerIdOrderByProviderAsc(OwnerType.work, ownerId)
                .filter { it.provider == ExternalProvider.tmdb }
                .map { it.ownerId to it.externalId }
        }.toMap()
    }

    @Transactional(readOnly = true)
    open fun workCard(id: Long): WorkCard {
        libraryAccess.requireWorkReadable(id)
        val work = works.findById(id).orElseThrow { ResponseStatusException(HttpStatus.NOT_FOUND, "作品不存在") }
        return toCards(listOf(work)).first()
    }

    private fun toCards(rows: List<Work>): List<WorkCard> {
        if (rows.isEmpty()) return emptyList()
        val ids = rows.mapNotNull { it.id }
        val translationMap = translations.findByWorkIdIn(ids).groupBy { it.workId }
        val artworkMap = artworks
            .findByOwnerTypeAndOwnerIdInAndKindIn(OwnerType.work, ids, listOf(ArtworkKind.poster, ArtworkKind.backdrop))
            .groupBy { it.ownerId }
        val ratingMap = ratings.findByOwnerTypeAndOwnerIdIn(OwnerType.work, ids).groupBy { it.ownerId }
        val genreLinks = workGenres.findByWorkIdIn(ids)
        val genreIds = genreLinks.map { it.genreId }.distinct()
        val genreNameById = if (genreIds.isEmpty()) {
            emptyMap()
        } else {
            genres.findAllById(genreIds).associate { requireNotNull(it.id) to it.name }
        }
        val genresByWork = genreLinks.groupBy({ it.workId }, { genreNameById[it.genreId] }).mapValues { (_, names) ->
            names.filterNotNull().distinct()
        }
        val watchStates = watchStates(ids)
        return rows.map { work ->
            val id = requireNotNull(work.id)
            val localeTranslations = translationMap[id].orEmpty()
            val preferred = pickTranslation(localeTranslations)
            val arts = artworkMap[id].orEmpty()
            val poster = arts.firstOrNull { it.kind == ArtworkKind.poster && it.locale.equals("zh-CN", ignoreCase = true) }
                ?: arts.firstOrNull { it.kind == ArtworkKind.poster }
            val backdrop = arts.firstOrNull { it.kind == ArtworkKind.backdrop && it.locale.equals("zh-CN", ignoreCase = true) }
                ?: arts.firstOrNull { it.kind == ArtworkKind.backdrop }
            val rating = ratingMap[id].orEmpty().maxByOrNull { it.votes ?: 0 }
            WorkCard(
                id,
                work.kind.name,
                work.originalTitle,
                preferred?.title ?: work.originalTitle,
                work.releaseYear,
                imageUrl(poster?.remoteUrl),
                imageUrl(backdrop?.remoteUrl),
                rating?.scoreValue,
                rating?.votes,
                genresByWork[id].orEmpty(),
                work.popularity,
                preferred?.overview,
                watchStates[id],
            )
        }
    }

    @Transactional(readOnly = true)
    fun contentFile(id: Long): LibraryFile {
        libraryAccess.requireFileReadable(id)
        return files.findById(id).orElseThrow { ResponseStatusException(HttpStatus.NOT_FOUND, "文件不存在") }
    }

    open fun file(id: Long): FileView {
        libraryAccess.requireFileReadable(id)
        val file = files.findWithMatchById(id).orElseThrow { ResponseStatusException(HttpStatus.NOT_FOUND, "文件不存在") }
        val work = file.work
        val summary = work?.let {
            WorkSummary(
                requireNotNull(it.id),
                it.kind.name,
                it.originalTitle,
                it.releaseYear,
                it.sourceProvider.name,
                translationViews(requireNotNull(it.id)),
            )
        }
        return FileView(
            requireNotNull(file.id),
            file.fileName,
            file.locator,
            file.matchStatus.name,
            file.parsedTitle,
            file.parsedYear,
            file.parsedSeason,
            file.parsedEpisode,
            file.parsedImdbId,
            file.confidence,
            file.message,
            work?.id,
            file.episode?.id,
            summary,
        )
    }

    @Transactional(readOnly = true)
    open fun work(id: Long): WorkView {
        libraryAccess.requireWorkReadable(id)
        val work = works.findById(id).orElseThrow { ResponseStatusException(HttpStatus.NOT_FOUND, "作品不存在") }
        val libraryFileRows = files.findByWork_IdOrderByIdAsc(id)
        val localEpisodeIds = files.findEpisodeIdsByWorkId(id).toSet()
        val episodeRows = episodes.findByWorkIdOrderByEpisodeNumberAsc(id)
        val seasonRows = seasons.findByWorkIdOrderBySeasonNumberAsc(id)
        val seasonIds = seasonRows.mapNotNull { it.id }
        val seasonArtworks = if (seasonIds.isEmpty()) {
            emptyMap()
        } else {
            artworks.findByOwnerTypeAndOwnerIdIn(OwnerType.season, seasonIds).groupBy { it.ownerId }
        }
        // 作品详情返回全部季（含无本地视频）；集列表交给季详情接口
        val seasonViews = seasonRows.map { season ->
            val seasonId = requireNotNull(season.id)
            val seasonEps = episodeRows.filter { it.seasonId == seasonId }
            val localCount = seasonEps.count { it.id != null && it.id in localEpisodeIds }
            toSeasonView(
                season,
                seasonEps,
                includeEpisodes = false,
                seasonArtworks[seasonId].orEmpty(),
                localEpisodeCount = localCount,
            )
        }
        val creditRows = credits.findForOwner(OwnerType.work, id)
        val people = creditRows.mapNotNull { it.person }.distinctBy { it.id }
        val personIds = people.mapNotNull { it.id }
        val personArtworks = if (personIds.isEmpty()) {
            emptyMap()
        } else {
            artworks.findByOwnerTypeAndOwnerIdIn(OwnerType.person, personIds).groupBy { it.ownerId }
        }
        val personViews = people.map { person ->
            val personId = requireNotNull(person.id)
            PersonView(
                person.provider.name,
                person.providerPersonId,
                person.name,
                imageUrl(person.profileUrl),
                artworkViews(personArtworks[personId].orEmpty()),
            )
        }
        val genreViews = workGenres.findByWorkId(id).mapNotNull { link ->
            genres.findById(link.genreId).orElse(null)?.let { NameView(it.externalId, it.name) }
        }
        val companyViews = workCompanies.findByWorkId(id).mapNotNull { link ->
            companies.findById(link.companyId).orElse(null)?.let {
                CompanyView(it.externalId, it.name, it.originCountry, imageUrl(it.logoUrl), link.companyRole)
            }
        }
        return WorkView(
            id,
            work.kind.name,
            work.originalTitle,
            work.originalLanguage,
            work.releaseYear,
            work.premiereDate,
            work.runtimeMinutes,
            DisplayLabels.workStatus(work.workStatus),
            work.homepage,
            work.popularity,
            work.budget,
            work.revenue,
            work.adult,
            DisplayLabels.showType(work.showType),
            work.inProduction,
            work.lastAirDate,
            work.numberOfSeasons,
            work.numberOfEpisodes,
            work.collectionExternalId,
            work.collectionName,
            work.awards,
            work.sourceProvider.name,
            translationViews(id),
            externalIds.findByOwnerTypeAndOwnerIdOrderByProviderAsc(OwnerType.work, id)
                .map { ExternalIdView(it.provider.name, it.externalId, ProviderLogos.url(it.provider)) },
            ratings.findByOwnerTypeAndOwnerIdOrderByProviderAsc(OwnerType.work, id)
                .map {
                    RatingView(
                        it.provider.name,
                        it.scoreValue,
                        it.votes,
                        it.scoreScale,
                        ProviderLogos.url(it.provider),
                    )
                },
            artworkViews(OwnerType.work, id),
            creditRows.map { credit ->
                CreditView(
                    credit.person?.provider?.name ?: "",
                    credit.person?.providerPersonId ?: "",
                    credit.person?.name ?: "",
                    imageUrl(credit.person?.profileUrl),
                    credit.department,
                    credit.jobName,
                    credit.characterName,
                    credit.sortOrder,
                )
            },
            personViews,
            genreViews,
            companyViews,
            workCountries.findByWorkId(id).map { CountryView(it.countryCode, it.name, it.countryKind) },
            workLanguages.findByWorkId(id).map { LanguageView(it.languageCode, it.name) },
            workKeywords.findByWorkId(id).mapNotNull { link ->
                keywords.findById(link.keywordId).orElse(null)?.let { NameView(it.externalId, it.name) }
            },
            videos.findByOwnerTypeAndOwnerIdOrderByIdAsc(OwnerType.work, id).map {
                VideoView(it.externalId, it.site, it.videoType, it.name, it.videoKey, it.language, it.official)
            },
            seasonViews,
            libraryFileRows.map { reviewFileRow(it) },
        )
    }

    @Transactional
    open fun season(workId: Long, seasonNumber: Int): SeasonDetailView {
        libraryAccess.requireWorkReadable(workId)
        val work = works.findById(workId).orElseThrow { ResponseStatusException(HttpStatus.NOT_FOUND, "作品不存在") }
        var season = seasons.findByWorkIdAndSeasonNumber(workId, seasonNumber)
            .orElseThrow { ResponseStatusException(HttpStatus.NOT_FOUND, "季不存在") }
        maybeHydrateSeasonEpisodes(workId, season)
        season = seasons.findByWorkIdAndSeasonNumber(workId, seasonNumber)
            .orElseThrow { ResponseStatusException(HttpStatus.NOT_FOUND, "季不存在") }
        val seasonId = requireNotNull(season.id)
        val episodeRows = episodes.findBySeasonIdOrderByEpisodeNumberAsc(seasonId)
        val filesByEpisode = files.findByWork_IdOrderByIdAsc(workId)
            .groupBy { it.episode?.id }
            .mapNotNull { (episodeId, rows) ->
                if (episodeId == null) return@mapNotNull null
                episodeId to rows.map { reviewFileRow(it) }
            }
            .toMap()
        val localCount = episodeRows.count { ep ->
            val id = ep.id ?: return@count false
            filesByEpisode[id]?.isNotEmpty() == true
        }
        val title = pickTranslation(translations.findByWorkIdOrderByLocaleAsc(workId))?.title
            ?.takeIf { it.isNotBlank() }
            ?: work.originalTitle
        return SeasonDetailView(
            workId,
            work.kind.name,
            title,
            work.originalTitle,
            toSeasonView(
                season,
                episodeRows,
                includeEpisodes = true,
                null,
                filesByEpisode,
                localEpisodeCount = localCount,
            ),
        )
    }

    @Transactional(readOnly = true)
    open fun episode(workId: Long, seasonNumber: Int, episodeNumber: Int): EpisodeDetailView {
        libraryAccess.requireWorkReadable(workId)
        val work = works.findById(workId).orElseThrow { ResponseStatusException(HttpStatus.NOT_FOUND, "作品不存在") }
        val season = seasons.findByWorkIdAndSeasonNumber(workId, seasonNumber)
            .orElseThrow { ResponseStatusException(HttpStatus.NOT_FOUND, "季不存在") }
        val seasonId = requireNotNull(season.id)
        val episode = episodes.findBySeasonIdAndEpisodeNumber(seasonId, episodeNumber)
            .orElseThrow { ResponseStatusException(HttpStatus.NOT_FOUND, "集不存在") }
        val episodeId = requireNotNull(episode.id)
        val episodeFiles = files.findByWork_IdOrderByIdAsc(workId)
            .filter { it.episode?.id == episodeId }
            .map { reviewFileRow(it) }
        val title = pickTranslation(translations.findByWorkIdOrderByLocaleAsc(workId))?.title
            ?.takeIf { it.isNotBlank() }
            ?: work.originalTitle
        val localArtworks = artworkViews(OwnerType.episode, episodeId)
        val enrich = fetchTmdbEpisode(workId, seasonNumber, episodeNumber)
        val artworks = mergeEpisodeArtworks(localArtworks, enrich?.stills.orEmpty())
        return EpisodeDetailView(
            workId,
            work.kind.name,
            title,
            work.originalTitle,
            season.seasonNumber,
            season.name,
            EpisodeView(
                episodeId,
                episode.episodeNumber,
                episode.absoluteNumber,
                episode.title,
                episode.overview,
                episode.airDate,
                episode.runtimeMinutes,
                episode.voteAverage,
                episode.voteCount,
                artworks,
                episodeFiles,
            ),
            enrich?.productionCode,
            enrich?.credits?.map { creditView(it) }.orEmpty(),
            enrich?.externalIds?.map {
                ExternalIdView(it.provider.name, it.externalId, ProviderLogos.url(it.provider))
            }.orEmpty(),
            enrich?.videos?.map {
                VideoView(it.externalId, it.site, it.type, it.name, it.key, it.language, it.official)
            }.orEmpty(),
        )
    }

    private fun fetchTmdbEpisode(workId: Long, seasonNumber: Int, episodeNumber: Int): TmdbEpisodeDetail? {
        if (!tmdb.configured()) return null
        val seriesId = tmdbIdsByWork(listOf(workId))[workId]?.toLongOrNull() ?: return null
        return try {
            tmdb.episode(seriesId, seasonNumber, episodeNumber)
        } catch (ex: ProviderException) {
            if (ex.status == 404) null else {
                log.warn("拉取集详情失败 workId={} S{}E{}: {}", workId, seasonNumber, episodeNumber, ex.message)
                null
            }
        } catch (ex: RuntimeException) {
            log.warn("拉取集详情失败 workId={} S{}E{}: {}", workId, seasonNumber, episodeNumber, ex.message)
            null
        }
    }

    private fun creditView(ref: CanonicalWork.CreditRef) =
        CreditView(
            ref.provider.name,
            ref.personId,
            ref.name,
            imageUrl(ref.profileUrl),
            ref.department,
            ref.job,
            ref.character,
            ref.order,
        )

    private fun mergeEpisodeArtworks(
        local: List<ArtworkView>,
        remote: List<CanonicalWork.ArtworkRef>,
    ): List<ArtworkView> {
        val seen = linkedSetOf<String>()
        val merged = mutableListOf<ArtworkView>()
        for (art in local) {
            val url = art.remoteUrl.trim()
            if (url.isEmpty() || !seen.add(url)) continue
            merged += art
        }
        for (art in remote) {
            val url = imageUrl(art.remoteUrl)?.trim().orEmpty()
            if (url.isEmpty() || !seen.add(url)) continue
            merged += ArtworkView(art.provider.name, art.kind.name, art.locale, url)
        }
        return merged
    }

    @Transactional(readOnly = true)
    open fun reviewFile(id: Long): ReviewFileRow {
        val file = files.findById(id).orElseThrow { ResponseStatusException(HttpStatus.NOT_FOUND, "文件不存在") }
        return reviewFileRow(file)
    }

    open fun reviewFileRow(file: LibraryFile) = ReviewFileRow(
        requireNotNull(file.id),
        file.fileName,
        file.locator,
        file.matchStatus.name,
        file.parsedTitle,
        file.parsedYear,
        file.parsedSeason,
        file.parsedEpisode,
        file.confidence,
        file.message,
        file.fileSize,
        file.sourceModifiedAt,
        file.mediaContainer,
        file.durationMs,
        file.videoCodec,
        file.videoWidth,
        file.videoHeight,
        file.videoFrameRate?.toDouble(),
        file.videoBitrate,
        file.videoBitDepth,
        file.videoDynamicRange,
        file.videoProfile,
        file.videoPixelFormat,
        probe.decodeAudio(file.audioTracks),
        probe.decodeSubtitles(file.subtitleTracks),
    )

    @Transactional(readOnly = true)
    open fun detail(id: Long): VideoDetail {
        libraryAccess.requireFileReadable(id)
        val file = files.findWithMatchById(id).orElseThrow { ResponseStatusException(HttpStatus.NOT_FOUND, "文件不存在") }
        val workId = file.work?.id
        return VideoDetail(
            requireNotNull(file.id),
            file.fileName,
            file.locator,
            file.matchStatus.name,
            file.parsedTitle,
            file.parsedYear,
            file.parsedSeason,
            file.parsedEpisode,
            file.parsedImdbId,
            file.confidence,
            file.message,
            file.episode?.id,
            workId?.let { work(it) },
        )
    }

    private fun translationViews(workId: Long) = translations.findByWorkIdOrderByLocaleAsc(workId)
        .map { TranslationView(it.locale, it.title, it.overview, it.tagline) }

    private fun pickTranslation(rows: List<WorkTranslation>) =
        rows.firstOrNull { it.locale.equals("zh-CN", ignoreCase = true) }

    private fun artworkViews(ownerType: OwnerType, ownerId: Long) =
        artworkViews(artworks.findByOwnerTypeAndOwnerIdOrderByIdAsc(ownerType, ownerId))

    private fun artworkViews(rows: List<Artwork>) =
        rows.map { ArtworkView(it.provider.name, it.kind.name, it.locale, imageUrl(it.remoteUrl) ?: it.remoteUrl) }

    private fun imageUrl(stored: String?): String? =
        TmdbImageUrls.resolve(stored, appSettings.current().tmdbImageBaseUrl)

    private fun maybeHydrateSeasonEpisodes(workId: Long, season: Season) {
        val seasonId = requireNotNull(season.id)
        val existing = episodes.findBySeasonIdOrderByEpisodeNumberAsc(seasonId)
        val expected = season.episodeCount
        val needsHydrate = existing.isEmpty() ||
            (expected != null && expected > 0 && existing.size < expected)
        if (!needsHydrate) return
        val tmdbId = tmdbIdsByWork(listOf(workId))[workId]?.toLongOrNull() ?: return
        if (!tmdb.configured()) return
        try {
            log.info(
                "季分集元数据不足，开始补全 workId={} season={} have={} expect={}",
                workId,
                season.seasonNumber,
                existing.size,
                expected,
            )
            seriesIngest.refreshSeason(tmdbId, season.seasonNumber)
        } catch (ex: ProviderException) {
            log.warn(
                "补全季分集失败 workId={} season={} status={}: {}",
                workId,
                season.seasonNumber,
                ex.status,
                ex.message,
            )
        } catch (ex: RuntimeException) {
            log.warn("补全季分集失败 workId={} season={}: {}", workId, season.seasonNumber, ex.message)
        }
    }

    private fun toSeasonView(
        season: Season,
        episodeRows: List<Episode>,
        includeEpisodes: Boolean,
        preloadedSeasonArtworks: List<Artwork>?,
        filesByEpisode: Map<Long, List<ReviewFileRow>> = emptyMap(),
        localEpisodeCount: Int? = null,
    ): SeasonView {
        val seasonId = requireNotNull(season.id)
        val episodeViews = if (!includeEpisodes) {
            emptyList()
        } else {
            episodeRows.map { episode ->
                val episodeId = requireNotNull(episode.id)
                EpisodeView(
                    episodeId,
                    episode.episodeNumber,
                    episode.absoluteNumber,
                    episode.title,
                    episode.overview,
                    episode.airDate,
                    episode.runtimeMinutes,
                    episode.voteAverage,
                    episode.voteCount,
                    artworkViews(OwnerType.episode, episodeId),
                    filesByEpisode[episodeId].orEmpty(),
                )
            }
        }
        val seasonArtworkViews = if (preloadedSeasonArtworks != null) {
            artworkViews(preloadedSeasonArtworks)
        } else {
            artworkViews(OwnerType.season, seasonId)
        }
        val localCount = localEpisodeCount ?: episodeRows.count { ep ->
            val id = ep.id ?: return@count false
            filesByEpisode[id]?.isNotEmpty() == true
        }
        return SeasonView(
            seasonId,
            season.seasonNumber,
            season.name,
            season.episodeCount,
            localCount,
            season.airDate,
            season.overview,
            seasonArtworkViews,
            episodeViews,
        )
    }

    private fun watchStates(ids: List<Long>): Map<Long, String> {
        if (ids.isEmpty()) return emptyMap()
        val userId = libraryAccess.currentUserId() ?: return emptyMap()
        val scope = resolveReadableScope(null) ?: return emptyMap()
        return browse.states(userId, ids, scope.restrict, scope.libraryIds)
    }

    private fun parseSearch(rawQuery: String?): ParsedSearch {
        val raw = rawQuery?.trim()?.ifBlank { null } ?: return ParsedSearch(null, null, null)
        val match = YEAR.find(raw) ?: return ParsedSearch(raw, raw, null)
        val year = match.value.toInt()
        val text = raw.removeRange(match.range).trim().replace(Regex("\\s+"), " ").ifBlank { null }
        return ParsedSearch(raw, text, year)
    }

    private fun tmdbMovieGenreNames(ids: List<Int>): List<String> =
        ids.mapNotNull { TMDB_MOVIE_GENRES[it] }.distinct()

    private data class ParsedSearch(val raw: String?, val text: String?, val year: Int?)

    private companion object {
        val YEAR = Regex("(?<!\\d)(?:19|20)\\d{2}(?!\\d)")

        // TMDB movie genre ids with zh-CN labels used by Folio.
        val TMDB_MOVIE_GENRES = mapOf(
            28 to "动作",
            12 to "冒险",
            16 to "动画",
            35 to "喜剧",
            80 to "犯罪",
            99 to "纪录片",
            18 to "剧情",
            10751 to "家庭",
            14 to "奇幻",
            36 to "历史",
            27 to "恐怖",
            10402 to "音乐",
            9648 to "悬疑",
            10749 to "爱情",
            878 to "科幻",
            10770 to "电视电影",
            53 to "惊悚",
            10752 to "战争",
            37 to "西部",
        )
    }

    /**
     * @return `null` 表示当前用户没有任何可读资料库；否则返回查询范围。
     * `restrict=false` 表示管理员不限制。
     */
    private fun resolveReadableScope(libraryId: Long?): LibraryScope? {
        val allowed = libraryAccess.readableLibraryIds()
        if (allowed == null) {
            return if (libraryId == null) {
                LibraryScope(restrict = false, libraryIds = listOf(-1L))
            } else {
                LibraryScope(restrict = true, libraryIds = listOf(libraryId))
            }
        }
        if (libraryId != null) {
            libraryAccess.requireRead(libraryId)
            return LibraryScope(restrict = true, libraryIds = listOf(libraryId))
        }
        if (allowed.isEmpty()) return null
        return LibraryScope(restrict = true, libraryIds = allowed.toList())
    }

    private data class LibraryScope(
        val restrict: Boolean,
        val libraryIds: Collection<Long>,
    )
}

