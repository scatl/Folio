package com.scatl.folio.parse

data class ParsedName(
    val title: String?,
    val year: Int?,
    val season: Int?,
    val episode: Int?,
    val imdbId: String?,
) {
    fun hasIdentity(): Boolean = !title.isNullOrBlank() || imdbId != null

    /** 单集文件名里的年份通常是播出年，不能当作剧集开播年去搜索。 */
    fun catalogYear(): Int? = if (season != null || episode != null) null else year
}
