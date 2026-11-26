package com.scatl.folio.dto

data class RankedCandidate(
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
