-- +goose Up
-- +goose StatementBegin

CREATE TABLE packs (
    id            TEXT PRIMARY KEY,                      -- reverse-DNS, e.g. com.github.ata.nihongo
    name          TEXT NOT NULL,
    description   TEXT,
    language_code TEXT NOT NULL,                         -- ISO 639, e.g. ja
    language_name TEXT NOT NULL,
    ui_language   TEXT,
    level         TEXT,
    author_name   TEXT NOT NULL,
    author_url    TEXT,
    license       TEXT NOT NULL,
    homepage      TEXT,
    repository_url TEXT,
    tags          TEXT[] NOT NULL DEFAULT '{}',
    latest_version TEXT,                                 -- denormalized: most recent version
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_packs_language_code ON packs (language_code);
CREATE INDEX idx_packs_tags ON packs USING GIN (tags);

CREATE TABLE pack_versions (
    pack_id        TEXT NOT NULL REFERENCES packs(id) ON DELETE CASCADE,
    version        TEXT NOT NULL,                       -- semver, e.g. 1.2.0
    schema_version TEXT NOT NULL,                       -- pack format version
    sha256         TEXT NOT NULL,                       -- content hash of zip
    size_bytes     BIGINT NOT NULL,
    storage_key    TEXT NOT NULL,                       -- S3 key, e.g. packs/com.github.ata.nihongo/1.2.0.zip
    source         TEXT NOT NULL,                       -- 'github' | 'upload'
    source_url     TEXT,                                -- if from github: release asset URL
    manifest_json  JSONB NOT NULL,                      -- cached manifest for fast queries
    min_sdk_version TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (pack_id, version)
);

CREATE INDEX idx_pack_versions_created_at ON pack_versions (created_at DESC);

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin

DROP TABLE IF EXISTS pack_versions;
DROP TABLE IF EXISTS packs;

-- +goose StatementEnd
