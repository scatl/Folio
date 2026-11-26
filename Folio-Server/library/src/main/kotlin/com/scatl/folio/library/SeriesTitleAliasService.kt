package com.scatl.folio.library

import com.scatl.folio.catalog.ExternalProvider
import com.scatl.folio.catalog.OwnerType
import com.scatl.folio.entity.SeriesTitleAlias
import com.scatl.folio.parse.TitleScore
import com.scatl.folio.repository.ExternalIdRepository
import com.scatl.folio.repository.LibraryFileRepository
import com.scatl.folio.repository.SeriesTitleAliasRepository
import org.springframework.dao.DataIntegrityViolationException
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional

data class KnownSeries(
    val workId: Long,
    val tmdbId: Long,
)

@Service
open class SeriesTitleAliasService(
    private val aliases: SeriesTitleAliasRepository,
    private val files: LibraryFileRepository,
    private val externalIds: ExternalIdRepository,
) {
    @Transactional
    open fun find(title: String?, year: Int?): KnownSeries? {
        val key = TitleScore.key(title)
        if (key.isEmpty()) return null
        aliases.findByTitleKey(key)?.let { row ->
            if (!yearCompatible(row.releaseYear, year)) return null
            val tmdbId = row.tmdbId.toLongOrNull() ?: return null
            return KnownSeries(row.workId, tmdbId)
        }
        val learned = learnFromMatchedFiles(key, year) ?: return null
        remember(title, learned.year, learned.workId, learned.tmdbId)
        return KnownSeries(learned.workId, learned.tmdbId)
    }

    @Transactional
    open fun remember(title: String?, year: Int?, workId: Long, tmdbId: Long) {
        val key = TitleScore.key(title)
        if (key.isEmpty()) return
        val existing = aliases.findByTitleKey(key)
        if (existing == null) {
            try {
                aliases.saveAndFlush(SeriesTitleAlias().apply {
                    titleKey = key
                    releaseYear = year
                    this.workId = workId
                    this.tmdbId = tmdbId.toString()
                })
            } catch (_: DataIntegrityViolationException) {
                val raced = aliases.findByTitleKey(key) ?: return
                raced.workId = workId
                raced.tmdbId = tmdbId.toString()
                if (year != null) raced.releaseYear = year
                aliases.save(raced)
            }
            return
        }
        if (existing.releaseYear != null && year != null && existing.releaseYear != year) return
        existing.workId = workId
        existing.tmdbId = tmdbId.toString()
        if (year != null) existing.releaseYear = year
        aliases.save(existing)
    }

    private data class Learned(val workId: Long, val tmdbId: Long, val year: Int?)

    private fun learnFromMatchedFiles(key: String, year: Int?): Learned? {
        val sameTitle = files.findMatchedSeriesFiles().filter { TitleScore.key(it.parsedTitle) == key }
        val pool = when {
            year != null && sameTitle.any { it.parsedYear == year } ->
                sameTitle.filter { it.parsedYear == null || it.parsedYear == year }
            year != null && sameTitle.any { it.parsedYear != null } -> emptyList()
            else -> sameTitle
        }
        val counts = pool.groupBy { it.work?.id }.filterKeys { it != null }
        if (counts.isEmpty()) return null
        val most = counts.maxOf { it.value.size }
        val winners = counts.filter { it.value.size == most }.keys
        if (winners.size != 1) return null
        val workId = winners.first() ?: return null
        val tmdbId = externalIds.findByOwnerTypeAndOwnerIdOrderByProviderAsc(OwnerType.work, workId)
            .firstOrNull { it.provider == ExternalProvider.tmdb }
            ?.externalId
            ?.toLongOrNull()
            ?: return null
        val learnedYear = year ?: pool.mapNotNull { it.parsedYear }.groupingBy { it }.eachCount().maxByOrNull { it.value }?.key
        return Learned(workId, tmdbId, learnedYear)
    }

    private fun yearCompatible(stored: Int?, incoming: Int?): Boolean =
        stored == null || incoming == null || stored == incoming
}
