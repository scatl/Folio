package com.scatl.folio.repository

import com.scatl.folio.entity.SeriesTitleAlias
import org.springframework.data.jpa.repository.JpaRepository

interface SeriesTitleAliasRepository : JpaRepository<SeriesTitleAlias, Long> {
    fun findByTitleKey(titleKey: String): SeriesTitleAlias?
}
