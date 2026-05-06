# Changelog

Tüm önemli değişiklikler bu dosyaya eklenir. Format [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versiyonlama [SemVer](https://semver.org/lang/tr/) uyumludur.

## [0.3.0](https://github.com/rapoyrazoglu/languageApp/compare/v0.2.0...v0.3.0) (2026-05-06)


### Features

* **backend:** persist supportedLocales + localeCoverage + translationStatus on pack_versions ([8fe12a2](https://github.com/rapoyrazoglu/languageApp/commit/8fe12a2af34fae3d129388341f906a1000dc63e9))
* **creator-cli:** paktly CLI for content creators ([002d832](https://github.com/rapoyrazoglu/languageApp/commit/002d8328d2ccb6bdc83c45f3a27aa366da97b07a))
* **demo:** iOS demo app — Home / Discover / Language Detail / Lesson Runner ([972cbfc](https://github.com/rapoyrazoglu/languageApp/commit/972cbfcc335f5987893aa1391513c23667656d42))
* **ios:** add 10 exercise family views — every exerciseType is renderable ([6b4ec68](https://github.com/rapoyrazoglu/languageApp/commit/6b4ec6839aea5c9166d41d7b93ddacb679bfe6fa))
* **ios:** add LessonRunner SwiftUI views (explanation + vocabulary cards) ([670138a](https://github.com/rapoyrazoglu/languageApp/commit/670138a20f1c608554862eb088215f657b36f238))
* **ios:** add PackStore — verified download, unzip, on-device cache ([340e957](https://github.com/rapoyrazoglu/languageApp/commit/340e957f59c5756e3e05df7a84ed32d4ce1a14c1))
* **ios:** add PaktlyAudioPlayer with AVSpeechSynthesizer fallback ([9fc5b9f](https://github.com/rapoyrazoglu/languageApp/commit/9fc5b9f93bc79d15f706f9521a1fa54707607f2a))
* **ios:** add RegistryClient — async REST client for paktly registries ([82c4b56](https://github.com/rapoyrazoglu/languageApp/commit/82c4b56666fca1f25be1206662a096692f83c2cb))
* **ios:** Hashable + Identifiable conformances on registry types ([3d4eeb2](https://github.com/rapoyrazoglu/languageApp/commit/3d4eeb2e46b97aa3d2034ffdf75ae11ccbc0e4fb))
* **ios:** PaktlyKit foundation — Codable models for pack format v1.0/v1.1 ([d54d0ba](https://github.com/rapoyrazoglu/languageApp/commit/d54d0ba59c378038581f42afbeb0f6ec2203b716))
* **pack:** bump schema to 1.1.0 with aiCapabilities, vocab examples, ipa, level path ([76d4244](https://github.com/rapoyrazoglu/languageApp/commit/76d4244be94143fd4691fa95d2a18381fb3670ab))
* **pack:** expand exerciseType catalog to 30 types in 10 families ([daad52a](https://github.com/rapoyrazoglu/languageApp/commit/daad52acc4f78db2375f61dc33582e53d76045cc))
* **schema:** pack format 1.2.0 — dialogue/kanji/grammar blocks + multi-locale + mock exam ([754b70e](https://github.com/rapoyrazoglu/languageApp/commit/754b70e907e5b78e7de1ad0e910e96e77d0ab0b7))


### Bug fixes

* **lint:** satisfy errcheck / gofmt / revive on golangci-lint v2.5.0 ([554077a](https://github.com/rapoyrazoglu/languageApp/commit/554077aa51bc2bb380ba213c6adcf85dc793cc92))


### Documentation

* add CLAUDE.md (AI agent context) + GETTING_STARTED.md (human onboarding) ([09d8acc](https://github.com/rapoyrazoglu/languageApp/commit/09d8acc169740fdb8c0ed141cede90ace57013e3))
* comprehensive AUTHORING.md for pack creators ([ad69cbb](https://github.com/rapoyrazoglu/languageApp/commit/ad69cbb0ae02c0801eeab1c51fd7ad0a8d143ea0))
* **creator:** CREATOR_API.md + ORIGINALS_OPS.md publish-side runbooks ([2387ad1](https://github.com/rapoyrazoglu/languageApp/commit/2387ad13d531e374aab61bc6c73089e8218b5f63))
* MIT license, Obsidian-style monetization plan, Phase 2.5 + Phase 8 in roadmap ([fefc3d4](https://github.com/rapoyrazoglu/languageApp/commit/fefc3d4d0d23e371925aa392bf55554913e87469))
* refresh CLAUDE.md for Phase 3g + add HANDOFF.md session state ([e158b4b](https://github.com/rapoyrazoglu/languageApp/commit/e158b4b4c16da957c2accb56f54e3d298cea8548))
* refresh ROADMAP / CLAUDE for Phase 2.5–3f progress and locked decisions ([b3c274d](https://github.com/rapoyrazoglu/languageApp/commit/b3c274d02f89d12f1c3009ec85a6a5d608d418d3))
* roadmap — multi-provider AI, creator incentives, Paktly Originals, Phase 9 billing ([54c6938](https://github.com/rapoyrazoglu/languageApp/commit/54c6938b952d3f766034a9726538e67f3731026a))
* TUTORIAL.md 30-min on-ramp + design HTML specs ([61dca2a](https://github.com/rapoyrazoglu/languageApp/commit/61dca2a125f18ef406041e270bedc825c08e1d37))


### CI / Build

* add manual release workflow (workflow_dispatch + tag + release notes from CHANGELOG) ([74ae20f](https://github.com/rapoyrazoglu/languageApp/commit/74ae20f9411ee2357fdaa8cb284c482364c1d5dd))
* add release-please for automated semver releases from Conventional Commits ([09eddfa](https://github.com/rapoyrazoglu/languageApp/commit/09eddfa61c89513653bdc9d39cdbadf0a8298ff6))
* golangci-lint v2, Go 1.25 toolchain ([f2581fd](https://github.com/rapoyrazoglu/languageApp/commit/f2581fdd558de2f95069131556f8cb1bbf27683c))
* replace retired bitnami/minio with official minio/minio + manual bucket seed ([cca5203](https://github.com/rapoyrazoglu/languageApp/commit/cca52037d37b25a2595ba768755f4c10459e14b1))


### Tests

* **integration:** read example pack version from manifest, not hardcoded ([1966962](https://github.com/rapoyrazoglu/languageApp/commit/1966962e782497cf1325ebc8c2326ea3d8e0a46c))

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
