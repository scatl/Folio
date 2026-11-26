CREATE TABLE media_segment_cache (
    id BIGINT NOT NULL AUTO_INCREMENT,
    work_id BIGINT NOT NULL,
    season_number INT NOT NULL,
    episode_number INT NOT NULL,
    duration_bucket INT NOT NULL,
    payload TEXT NOT NULL,
    empty_result TINYINT(1) NOT NULL,
    fetched_at DATETIME(6) NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_media_segment_lookup (work_id, season_number, episode_number, duration_bucket),
    CONSTRAINT fk_media_segment_work FOREIGN KEY (work_id) REFERENCES works (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
