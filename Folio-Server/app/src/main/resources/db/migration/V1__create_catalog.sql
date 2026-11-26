CREATE TABLE works (
    id BIGINT NOT NULL AUTO_INCREMENT,
    kind VARCHAR(16) NOT NULL,
    original_title VARCHAR(512) NOT NULL,
    original_language VARCHAR(16) NULL,
    release_year INT NULL,
    premiere_date DATE NULL,
    runtime_minutes INT NULL,
    work_status VARCHAR(64) NULL,
    homepage VARCHAR(1024) NULL,
    popularity DECIMAL(12, 3) NULL,
    budget BIGINT NULL,
    revenue BIGINT NULL,
    adult BIT(1) NULL,
    show_type VARCHAR(64) NULL,
    in_production BIT(1) NULL,
    last_air_date DATE NULL,
    number_of_seasons INT NULL,
    number_of_episodes INT NULL,
    collection_external_id VARCHAR(64) NULL,
    collection_name VARCHAR(512) NULL,
    awards VARCHAR(1024) NULL,
    source_provider VARCHAR(16) NOT NULL,
    created_at DATETIME(6) NOT NULL,
    updated_at DATETIME(6) NOT NULL,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE work_translations (
    id BIGINT NOT NULL AUTO_INCREMENT,
    work_id BIGINT NOT NULL,
    locale VARCHAR(16) NOT NULL,
    title VARCHAR(512) NOT NULL,
    overview TEXT NULL,
    tagline VARCHAR(1024) NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_work_translation (work_id, locale),
    CONSTRAINT fk_work_translation_work FOREIGN KEY (work_id) REFERENCES works (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE seasons (
    id BIGINT NOT NULL AUTO_INCREMENT,
    work_id BIGINT NOT NULL,
    season_number INT NOT NULL,
    name VARCHAR(512) NULL,
    episode_count INT NULL,
    air_date DATE NULL,
    overview TEXT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_season (work_id, season_number),
    CONSTRAINT fk_season_work FOREIGN KEY (work_id) REFERENCES works (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE episodes (
    id BIGINT NOT NULL AUTO_INCREMENT,
    work_id BIGINT NOT NULL,
    season_id BIGINT NOT NULL,
    episode_number INT NOT NULL,
    absolute_number INT NULL,
    title VARCHAR(512) NULL,
    overview TEXT NULL,
    air_date DATE NULL,
    runtime_minutes INT NULL,
    vote_average DECIMAL(6, 2) NULL,
    vote_count INT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_episode (season_id, episode_number),
    CONSTRAINT fk_episode_work FOREIGN KEY (work_id) REFERENCES works (id),
    CONSTRAINT fk_episode_season FOREIGN KEY (season_id) REFERENCES seasons (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE external_ids (
    id BIGINT NOT NULL AUTO_INCREMENT,
    owner_type VARCHAR(16) NOT NULL,
    owner_id BIGINT NOT NULL,
    provider VARCHAR(16) NOT NULL,
    external_id VARCHAR(64) NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_external_id (owner_type, provider, external_id),
    KEY idx_external_owner (owner_type, owner_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE people (
    id BIGINT NOT NULL AUTO_INCREMENT,
    provider VARCHAR(16) NOT NULL,
    provider_person_id VARCHAR(64) NOT NULL,
    name VARCHAR(512) NOT NULL,
    profile_url VARCHAR(1024) NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_person (provider, provider_person_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE credits (
    id BIGINT NOT NULL AUTO_INCREMENT,
    owner_type VARCHAR(16) NOT NULL,
    owner_id BIGINT NOT NULL,
    person_id BIGINT NOT NULL,
    department VARCHAR(64) NULL,
    job_name VARCHAR(64) NULL,
    character_name VARCHAR(512) NULL,
    sort_order INT NOT NULL,
    PRIMARY KEY (id),
    KEY idx_credit_owner (owner_type, owner_id),
    CONSTRAINT fk_credit_person FOREIGN KEY (person_id) REFERENCES people (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE ratings (
    id BIGINT NOT NULL AUTO_INCREMENT,
    owner_type VARCHAR(16) NOT NULL,
    owner_id BIGINT NOT NULL,
    provider VARCHAR(16) NOT NULL,
    score_value DECIMAL(6, 2) NOT NULL,
    votes INT NULL,
    score_scale DECIMAL(6, 2) NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_rating (owner_type, owner_id, provider)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE artworks (
    id BIGINT NOT NULL AUTO_INCREMENT,
    owner_type VARCHAR(16) NOT NULL,
    owner_id BIGINT NOT NULL,
    kind VARCHAR(32) NOT NULL,
    locale VARCHAR(16) NULL,
    provider VARCHAR(16) NOT NULL,
    remote_url VARCHAR(1024) NOT NULL,
    local_path VARCHAR(1024) NULL,
    PRIMARY KEY (id),
    KEY idx_artwork_owner (owner_type, owner_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE genres (
    id BIGINT NOT NULL AUTO_INCREMENT,
    provider VARCHAR(16) NOT NULL,
    external_id VARCHAR(64) NOT NULL,
    name VARCHAR(255) NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_genre (provider, external_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE work_genres (
    id BIGINT NOT NULL AUTO_INCREMENT,
    work_id BIGINT NOT NULL,
    genre_id BIGINT NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_work_genre (work_id, genre_id),
    CONSTRAINT fk_work_genre_work FOREIGN KEY (work_id) REFERENCES works (id),
    CONSTRAINT fk_work_genre_genre FOREIGN KEY (genre_id) REFERENCES genres (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE companies (
    id BIGINT NOT NULL AUTO_INCREMENT,
    provider VARCHAR(16) NOT NULL,
    external_id VARCHAR(64) NOT NULL,
    name VARCHAR(512) NOT NULL,
    origin_country VARCHAR(8) NULL,
    logo_url VARCHAR(1024) NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_company (provider, external_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE work_companies (
    id BIGINT NOT NULL AUTO_INCREMENT,
    work_id BIGINT NOT NULL,
    company_id BIGINT NOT NULL,
    company_role VARCHAR(32) NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_work_company (work_id, company_id, company_role),
    CONSTRAINT fk_work_company_work FOREIGN KEY (work_id) REFERENCES works (id),
    CONSTRAINT fk_work_company_company FOREIGN KEY (company_id) REFERENCES companies (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE work_countries (
    id BIGINT NOT NULL AUTO_INCREMENT,
    work_id BIGINT NOT NULL,
    country_code VARCHAR(8) NOT NULL,
    name VARCHAR(255) NULL,
    country_kind VARCHAR(16) NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_work_country (work_id, country_code, country_kind),
    CONSTRAINT fk_work_country_work FOREIGN KEY (work_id) REFERENCES works (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE work_languages (
    id BIGINT NOT NULL AUTO_INCREMENT,
    work_id BIGINT NOT NULL,
    language_code VARCHAR(16) NOT NULL,
    name VARCHAR(255) NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_work_language (work_id, language_code),
    CONSTRAINT fk_work_language_work FOREIGN KEY (work_id) REFERENCES works (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE keywords (
    id BIGINT NOT NULL AUTO_INCREMENT,
    provider VARCHAR(16) NOT NULL,
    external_id VARCHAR(64) NOT NULL,
    name VARCHAR(255) NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_keyword (provider, external_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE work_keywords (
    id BIGINT NOT NULL AUTO_INCREMENT,
    work_id BIGINT NOT NULL,
    keyword_id BIGINT NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_work_keyword (work_id, keyword_id),
    CONSTRAINT fk_work_keyword_work FOREIGN KEY (work_id) REFERENCES works (id),
    CONSTRAINT fk_work_keyword_keyword FOREIGN KEY (keyword_id) REFERENCES keywords (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE videos (
    id BIGINT NOT NULL AUTO_INCREMENT,
    owner_type VARCHAR(16) NOT NULL,
    owner_id BIGINT NOT NULL,
    provider VARCHAR(16) NOT NULL,
    external_id VARCHAR(64) NOT NULL,
    site VARCHAR(64) NULL,
    video_type VARCHAR(64) NULL,
    name VARCHAR(512) NULL,
    video_key VARCHAR(128) NULL,
    language VARCHAR(16) NULL,
    official BIT(1) NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_video (owner_type, provider, external_id),
    KEY idx_video_owner (owner_type, owner_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE media_libraries (
    id BIGINT NOT NULL AUTO_INCREMENT,
    name VARCHAR(128) NOT NULL,
    kind VARCHAR(16) NOT NULL,
    root_path VARCHAR(1024) NOT NULL,
    created_at DATETIME(6) NOT NULL,
    updated_at DATETIME(6) NOT NULL,
    PRIMARY KEY (id),
    KEY idx_media_library_kind (kind)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE library_files (
    id BIGINT NOT NULL AUTO_INCREMENT,
    media_library_id BIGINT NULL,
    locator VARCHAR(1024) NOT NULL,
    locator_hash CHAR(64) NOT NULL,
    file_name VARCHAR(512) NOT NULL,
    file_size BIGINT NULL,
    source_modified_at DATETIME(6) NULL,
    media_container VARCHAR(32) NULL,
    duration_ms BIGINT NULL,
    video_codec VARCHAR(64) NULL,
    video_width INT NULL,
    video_height INT NULL,
    video_frame_rate DECIMAL(10, 3) NULL,
    video_bitrate BIGINT NULL,
    video_bit_depth INT NULL,
    video_dynamic_range VARCHAR(32) NULL,
    audio_tracks TEXT NULL,
    subtitle_tracks TEXT NULL,
    probed_at DATETIME(6) NULL,
    fingerprinted_at DATETIME(6) NULL,
    parsed_title VARCHAR(512) NULL,
    parsed_year INT NULL,
    parsed_season INT NULL,
    parsed_episode INT NULL,
    parsed_imdb_id VARCHAR(16) NULL,
    match_status VARCHAR(32) NOT NULL,
    confidence DECIMAL(6, 4) NULL,
    work_id BIGINT NULL,
    episode_id BIGINT NULL,
    message VARCHAR(1024) NULL,
    created_at DATETIME(6) NOT NULL,
    updated_at DATETIME(6) NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_library_file_locator (media_library_id, locator_hash),
    KEY idx_library_file_media_library (media_library_id),
    CONSTRAINT fk_library_file_media_library FOREIGN KEY (media_library_id) REFERENCES media_libraries (id),
    CONSTRAINT fk_library_file_work FOREIGN KEY (work_id) REFERENCES works (id),
    CONSTRAINT fk_library_file_episode FOREIGN KEY (episode_id) REFERENCES episodes (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE scrape_jobs (
    id BIGINT NOT NULL AUTO_INCREMENT,
    library_file_id BIGINT NOT NULL,
    status VARCHAR(16) NOT NULL,
    attempts INT NOT NULL,
    max_attempts INT NOT NULL,
    next_run_at DATETIME(6) NOT NULL,
    last_error VARCHAR(1024) NULL,
    progress VARCHAR(255) NULL,
    created_at DATETIME(6) NOT NULL,
    updated_at DATETIME(6) NOT NULL,
    PRIMARY KEY (id),
    KEY idx_scrape_job_claim (status, next_run_at, id),
    CONSTRAINT fk_scrape_job_file FOREIGN KEY (library_file_id) REFERENCES library_files (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE provider_snapshots (
    id BIGINT NOT NULL AUTO_INCREMENT,
    provider VARCHAR(16) NOT NULL,
    resource_key VARCHAR(255) NOT NULL,
    body MEDIUMTEXT NOT NULL,
    fetched_at DATETIME(6) NOT NULL,
    PRIMARY KEY (id),
    KEY idx_provider_snapshot (provider, resource_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE series_title_aliases (
    id BIGINT NOT NULL AUTO_INCREMENT,
    title_key VARCHAR(512) NOT NULL,
    release_year INT NULL,
    work_id BIGINT NOT NULL,
    tmdb_id VARCHAR(32) NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_series_title_alias (title_key),
    CONSTRAINT fk_series_title_alias_work FOREIGN KEY (work_id) REFERENCES works (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE app_users (
    id BIGINT NOT NULL AUTO_INCREMENT,
    username VARCHAR(64) NOT NULL,
    password_hash VARCHAR(120) NOT NULL,
    created_at DATETIME(6) NOT NULL,
    updated_at DATETIME(6) NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_app_user_username (username)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE app_settings (
    id BIGINT NOT NULL,
    tmdb_api_key VARCHAR(256) NULL,
    tmdb_base_url VARCHAR(512) NOT NULL,
    tmdb_image_base_url VARCHAR(512) NOT NULL,
    tmdb_language VARCHAR(32) NOT NULL,
    tmdb_search_language VARCHAR(32) NOT NULL,
    tmdb_requests_per_second DOUBLE NOT NULL,
    tmdb_person_images VARCHAR(16) NOT NULL,
    omdb_api_key VARCHAR(256) NULL,
    omdb_base_url VARCHAR(512) NOT NULL,
    omdb_requests_per_second DOUBLE NOT NULL,
    tvdb_enabled TINYINT(1) NOT NULL,
    tvdb_api_key VARCHAR(256) NULL,
    tvdb_pin VARCHAR(128) NULL,
    tvdb_base_url VARCHAR(512) NOT NULL,
    tvdb_requests_per_second DOUBLE NOT NULL,
    http_timeout_seconds BIGINT NOT NULL,
    match_auto_threshold DOUBLE NOT NULL,
    worker_delay_ms BIGINT NOT NULL,
    worker_max_attempts INT NOT NULL,
    worker_concurrency INT NOT NULL,
    scan_interval_minutes INT NOT NULL,
    watch_enabled TINYINT(1) NOT NULL,
    updated_at DATETIME(6) NOT NULL,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO app_settings (
    id,
    tmdb_api_key,
    tmdb_base_url,
    tmdb_image_base_url,
    tmdb_language,
    tmdb_search_language,
    tmdb_requests_per_second,
    tmdb_person_images,
    omdb_api_key,
    omdb_base_url,
    omdb_requests_per_second,
    tvdb_enabled,
    tvdb_api_key,
    tvdb_pin,
    tvdb_base_url,
    tvdb_requests_per_second,
    http_timeout_seconds,
    match_auto_threshold,
    worker_delay_ms,
    worker_max_attempts,
    worker_concurrency,
    scan_interval_minutes,
    watch_enabled,
    updated_at
) VALUES (
    1,
    NULL,
    'https://api.tmdb.org/3',
    'https://image.tmdb.org/t/p/original',
    'zh-CN',
    'en-US',
    30,
    'credit',
    NULL,
    'https://www.omdbapi.com',
    30,
    0,
    NULL,
    NULL,
    'https://api4.thetvdb.com/v4',
    30,
    10,
    0.72,
    2000,
    3,
    8,
    10,
    1,
    CURRENT_TIMESTAMP(6)
);

CREATE TABLE file_fingerprints (
    id BIGINT NOT NULL AUTO_INCREMENT,
    file_size BIGINT NOT NULL,
    content_hash CHAR(64) NOT NULL,
    work_id BIGINT NOT NULL,
    episode_id BIGINT NULL,
    created_at DATETIME(6) NOT NULL,
    updated_at DATETIME(6) NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_file_fingerprint (file_size, content_hash),
    KEY idx_file_fingerprint_work (work_id),
    CONSTRAINT fk_file_fingerprint_work FOREIGN KEY (work_id) REFERENCES works (id),
    CONSTRAINT fk_file_fingerprint_episode FOREIGN KEY (episode_id) REFERENCES episodes (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
