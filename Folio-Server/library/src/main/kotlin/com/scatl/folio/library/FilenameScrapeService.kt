package com.scatl.folio.library

import com.scatl.folio.catalog.CatalogService
import com.scatl.folio.settings.FolioSettings
import com.scatl.folio.catalog.SavedRef
import com.scatl.folio.parse.FilenameParser
import com.scatl.folio.parse.ParsedName
import com.scatl.folio.parse.TitleScore
import com.scatl.folio.provider.MediaHit
import com.scatl.folio.provider.RateLimitException
import com.scatl.folio.provider.TvdbLoginCoolingDown
import org.slf4j.LoggerFactory
import org.springframework.stereotype.Service
import java.util.Locale

@Service
open class FilenameScrapeService(
    private val jobs: ScrapeJobService,
    private val files: FileMatchService,
    private val parser: FilenameParser,
    private val tmdb: com.scatl.folio.provider.TmdbClient,
    private val tvdb: com.scatl.folio.provider.TvdbClient,
    private val catalog: CatalogService,
    private val seriesFetch: SeriesFetchCoordinator,
    private val seriesIngest: SeriesEpisodeIngest,
    private val aliases: SeriesTitleAliasService,
    private val appSettings: FolioSettings,
    private val omdbRatings: OmdbRatingService,
    private val fingerprints: FileFingerprintService,
) {
    private val log = LoggerFactory.getLogger(javaClass)

    fun match(jobId: Long): Boolean {
        val fileId = jobs.fileId(jobId) ?: run {
            log.info("刮削任务已不存在，停止 jobId={}", jobId)
            return true
        }
        val fileName = files.fileName(fileId)
        log.info("刮削开始 jobId={} fileId={} fileName={}", jobId, fileId, fileName)
        val started = System.nanoTime()

        jobs.progress(jobId, "解析文件名")
        val parseStarted = System.nanoTime()
        log.info("解析文件名开始 jobId={} fileName={}", jobId, fileName)
        val parsed = parser.parse(fileName)
        files.saveParsed(fileId, parsed)
        log.info(
            "解析文件名结束 jobId={} title={} year={} season={} episode={} imdbId={} 耗时={}ms",
            jobId,
            parsed.title,
            parsed.year,
            parsed.season,
            parsed.episode,
            parsed.imdbId,
            elapsedMs(parseStarted),
        )

        val knownFile = fingerprints.lookup(files.locator(fileId))
        if (knownFile?.second != null) {
            val saved = knownFile.second!!
            log.info(
                "文件特征值已存在，跳过 TMDB jobId={} fileId={} workId={} episodeId={}",
                jobId,
                fileId,
                saved.workId,
                saved.episodeId,
            )
            jobs.progress(jobId, "沿用已有文件")
            files.markMatched(fileId, saved.workId, saved.episodeId, 1.0, null)
            fingerprints.remember(fileId, saved.workId, saved.episodeId, knownFile.first)
            log.info(
                "刮削结束 jobId={} fileId={} outcome=matched source=fingerprint workId={} episodeId={} 总耗时={}ms",
                jobId,
                fileId,
                saved.workId,
                saved.episodeId,
                elapsedMs(started),
            )
            return true
        }

        if (!parsed.hasIdentity()) {
            log.warn("解析文件名失败 jobId={} reason=无法从文件名解析出标题 总耗时={}ms", jobId, elapsedMs(started))
            jobs.failPermanent(jobId, "无法从文件名解析出标题")
            return false
        }
        if (parsed.season == null && parsed.episode == null) {
            val knownId = catalog.findKnownMovie(parsed.title, parsed.year, parsed.imdbId)
            if (knownId != null) {
                log.info(
                    "电影已入库，跳过 TMDB jobId={} fileId={} workId={} title={} year={}",
                    jobId,
                    fileId,
                    knownId,
                    parsed.title,
                    parsed.year,
                )
                jobs.progress(jobId, "沿用已有电影资料")
                files.markMatched(fileId, knownId, null, 1.0, null)
                fingerprints.remember(fileId, knownId, null, knownFile?.first)
                log.info(
                    "刮削结束 jobId={} fileId={} outcome=matched source=local workId={} 总耗时={}ms",
                    jobId,
                    fileId,
                    knownId,
                    elapsedMs(started),
                )
                return true
            }
        }
        if (!tmdb.configured()) {
            log.error("刮削失败 jobId={} reason=TMDB API Key 未配置 总耗时={}ms", jobId, elapsedMs(started))
            jobs.failPermanent(jobId, "TMDB API Key 未配置")
            return false
        }

        val season = parsed.season
        val episode = parsed.episode
        val titleKey = TitleScore.key(parsed.title)
        val tmdbSelection = if (season != null && episode != null && titleKey.isNotEmpty()) {
            val decided = seriesFetch.callTitle(titleKey) {
                val known = aliases.find(parsed.title, parsed.catalogYear())
                if (known != null) {
                    log.info(
                        "沿用已匹配剧名 jobId={} title={} tmdbId={} workId={}",
                        jobId,
                        parsed.title,
                        known.tmdbId,
                        known.workId,
                    )
                    SeriesGate.Known(known.tmdbId)
                } else {
                    val selection = searchTmdb(jobId, parsed, season)
                    if (selection != null &&
                        selection.hit.kind != "movie" &&
                        selection.autoAcceptable(appSettings.current().matchAutoThreshold)
                    ) {
                        val ingest = ingestKnownSeries(
                            jobId,
                            selection.hit.id,
                            selection.hit.seasonNumber ?: season,
                            selection.hit.episodeNumber ?: episode,
                        )
                        aliases.remember(parsed.title, parsed.catalogYear(), ingest.saved.workId, selection.hit.id)
                        SeriesGate.Ingested(selection, ingest)
                    } else {
                        SeriesGate.Unresolved(selection)
                    }
                }
            }
            when (decided) {
                is SeriesGate.Known -> {
                    val selection = Selection(
                        MediaHit("series", decided.tmdbId, parsed.title, null, parsed.year, season, episode),
                        1.0,
                        true,
                    )
                    finishSeriesMatch(
                        jobId,
                        fileId,
                        parsed,
                        selection,
                        ingestKnownSeries(jobId, decided.tmdbId, season, episode),
                        started,
                    )
                    return true
                }
                is SeriesGate.Ingested -> {
                    finishSeriesMatch(jobId, fileId, parsed, decided.selection, decided.ingest, started)
                    return true
                }
                is SeriesGate.Unresolved -> decided.selection
            }
        } else {
            searchTmdb(jobId, parsed, season)
        }

        if (tmdbSelection != null && tmdbSelection.autoAcceptable(appSettings.current().matchAutoThreshold)) {
            acceptTmdbMatch(jobId, fileId, parsed, tmdbSelection, started)
            return true
        }

        if (tmdbSelection != null) {
            jobs.progress(jobId, "待人工确认")
            val message = reviewMessage(tmdbSelection)
            files.markReview(fileId, tmdbSelection.score, message)
            log.warn(
                "刮削结束 jobId={} fileId={} outcome=needs_review score={} reason={} 总耗时={}ms",
                jobId,
                fileId,
                String.format(Locale.ROOT, "%.4f", tmdbSelection.score),
                message,
                elapsedMs(started),
            )
            return true
        }
        jobs.progress(jobId, "无匹配结果")
        files.markFailed(fileId, "没有匹配结果")
        log.warn(
            "刮削结束 jobId={} fileId={} outcome=failed reason=没有匹配结果 总耗时={}ms",
            jobId,
            fileId,
            elapsedMs(started),
        )
        return true
    }

    private fun ingestKnownSeries(jobId: Long, tmdbId: Long, season: Int, episode: Int): SeriesIngest =
        seriesIngest.ingest(tmdbId, season, episode) {
            jobs.progress(jobId, "拉取 TMDB 详情")
        }

    private fun supplementRatings(workId: Long) {
        try {
            omdbRatings.enrichWork(workId)
        } catch (ex: RuntimeException) {
            log.warn("OMDb 评分补充失败 workId={} reason={}", workId, ex.message)
        }
    }

    private fun supplementFromTvdb(
        jobId: Long,
        workId: Long,
        parsed: ParsedName,
        kind: String,
        originalTitle: String?,
        season: Int?,
    ): String? {
        if (!tvdb.configured()) {
            log.info("TVDB 未配置，跳过补充 jobId={} workId={}", jobId, workId)
            return null
        }
        jobs.progress(jobId, "TVDB 补充元数据")
        log.info(
            "TVDB 补充开始 jobId={} workId={} kind={} title={} year={} season={}",
            jobId,
            workId,
            kind,
            parsed.title ?: originalTitle,
            parsed.year,
            season,
        )
        val started = System.nanoTime()
        return try {
            val query = parsed.title ?: originalTitle
            catalog.applySupplement(
                workId,
                tvdb.enrich(kind, query, parsed.catalogYear(), originalTitle, season),
            )
            log.info(
                "TVDB 补充结束 jobId={} workId={} 耗时={}ms",
                jobId,
                workId,
                elapsedMs(started),
            )
            null
        } catch (ex: TvdbLoginCoolingDown) {
            log.info("TVDB 登录冷却中，跳过补充 jobId={} workId={}", jobId, workId)
            null
        } catch (ex: RateLimitException) {
            log.warn("TVDB 补充触发限流 jobId={} workId={} delaySeconds={}", jobId, workId, ex.delaySeconds)
            throw ex
        } catch (ex: RuntimeException) {
            val message = "TheTVDB 补充失败：" + (ex.message ?: ex.javaClass.simpleName)
            log.warn(
                "TVDB 补充失败 jobId={} workId={} 耗时={}ms reason={}",
                jobId,
                workId,
                elapsedMs(started),
                ex.message,
            )
            message
        }
    }

    private fun finishSeriesMatch(
        jobId: Long,
        fileId: Long,
        parsed: ParsedName,
        selection: Selection,
        ingest: SeriesIngest,
        started: Long,
    ) {
        val season = parsed.season
        val episode = parsed.episode
        val saved = ingest.saved
        val work = ingest.work
        val note = if (ingest.reused || work == null) {
            null
        } else {
            supplementFromTvdb(jobId, saved.workId, parsed, work.kind, work.originalTitle, season)
        }
        if (work != null) {
            supplementRatings(saved.workId)
        }
        files.markMatched(
            fileId,
            saved.workId,
            saved.episodeId,
            selection.score,
            matchMessage(saved.episodeId, season, episode, note),
        )
        fingerprints.remember(fileId, saved.workId, saved.episodeId)
        log.info(
            "刮削结束 jobId={} fileId={} outcome=matched source=tmdb workId={} episodeId={} score={} 总耗时={}ms",
            jobId,
            fileId,
            saved.workId,
            saved.episodeId,
            String.format(Locale.ROOT, "%.4f", selection.score),
            elapsedMs(started),
        )
    }

    private sealed interface SeriesGate {
        data class Known(val tmdbId: Long) : SeriesGate
        data class Ingested(val selection: Selection, val ingest: SeriesIngest) : SeriesGate
        data class Unresolved(val selection: Selection?) : SeriesGate
    }

    private fun searchTmdb(jobId: Long, parsed: ParsedName, season: Int?): Selection? {
        jobs.progress(jobId, "搜索 TMDB")
        val searchStarted = System.nanoTime()
        log.info("TMDB 搜索开始 jobId={} title={} year={} season={}", jobId, parsed.title, parsed.year, season)
        val selection = selectTmdb(parsed)
        if (selection == null) {
            log.info("TMDB 搜索结束 jobId={} result=无匹配 耗时={}ms", jobId, elapsedMs(searchStarted))
        } else {
            log.info(
                "TMDB 搜索结束 jobId={} kind={} id={} title={} score={} certain={} ambiguous={} 耗时={}ms",
                jobId,
                selection.hit.kind,
                selection.hit.id,
                selection.hit.title ?: selection.hit.originalTitle,
                String.format(Locale.ROOT, "%.4f", selection.score),
                selection.certain,
                selection.ambiguous,
                elapsedMs(searchStarted),
            )
        }
        return selection
    }

    private fun acceptTmdbMatch(jobId: Long, fileId: Long, parsed: ParsedName, tmdbSelection: Selection, started: Long) {
        val season = parsed.season
        val episode = parsed.episode
        val hitSeason = tmdbSelection.hit.seasonNumber ?: season
        val hitEpisode = tmdbSelection.hit.episodeNumber ?: episode
        val saved: SavedRef
        val note: String?
        if (tmdbSelection.hit.kind != "movie" && hitSeason != null && hitEpisode != null) {
            val ingest = ingestKnownSeries(jobId, tmdbSelection.hit.id, hitSeason, hitEpisode)
            saved = ingest.saved
            note = if (ingest.reused) {
                null
            } else {
                val work = requireNotNull(ingest.work)
                supplementFromTvdb(jobId, saved.workId, parsed, work.kind, work.originalTitle, season)
            }
        } else {
            jobs.progress(jobId, "拉取 TMDB 详情")
            val detailStarted = System.nanoTime()
            log.info(
                "TMDB 详情拉取开始 jobId={} kind={} id={} season={}",
                jobId,
                tmdbSelection.hit.kind,
                tmdbSelection.hit.id,
                hitSeason,
            )
            val work = if (tmdbSelection.hit.kind == "movie") {
                tmdb.movie(tmdbSelection.hit.id)
            } else {
                tmdb.series(tmdbSelection.hit.id, hitSeason)
            }
            log.info(
                "TMDB 详情拉取结束 jobId={} title={} source={} 耗时={}ms",
                jobId,
                work.originalTitle,
                work.sourceProvider,
                elapsedMs(detailStarted),
            )

            jobs.progress(jobId, "写入目录")
            val saveStarted = System.nanoTime()
            log.info("目录入库开始 jobId={} source={}", jobId, work.sourceProvider)
            saved = catalog.save(work, hitSeason, hitEpisode)
            log.info(
                "目录入库结束 jobId={} workId={} episodeId={} 耗时={}ms",
                jobId,
                saved.workId,
                saved.episodeId,
                elapsedMs(saveStarted),
            )
            note = supplementFromTvdb(jobId, saved.workId, parsed, work.kind, work.originalTitle, season)
        }
        supplementRatings(saved.workId)
        if (tmdbSelection.hit.kind != "movie") {
            aliases.remember(parsed.title, parsed.catalogYear(), saved.workId, tmdbSelection.hit.id)
        }
        files.markMatched(
            fileId,
            saved.workId,
            saved.episodeId,
            tmdbSelection.score,
            matchMessage(saved.episodeId, season, episode, note),
        )
        fingerprints.remember(fileId, saved.workId, saved.episodeId)
        log.info(
            "刮削结束 jobId={} fileId={} outcome=matched source=tmdb workId={} episodeId={} score={} 总耗时={}ms",
            jobId,
            fileId,
            saved.workId,
            saved.episodeId,
            String.format(Locale.ROOT, "%.4f", tmdbSelection.score),
            elapsedMs(started),
        )
    }

    private fun selectTmdb(parsed: ParsedName): Selection? {
        if (parsed.imdbId != null) {
            val hit = pickImdb(tmdb.findByImdb(parsed.imdbId), parsed) ?: return null
            return Selection(hit, 1.0, certain = true)
        }
        if (parsed.season != null) {
            val year = parsed.catalogYear()
            val hits = tmdb.searchSeries(parsed.title ?: "", year)
            val ranked = withLocalizedScore(score(hits, parsed), parsed, year, series = true)
            if (ranked != null && ranked.autoAcceptable(appSettings.current().matchAutoThreshold)) return ranked
            return boostByAlternativeTitles(hits, parsed, ranked)
        }
        val movie = withLocalizedScore(
            score(tmdb.searchMovies(parsed.title ?: "", parsed.year), parsed),
            parsed,
            parsed.year,
            series = false,
        )
        if (movie != null && movie.autoAcceptable(appSettings.current().matchAutoThreshold)) return movie
        val series = withLocalizedScore(
            score(tmdb.searchSeries(parsed.title ?: "", parsed.year), parsed),
            parsed,
            parsed.year,
            series = true,
        )
        return when {
            movie == null -> series
            series == null -> movie
            series.score > movie.score -> series
            movie.score > series.score -> movie
            else -> movie.copy(ambiguous = true)
        }
    }

    private fun boostByAlternativeTitles(hits: List<MediaHit>, parsed: ParsedName, current: Selection?): Selection? {
        var best = current
        for (hit in hits.take(ALT_TITLE_CANDIDATES)) {
            val titles = tmdb.alternativeTitles(hit.id)
            val altScore = titles.maxOfOrNull { TitleScore.of(parsed.title, parsed.catalogYear(), it, null, hit.year) } ?: continue
            val official = TitleScore.of(parsed.title, parsed.catalogYear(), hit.title, hit.originalTitle, hit.year)
            val combined = maxOf(altScore, official)
            when {
                best == null || combined > best.score -> {
                    best = Selection(hit, combined, certain = false)
                    log.info(
                        "剧集别名得分 tmdbId={} title={} score={}",
                        hit.id,
                        hit.title ?: hit.originalTitle,
                        String.format(Locale.ROOT, "%.4f", combined),
                    )
                }
                combined == best.score && best.hit.id != hit.id -> {
                    best = best.copy(ambiguous = true)
                }
            }
        }
        return best
    }

    private fun withLocalizedScore(current: Selection?, parsed: ParsedName, year: Int?, series: Boolean): Selection? {
        val settings = appSettings.current()
        val title = parsed.title?.trim().orEmpty()
        if (
            title.isEmpty() ||
            !TitleScore.needsLocalizedSearch(title) ||
            settings.tmdbLanguage.equals(settings.tmdbSearchLanguage, ignoreCase = true) ||
            (current != null && current.autoAcceptable(settings.matchAutoThreshold))
        ) {
            return current
        }
        val hits = if (series) {
            tmdb.searchSeries(title, year, settings.tmdbLanguage)
        } else {
            tmdb.searchMovies(title, year, settings.tmdbLanguage)
        }
        val localized = score(hits, parsed) ?: return current
        if (!preferLocalized(current, localized)) return current
        log.info(
            "界面语言补搜命中 language={} kind={} tmdbId={} title={} score={} ambiguous={}",
            settings.tmdbLanguage,
            if (series) "series" else "movie",
            localized.hit.id,
            localized.hit.title ?: localized.hit.originalTitle,
            String.format(Locale.ROOT, "%.4f", localized.score),
            localized.ambiguous,
        )
        return localized
    }

    /** 补搜结果更好：分数更高，或同分但解开了并列歧义。 */
    private fun preferLocalized(current: Selection?, localized: Selection): Boolean {
        if (current == null) return true
        if (localized.score > current.score) return true
        if (localized.score < current.score) return false
        return current.ambiguous && !localized.ambiguous
    }

    private fun score(hits: List<MediaHit>, parsed: ParsedName): Selection? {
        if (hits.isEmpty()) return null
        val ranked = hits.map { hit ->
            hit to TitleScore.of(parsed.title, parsed.catalogYear(), hit.title, hit.originalTitle, hit.year)
        }
        val bestScore = ranked.maxOf { it.second }
        val top = ranked.filter { it.second == bestScore }
        val hit = top.first().first
        return Selection(hit, bestScore, certain = false, ambiguous = top.size > 1)
    }

    private fun pickImdb(hits: List<MediaHit>, parsed: ParsedName): MediaHit? {
        val series = parsed.season != null || hits.any { it.seasonNumber != null }
        return if (series) {
            hits.filter { it.kind == "series" }.maxByOrNull { it.episodeNumber != null }
        } else {
            hits.firstOrNull { it.kind == "movie" } ?: hits.firstOrNull { it.kind == "series" }
        }
    }

    private fun reviewMessage(selection: Selection): String {
        val title = selection.hit.title ?: selection.hit.originalTitle
        val year = selection.hit.year?.let { " ($it)" } ?: ""
        val score = String.format(Locale.ROOT, "%.2f", selection.score)
        if (selection.ambiguous) {
            return "存在多个相同相似度的候选，最接近的是 $title$year，相似度 $score，请人工确认"
        }
        return "未达到自动匹配阈值，最接近的是 $title$year，相似度 $score"
    }

    private fun matchMessage(episodeId: Long?, season: Int?, episode: Int?, note: String?): String? {
        val missingEpisode = if (episodeId == null && season != null && episode != null) {
            "已匹配剧集，但没有找到对应单集"
        } else {
            null
        }
        return join(note, missingEpisode)
    }

    private fun join(first: String?, second: String?): String? = when {
        first.isNullOrBlank() -> second
        second.isNullOrBlank() -> first
        else -> "$first;$second"
    }

    private fun elapsedMs(started: Long): Long = (System.nanoTime() - started) / 1_000_000

    private data class Selection(
        val hit: MediaHit,
        val score: Double,
        val certain: Boolean,
        val ambiguous: Boolean = false,
    ) {
        fun autoAcceptable(threshold: Double): Boolean =
            !ambiguous && (certain || score >= threshold)
    }

    private companion object {
        const val ALT_TITLE_CANDIDATES = 3
    }
}
