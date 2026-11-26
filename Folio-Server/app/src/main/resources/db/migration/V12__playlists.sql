CREATE TABLE playlists (
    id BIGINT NOT NULL AUTO_INCREMENT,
    user_id BIGINT NOT NULL,
    name VARCHAR(40) NOT NULL,
    created_at DATETIME(6) NOT NULL,
    updated_at DATETIME(6) NOT NULL,
    PRIMARY KEY (id),
    KEY idx_playlists_user_updated (user_id, updated_at DESC),
    CONSTRAINT fk_playlists_user FOREIGN KEY (user_id) REFERENCES app_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE playlist_items (
    id BIGINT NOT NULL AUTO_INCREMENT,
    playlist_id BIGINT NOT NULL,
    work_id BIGINT NOT NULL,
    position INT NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_playlist_item_work (playlist_id, work_id),
    KEY idx_playlist_item_order (playlist_id, position),
    CONSTRAINT fk_playlist_item_playlist FOREIGN KEY (playlist_id) REFERENCES playlists (id) ON DELETE CASCADE,
    CONSTRAINT fk_playlist_item_work FOREIGN KEY (work_id) REFERENCES works (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
