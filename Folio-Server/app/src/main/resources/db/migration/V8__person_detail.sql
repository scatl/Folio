ALTER TABLE people
    ADD COLUMN biography TEXT NULL,
    ADD COLUMN birthday DATE NULL,
    ADD COLUMN deathday DATE NULL,
    ADD COLUMN place_of_birth VARCHAR(512) NULL,
    ADD COLUMN known_for_department VARCHAR(128) NULL,
    ADD COLUMN also_known_as TEXT NULL,
    ADD COLUMN detail_fetched_at DATETIME(3) NULL;

CREATE TABLE person_credits (
    id BIGINT NOT NULL AUTO_INCREMENT,
    person_id BIGINT NOT NULL,
    media_type VARCHAR(16) NOT NULL,
    provider_media_id VARCHAR(64) NOT NULL,
    title VARCHAR(512) NOT NULL,
    original_title VARCHAR(512) NULL,
    release_year INT NULL,
    release_date DATE NULL,
    poster_url VARCHAR(1024) NULL,
    character_name VARCHAR(512) NULL,
    job_name VARCHAR(64) NULL,
    department VARCHAR(64) NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_person_credit (person_id, media_type, provider_media_id),
    KEY idx_person_credit_person (person_id),
    CONSTRAINT fk_person_credit_person FOREIGN KEY (person_id) REFERENCES people (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
