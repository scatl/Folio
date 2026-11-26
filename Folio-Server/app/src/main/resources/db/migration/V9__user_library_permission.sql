CREATE TABLE user_library_permissions (
    user_id BIGINT NOT NULL,
    library_id BIGINT NOT NULL,
    access VARCHAR(8) NOT NULL,
    PRIMARY KEY (user_id, library_id),
    CONSTRAINT fk_ulp_user FOREIGN KEY (user_id) REFERENCES app_users (id) ON DELETE CASCADE,
    CONSTRAINT fk_ulp_library FOREIGN KEY (library_id) REFERENCES media_libraries (id) ON DELETE CASCADE
);
