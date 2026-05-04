-- +goose Up
-- +goose StatementBegin

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;

CREATE TABLE users (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email         CITEXT NOT NULL,                        -- case-insensitive
    password_hash TEXT NOT NULL,
    display_name  TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX idx_users_email ON users (email);

-- Pack ownership: the user who first publishes a pack id owns it.
-- Nullable so existing rows aren't broken; new uploads will always set it.
ALTER TABLE packs ADD COLUMN owner_user_id UUID REFERENCES users(id) ON DELETE SET NULL;
CREATE INDEX idx_packs_owner ON packs (owner_user_id);

-- Track which user uploaded each version (audit trail).
ALTER TABLE pack_versions ADD COLUMN uploader_user_id UUID REFERENCES users(id) ON DELETE SET NULL;

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin

ALTER TABLE pack_versions DROP COLUMN IF EXISTS uploader_user_id;
DROP INDEX IF EXISTS idx_packs_owner;
ALTER TABLE packs DROP COLUMN IF EXISTS owner_user_id;
DROP TABLE IF EXISTS users;

-- +goose StatementEnd
