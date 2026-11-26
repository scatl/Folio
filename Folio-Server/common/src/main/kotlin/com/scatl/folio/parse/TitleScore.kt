package com.scatl.folio.parse

import java.util.Locale

object TitleScore {
    fun of(query: String?, queryYear: Int?, title: String?, originalTitle: String?, candidateYear: Int?): Double {
        var text = maxOf(similarity(query, title), similarity(query, originalTitle))
        if (queryYear != null && candidateYear != null) {
            val diff = kotlin.math.abs(queryYear - candidateYear)
            text += when (diff) {
                0 -> 0.05
                1 -> -0.05
                else -> -0.35
            }
        }
        return text.coerceIn(0.0, 1.0)
    }

    fun key(value: String?): String = normalize(value)

    /** 标题含汉字、假名或谚文时，英文搜索结果对不上文件名，需要再用界面语言搜一次。 */
    fun needsLocalizedSearch(value: String?): Boolean {
        if (value.isNullOrBlank()) return false
        var index = 0
        while (index < value.length) {
            val script = Character.UnicodeScript.of(value.codePointAt(index))
            if (
                script == Character.UnicodeScript.HAN ||
                script == Character.UnicodeScript.HIRAGANA ||
                script == Character.UnicodeScript.KATAKANA ||
                script == Character.UnicodeScript.HANGUL
            ) {
                return true
            }
            index += Character.charCount(value.codePointAt(index))
        }
        return false
    }

    internal fun similarity(left: String?, right: String?): Double {
        var a = normalize(left)
        var b = normalize(right)
        if (a.isEmpty() || b.isEmpty()) {
            return 0.0
        }
        if (a == b) {
            return 1.0
        }
        if (a.length > 80) {
            a = a.substring(0, 80)
        }
        if (b.length > 80) {
            b = b.substring(0, 80)
        }
        val distance = levenshtein(a, b)
        return 1.0 - distance.toDouble() / maxOf(a.length, b.length)
    }

    private fun normalize(value: String?): String {
        if (value == null) {
            return ""
        }
        val normalized = StringBuilder()
        var index = 0
        while (index < value.length) {
            val point = value.codePointAt(index)
            if (Character.isLetterOrDigit(point)) {
                normalized.appendCodePoint(Character.toLowerCase(point))
            }
            index += Character.charCount(point)
        }
        return normalized.toString().lowercase(Locale.ROOT)
    }

    private fun levenshtein(left: String, right: String): Int {
        var previous = IntArray(right.length + 1) { it }
        var current = IntArray(right.length + 1)
        for (i in 1..left.length) {
            current[0] = i
            for (j in 1..right.length) {
                val cost = if (left[i - 1] == right[j - 1]) 0 else 1
                current[j] = minOf(current[j - 1] + 1, previous[j] + 1, previous[j - 1] + cost)
            }
            val swap = previous
            previous = current
            current = swap
        }
        return previous[right.length]
    }
}
