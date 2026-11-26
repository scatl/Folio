package com.scatl.folio.library

import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class LibraryPathsSubtitleTest {
    @Test
    fun subtitleExtensions() {
        assertTrue(LibraryPaths.isSubtitleFileName("a.srt"))
        assertTrue(LibraryPaths.isSubtitleFileName("a.CHS.ASS"))
        assertFalse(LibraryPaths.isSubtitleFileName("a.mkv"))
        assertFalse(LibraryPaths.isSubtitleFileName("a"))
    }

    @Test
    fun rejectsPathTraversalNames() {
        assertTrue(LibraryPaths.isSafeSiblingSubtitleName("movie.srt"))
        assertFalse(LibraryPaths.isSafeSiblingSubtitleName("../movie.srt"))
        assertFalse(LibraryPaths.isSafeSiblingSubtitleName("a/b.srt"))
        assertFalse(LibraryPaths.isSafeSiblingSubtitleName("a\\b.srt"))
        assertFalse(LibraryPaths.isSafeSiblingSubtitleName("movie.mkv"))
    }
}
