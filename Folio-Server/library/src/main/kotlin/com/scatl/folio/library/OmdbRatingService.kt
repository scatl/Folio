package com.scatl.folio.library

import com.scatl.folio.catalog.CatalogService
import com.scatl.folio.catalog.ExternalProvider
import com.scatl.folio.catalog.OwnerType
import com.scatl.folio.provider.OmdbClient
import com.scatl.folio.repository.ExternalIdRepository
import com.scatl.folio.repository.WorkRepository
import org.slf4j.LoggerFactory
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Propagation
import org.springframework.transaction.annotation.Transactional

@Service
open class OmdbRatingService(
    private val omdb: OmdbClient,
    private val catalog: CatalogService,
    private val externalIds: ExternalIdRepository,
    private val works: WorkRepository,
) {
    private val log = LoggerFactory.getLogger(javaClass)

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    open fun enrichWork(workId: Long, force: Boolean = false) {
        if (!omdb.configured()) return
        val imdbId = externalIds.findByOwnerTypeAndOwnerIdOrderByProviderAsc(OwnerType.work, workId)
            .firstOrNull { it.provider == ExternalProvider.imdb }
            ?.externalId
            ?.trim()
            .orEmpty()
        if (imdbId.isEmpty()) return
        val work = works.findById(workId).orElse(null) ?: return
        if (!force && work.awards != null) return
        val payload = omdb.enrich(imdbId) ?: return
        catalog.applyOmdb(workId, payload.ratings, payload.awards, payload.tomatoUrl)
        log.info(
            "OMDb 已写入 workId={} imdbId={} ratings={} awards={}",
            workId,
            imdbId,
            payload.ratings.size,
            payload.awards.isNotEmpty(),
        )
    }
}
