-- +goose Up
-- +goose StatementBegin

-- Schema 1.2.0 introduces multi-locale `translations` maps. The registry now
-- derives two locale signals at ingest time and stores them per-version
-- (translations evolve across versions; pack-row denormalisation would lie):
--
--   supported_locales   atom-kind allowlist ≥ 90% — drives the Discover
--                       "For X speakers" filter.
--   locale_coverage     pool-wide percent (0..1) per locale — surfaced as
--                       a transparency chip in the UI.
--   translation_status  the creator's per-locale provenance declaration
--                       from manifest.translationStatus (native / machine /
--                       reviewed / partial). Quality signal, separate from
--                       the two derived fields above.

ALTER TABLE pack_versions
    ADD COLUMN supported_locales  TEXT[] NOT NULL DEFAULT '{}',
    ADD COLUMN locale_coverage    JSONB  NOT NULL DEFAULT '{}'::jsonb,
    ADD COLUMN translation_status JSONB  NOT NULL DEFAULT '{}'::jsonb;

-- GIN index on supported_locales lets `WHERE 'tr' = ANY(supported_locales)`
-- and `?| array['tr','en']` queries hit an index instead of seqscanning.
CREATE INDEX idx_pack_versions_supported_locales
    ON pack_versions USING GIN (supported_locales);

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin

DROP INDEX IF EXISTS idx_pack_versions_supported_locales;

ALTER TABLE pack_versions
    DROP COLUMN IF EXISTS translation_status,
    DROP COLUMN IF EXISTS locale_coverage,
    DROP COLUMN IF EXISTS supported_locales;

-- +goose StatementEnd
