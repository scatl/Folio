CREATE TABLE server_identity (
    id BIGINT NOT NULL,
    server_id VARCHAR(36) NOT NULL,
    remote_url VARCHAR(512) NULL,
    updated_at DATETIME(6) NOT NULL,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO server_identity (id, server_id, remote_url, updated_at)
VALUES (1, UUID(), NULL, UTC_TIMESTAMP(6));
