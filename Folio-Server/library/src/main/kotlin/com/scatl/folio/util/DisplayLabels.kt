package com.scatl.folio.util

object DisplayLabels {
    private val workStatusLabels = mapOf(
        "Rumored" to "传闻",
        "Planned" to "计划中",
        "In Production" to "制作中",
        "Post Production" to "后期制作",
        "Released" to "已上映",
        "Canceled" to "已取消",
        "Cancelled" to "已取消",
        "Returning" to "连载中",
        "Returning Series" to "连载中",
        "Ended" to "已完结",
        "Pilot" to "试播",
    )

    private val showTypeLabels = mapOf(
        "Scripted" to "剧本剧",
        "Reality" to "真人秀",
        "Documentary" to "纪录片",
        "News" to "新闻",
        "Talk" to "访谈",
        "Miniseries" to "迷你剧",
        "Video" to "影像节目",
    )

    fun workStatus(value: String?): String? = value?.let { workStatusLabels[it] ?: it }

    fun showType(value: String?): String? = value?.let { showTypeLabels[it] ?: it }
}
