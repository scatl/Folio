package com.scatl.folio.playlist

import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.GeneratedValue
import jakarta.persistence.GenerationType
import jakarta.persistence.Id
import jakarta.persistence.Table

@Entity
@Table(name = "playlist_items")
open class PlaylistItem {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    open var id: Long? = null

    @Column(name = "playlist_id", nullable = false)
    open var playlistId: Long = 0

    @Column(name = "work_id", nullable = false)
    open var workId: Long = 0

    @Column(nullable = false)
    open var position: Int = 0
}
