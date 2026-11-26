package com.scatl.folio.dto

data class MediaSegmentView(
    val kind: String,
    val startMs: Long,
    val endMs: Long?,
)

data class MediaSegmentsView(
    val segments: List<MediaSegmentView>,
)
