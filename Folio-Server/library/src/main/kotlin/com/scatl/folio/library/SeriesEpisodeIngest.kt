package com.scatl.folio.library

import com.scatl.folio.catalog.CatalogService
import com.scatl.folio.catalog.ExternalProvider
import com.scatl.folio.catalog.SavedRef
import com.scatl.folio.provider.CanonicalWork
import com.scatl.folio.provider.TmdbClient
import org.slf4j.LoggerFactory
import org.springframework.stereotype.Service
import java.time.Duration

@Service
class SeriesEpisodeIngest(
    private val tmdb: TmdbClient,
    private val catalog: CatalogService,
    private val seriesFetch: SeriesFetchCoordinator,
) {
    private val log = LoggerFactory.getLogger(javaClass)

    /**
     * 同一次刮削里，一部剧只请求一次，后面的集直接复用。
     * 这一集已经入库时，只刷新剧级资料，不重下每一集。
     * 这一集还没入库时，才拉该季的单集详情。
     */
    fun ingest(tmdbId: Long, season: Int, episode: Int, refresh: Boolean = false, onFetch: () -> Unit = {}): SeriesIngest =
        seriesFetch.call(tmdbId) {
            val existing = catalog.findSavedEpisode(ExternalProvider.tmdb, tmdbId.toString(), season, episode)
            val recent = seriesFetch.refreshedRecently(tmdbId, SHOW_REFRESH_WINDOW)
            if (existing != null && recent && !refresh) {
                log.info(
                    "剧集已在本次刷新内，跳过详情 tmdbId={} season={} episode={} workId={} episodeId={}",
                    tmdbId,
                    season,
                    episode,
                    existing.workId,
                    existing.episodeId,
                )
                return@call SeriesIngest(existing, true, null)
            }
            onFetch()
            if (existing != null) {
                log.info("刷新剧集资料，不重下单集 tmdbId={} season={} episode={} refresh={}", tmdbId, season, episode, refresh)
                val started = System.nanoTime()
                val work = tmdb.series(tmdbId, null)
                val saved = catalog.save(work, season, episode)
                seriesFetch.markRefreshed(tmdbId)
                log.info(
                    "剧集资料已更新 tmdbId={} workId={} 耗时={}ms",
                    tmdbId,
                    saved.workId,
                    elapsedMs(started),
                )
                return@call SeriesIngest(saved, true, work)
            }
            log.info("拉取剧集详情 tmdbId={} season={} episode={}", tmdbId, season, episode)
            val started = System.nanoTime()
            val work = tmdb.series(tmdbId, season)
            val saved = catalog.save(work, season, episode)
            seriesFetch.markRefreshed(tmdbId)
            log.info(
                "剧集详情已入库 tmdbId={} title={} workId={} episodeId={} 耗时={}ms",
                tmdbId,
                work.originalTitle,
                saved.workId,
                saved.episodeId,
                elapsedMs(started),
            )
            SeriesIngest(saved, false, work)
        }

    /** 人工匹配整部剧时，重写这一季的每一集，不用「已入库则跳过单集」的刮削捷径。 */
    fun refreshSeason(tmdbId: Long, season: Int): SeriesIngest =
        seriesFetch.call(tmdbId) {
            log.info("人工匹配刷新整季 tmdbId={} season={}", tmdbId, season)
            val started = System.nanoTime()
            val work = tmdb.series(tmdbId, season)
            val saved = catalog.save(work, season, null)
            seriesFetch.markRefreshed(tmdbId)
            log.info(
                "人工匹配整季已写入 tmdbId={} season={} title={} workId={} 耗时={}ms",
                tmdbId,
                season,
                work.originalTitle,
                saved.workId,
                elapsedMs(started),
            )
            SeriesIngest(saved, false, work)
        }

    private fun elapsedMs(started: Long): Long = (System.nanoTime() - started) / 1_000_000

    private companion object {
        val SHOW_REFRESH_WINDOW: Duration = Duration.ofMinutes(10)
    }
}

data class SeriesIngest(val saved: SavedRef, val reused: Boolean, val work: CanonicalWork?)
