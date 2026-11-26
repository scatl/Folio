CREATE TABLE playback_progress (
    id BIGINT NOT NULL AUTO_INCREMENT,
    user_id BIGINT NOT NULL,
    library_file_id BIGINT NOT NULL,
    work_id BIGINT NULL,
    episode_id BIGINT NULL,
    position_ms BIGINT NOT NULL,
    duration_ms BIGINT NULL,
    completed TINYINT(1) NOT NULL DEFAULT 0,
    updated_at DATETIME(6) NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_playback_user_file (user_id, library_file_id),
    KEY idx_playback_user_updated (user_id, updated_at DESC),
    KEY idx_playback_user_work_updated (user_id, work_id, updated_at DESC),
    CONSTRAINT fk_playback_user FOREIGN KEY (user_id) REFERENCES app_users (id) ON DELETE CASCADE,
    CONSTRAINT fk_playback_file FOREIGN KEY (library_file_id) REFERENCES library_files (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
