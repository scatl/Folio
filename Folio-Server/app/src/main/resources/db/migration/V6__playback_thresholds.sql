ALTER TABLE app_settings
    ADD COLUMN playback_ignore_below_seconds INT NOT NULL DEFAULT 10,
    ADD COLUMN playback_complete_remaining_seconds INT NOT NULL DEFAULT 30;
