-- +goose Up
-- +goose StatementBegin

-- Audit log: every successful publish/update of a pack version, plus the
-- subject who did it and how. Read-only from the API; rows are append-only.
CREATE TABLE pack_audit_log (
    id          BIGSERIAL PRIMARY KEY,
    pack_id     TEXT NOT NULL,
    version     TEXT NOT NULL,
    user_id     UUID REFERENCES users(id) ON DELETE SET NULL,
    action      TEXT NOT NULL,         -- 'publish' (first version) | 'update' (later version)
    source      TEXT NOT NULL,         -- 'upload' | 'github' | 'webhook'
    source_url  TEXT,
    ip_address  INET,
    user_agent  TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_audit_pack ON pack_audit_log (pack_id, created_at DESC);
CREATE INDEX idx_audit_user ON pack_audit_log (user_id, created_at DESC);

-- Webhook subscriptions: a user opts in their GitHub repo so that release
-- events trigger ingest under their identity. (repo_owner, repo_name) is
-- globally unique so two users can't claim the same repo.
CREATE TABLE webhook_subscriptions (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    repo_owner TEXT NOT NULL,
    repo_name  TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (repo_owner, repo_name)
);

CREATE INDEX idx_webhook_subs_user ON webhook_subscriptions (user_id);

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin

DROP TABLE IF EXISTS webhook_subscriptions;
DROP TABLE IF EXISTS pack_audit_log;

-- +goose StatementEnd
