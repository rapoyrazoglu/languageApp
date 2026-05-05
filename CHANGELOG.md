# Changelog

Tüm önemli değişiklikler bu dosyaya eklenir. Format [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versiyonlama [SemVer](https://semver.org/lang/tr/) uyumludur.

## [0.2.0] — 2026-05-05

Phase 2 close + AWS production deployment.

### Backend hardening
- Token-bucket rate limiting (per-IP anonymous + per-user authenticated)
- Search API with cursor pagination (`language`, `level`, `tag`, free-text `q`)
- Structured error format with stable codes (`{ "error": { "code", "message", "fields" } }`)
- OpenAPI 3.1 spec — [docs/openapi.yaml](docs/openapi.yaml)
- **Audit log** (`pack_audit_log`): every publish/update with user, source, IP, UA. Owner-only `GET /v1/packs/{id}/audit`.
- **GitHub release webhook ingest** (`POST /v1/webhooks/github`) with HMAC-SHA256 verification.
- Webhook subscription API: `POST/GET/DELETE /v1/webhooks/subscriptions`.
- Integration test suite (Postgres + MinIO end-to-end, `-tags=integration`).
- CI: golangci-lint v2, race-enabled tests, multi-arch GHCR images.
- Migration runner image (goose + migrations baked in).

### Production deploy (AWS, eu-central-1)
- Single EC2 (t4g.small ARM) + Caddy + Let's Encrypt auto-TLS.
- RDS Postgres in private subnet, KMS-encrypted, daily backup.
- S3 bucket with presigned URL access, block-public-access on.
- Secrets Manager (`paktly/db`, `paktly/jwt`, `paktly/geminiapi`).
- IAM role least-privilege (no static credentials on EC2).
- CloudWatch alarms + SNS mail notifications.
- Snapshot/restore drill verified.
- ~$32/month total.
- Step-by-step runbook: [docs/AWS_SETUP.md](docs/AWS_SETUP.md).

### Auto-deploy
- `main` push → GitHub Actions → GHCR (`linux/amd64` + `linux/arm64`).
- Watchtower polls GHCR every 5 minutes, pulls + restarts `paktly-api`.
- systemd `ExecStartPre` runs migrations idempotently before each start.

**Live**: <https://api.paktly.dev>

## [0.1.0] — initial

Phase 0 + Phase 1 — pack format spec + backend MVP (auth, ingest, presigned download, GitHub release import).
