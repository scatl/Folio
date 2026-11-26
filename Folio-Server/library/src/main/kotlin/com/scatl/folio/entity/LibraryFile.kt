package com.scatl.folio.entity

import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.EnumType
import jakarta.persistence.Enumerated
import jakarta.persistence.FetchType
import jakarta.persistence.GeneratedValue
import jakarta.persistence.GenerationType
import jakarta.persistence.Id
import jakarta.persistence.JoinColumn
import jakarta.persistence.ManyToOne
import jakarta.persistence.Table
import org.hibernate.annotations.DynamicUpdate
import java.math.BigDecimal
import java.time.Instant

@Entity
@Table(name = "library_files")
@DynamicUpdate
open class LibraryFile {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    open var id: Long? = null

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "media_library_id")
    open var mediaLibrary: MediaLibrary? = null

    @Column(nullable = false, length = 1024)
    open var locator: String = ""

    @Column(name = "locator_hash", nullable = false, length = 64)
    open var locatorHash: String = ""

    @Column(name = "file_name", nullable = false, length = 512)
    open var fileName: String = ""

    @Column(name = "file_size")
    open var fileSize: Long? = null

    @Column(name = "source_modified_at")
    open var sourceModifiedAt: Instant? = null

    @Column(name = "media_container", length = 32)
    open var mediaContainer: String? = null

    @Column(name = "duration_ms")
    open var durationMs: Long? = null

    @Column(name = "video_codec", length = 64)
    open var videoCodec: String? = null

    @Column(name = "video_width")
    open var videoWidth: Int? = null

    @Column(name = "video_height")
    open var videoHeight: Int? = null

    @Column(name = "video_frame_rate", precision = 10, scale = 3)
    open var videoFrameRate: BigDecimal? = null

    @Column(name = "video_bitrate")
    open var videoBitrate: Long? = null

    @Column(name = "video_bit_depth")
    open var videoBitDepth: Int? = null

    @Column(name = "video_dynamic_range", length = 32)
    open var videoDynamicRange: String? = null

    @Column(name = "video_profile", length = 64)
    open var videoProfile: String? = null

    @Column(name = "video_pixel_format", length = 64)
    open var videoPixelFormat: String? = null

    @Column(name = "audio_tracks", columnDefinition = "TEXT")
    open var audioTracks: String? = null

    @Column(name = "subtitle_tracks", columnDefinition = "TEXT")
    open var subtitleTracks: String? = null

    @Column(name = "probed_at")
    open var probedAt: Instant? = null

    @Column(name = "fingerprinted_at")
    open var fingerprintedAt: Instant? = null

    @Column(name = "parsed_title", length = 512)
    open var parsedTitle: String? = null

    @Column(name = "parsed_year")
    open var parsedYear: Int? = null

    @Column(name = "parsed_season")
    open var parsedSeason: Int? = null

    @Column(name = "parsed_episode")
    open var parsedEpisode: Int? = null

    @Column(name = "parsed_imdb_id", length = 16)
    open var parsedImdbId: String? = null

    @Enumerated(EnumType.STRING)
    @Column(name = "match_status", nullable = false, length = 32)
    open var matchStatus: MatchStatus = MatchStatus.pending

    @Column(precision = 6, scale = 4)
    open var confidence: BigDecimal? = null

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "work_id")
    open var work: Work? = null

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "episode_id")
    open var episode: Episode? = null

    @Column(length = 1024)
    open var message: String? = null

    @Column(name = "created_at", nullable = false)
    open var createdAt: Instant = Instant.EPOCH

    @Column(name = "updated_at", nullable = false)
    open var updatedAt: Instant = Instant.EPOCH
}
