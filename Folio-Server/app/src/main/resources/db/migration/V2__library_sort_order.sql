ALTER TABLE media_libraries
    ADD COLUMN sort_order INT NOT NULL DEFAULT 0;

UPDATE media_libraries AS target
JOIN (
    SELECT id, ROW_NUMBER() OVER (ORDER BY created_at DESC, id DESC) - 1 AS sort_order
    FROM media_libraries
) AS ranked ON ranked.id = target.id
SET target.sort_order = ranked.sort_order;
