# Paktly — context for Claude

> Bu dosya Claude Code (veya benzeri AI ajan) tarafından her oturumun başında
> okunur. Projenin neden, nasıl ve nereye gittiğini anlatır. Kullanıcı ile
> sohbette alınmış kararlar buraya yansır ki ileride hatırlansın.

## What this is

Paktly is an **open language pack platform**. Community-authored ZIP packs are
distributed through a Go registry; iOS/Android SDKs download and run them
locally. Pack format is fully documented and self-hosting is first-class.

- **Live API**: <https://api.paktly.dev> (AWS, eu-central-1)
- **Marka**: Paktly. Domain Namecheap'te kayıtlı, DNS Route53'te.
- **Kullanıcı**: tek kişi (rapoyrazoglu / "ata"), kodlama tecrübesi sınırlı —
  Claude'u sürücü olarak kullanır, plain language ile yön verir, code yazmaz.

## Repo yapısı

```
backend/                Go API. cmd/api ana binary, cmd/validate-pack yazar CLI.
  internal/             auth, db, github, httpapi, pack, storage, config
  migrations/           goose SQL (currently 3: init, auth, audit_and_webhooks)
  integration/          Postgres+MinIO end-to-end (-tags=integration)
  Dockerfile            backend image
  Dockerfile.migrate    migration runner image (goose + migrations baked in)
ios/                    Swift Package "PaktlyKit". iOS 16+, macOS 13+.
  Sources/PaktlyKit/    Models/, Registry/, (yakında) Store/, Views/
  Tests/PaktlyKitTests/ Fixtures/, Support/, *Tests.swift
packs/example-nihongo/  Reference pack, schema 1.1.0, audio + IPA + examples
schema/                 manifest + lesson JSON Schema (mirrored in backend/internal/pack/schemas)
docs/
  AWS_SETUP.md          17-step Console runbook for AWS deploy
  PACK_FORMAT.md        Pack format spec (1.0.0 + 1.1.0)
  GETTING_STARTED.md    Human-facing onboarding (use this if you're
                        explaining the project to the user)
  openapi.yaml          REST API contract
.github/workflows/
  backend.yml           lint + race tests + Postgres+MinIO integration
  ios.yml               swift test on macos-15
  release.yml           Docker images on tag push (linux/amd64 + linux/arm64)
  release-please.yml    auto Release PR from Conventional Commits
  release-publish.yml   manual workflow_dispatch fallback for releases
ROADMAP.md              Phases 0-9 with version targets
CHANGELOG.md            Keep a Changelog format, source of release notes
LICENSE                 MIT
README.md               Project front door
```

## Locked decisions

- **License**: code MIT, pack content per-pack (CC-BY / CC-BY-SA önerilir).
- **Self-hosting**: birinci sınıf. SDK registry URL'i config'le; backend
  docker-compose ile herkes kendi başına çalıştırabilir.
- **Monetization**: Obsidian modeli — free/open core sonsuz, paid sync + AI
  Phase 8'de. Hiç pack ödemeli olmaz.
- **AI strategy**: multi-provider proxy (`/v1/ai/*`). **Default DeepSeek**
  (~50% daha ucuz). Gemini alternatif (KVKK/GDPR önemliyse opt-in). Ollama
  self-host kullanıcılar için. Creator pack başına seçer; Paktly seçilen
  sağlayıcının API key'ini verir (creator kendi sağlayıcı hesabını
  yönetmez), tüm AI çağrıları Paktly merkezi hesabından geçer, fatura
  Paktly'de biter. Phase 8'de geliyor.
- **App UI dilleri** (launch minimum): TR, EN, DE, zh-Hans (anakara Çince),
  ES. Pack içerik lokalizasyonu ayrı (manifest `uiLanguage`).
- **Video pack'lerde**: opsiyonel, asla zorunlu değil. Validator warning yok,
  featured curation video varlığına bakmaz. Phase 6 öncesi roadmap dışı.
- **Creator billing**: Phase 8'de yok, Phase 9'da Stripe Connect ile gelir.
  Phase 8'de Paktly tüm AI cost'unu absorb eder (subscription'tan), creator'a
  sadece analytics dashboard.
- **Pricing target**: Free + Paktly+ (~$5/ay). AWS aylık ~$32 (Phase 7'de
  ~$120). 5-10 paid kullanıcı break-even.
- **Pack format**: v1.1.0 active. v1.0.0 still validates (backwards compat).
- **Branding**: "paktly" her yerde (paktly-vpc, paktly/db secret, vb.); Go
  module path eski adıyla `github.com/ata/languageapp/...` (rename değer
  taşımaz, dokunma).

## Branch + release modeli

- `main` = production. Her push otomatik deploy:
  - GH Actions release.yml → GHCR'a Docker image (linux/amd64 + linux/arm64)
  - EC2'deki Watchtower 5 dk içinde pull + restart
- **Conventional Commits zorunlu**: feat:, fix:, perf:, deps:, revert:, docs:,
  ci:, chore: (hidden), refactor:, test:, style: (hidden).
- **release-please** her main push'unda Release PR açar/günceller. Merge
  edince tag + GitHub release otomatik oluşur; release.yml semver tagli
  Docker image'leri basar.
- **release-publish** workflow'u manuel fallback (Actions UI'dan tetiklenir).

## Yaygın komutlar

```bash
# Backend
cd backend
make test                              # birim test (race)
make test-integration                  # postgres + minio uçtan uca
go run ./cmd/validate-pack pack.zip    # bir pack zip'i validate et
go run ./cmd/api                       # backend lokal çalıştır

# iOS
cd ios
swift test --parallel
swift build
xed Package.swift                      # Xcode'da aç

# AWS deploy
ssh -i ~/.ssh/paktly-key.pem ec2-user@3.69.40.116
sudo systemctl status paktly
sudo journalctl -u paktly -f
```

## Live infrastructure (production)

- **EC2**: t4g.small ARM, paktly-api, public subnet, IAM role
  paktly-ec2-role
- **Elastic IP**: 3.69.40.116 → api.paktly.dev (Caddy + Let's Encrypt)
- **RDS**: paktly-db (Postgres 16, db.t4g.micro, private subnet, KMS-encrypted)
- **S3**: paktly-packs-sjgku7 (block-public-access on, presigned URL only)
- **Secrets Manager**: paktly/db, paktly/jwt, paktly/geminiapi (placeholder)
- **CloudWatch alarms**: RDS CPU > 80%, EC2 status fail, RDS storage < 5 GB
- **Account ID**: 629843008627 (region: eu-central-1)

## Mevcut faz

> **Detaylı session state için [HANDOFF.md](HANDOFF.md)'i oku** — şu anda
> nerdeyiz, hangi commit'ler push edilmemiş, sıradaki adımlar, bilinen
> bug'lar, build komutları orada toplanmış. CLAUDE.md stabil kararlar
> içindir; HANDOFF.md "şu anda" cevabı verir.

**Phase 3 — iOS SDK alpha + Phase 3g demo app** (devam ediyor, design
polish iterasyonunda). Tamamlanan:

- Phase 2.5: pack format v1.1 + 1.2.0 (30-type exercise catalog)
- Phase 3a: Codable models
- Phase 3b: RegistryClient (13 test)
- Phase 3c: PackStore + dep-free pkzip (10 test)
- Phase 3d: LessonRunner SwiftUI views
- Phase 3e: 30 exercise type, 10 family view, ExerciseData typed payloads
- Phase 3f: PaktlyAudioPlayer (AVFoundation + TTS fallback)
- Phase 3g: **Demo iOS app** — Home (lesson path + 3D nodes + breath
  animation), Discover (sticky header + featured + grids), Language Detail
  (tier filter + author avatars), Lesson Runner (custom + chevron nav row),
  PlacementTest (mini-quiz to skip ahead), Floating tab bar (custom pill).
  TR-locked at app init.
- Plus creator CLI (`paktly` binary) + AUTHORING.md + TUTORIAL.md.

Sıradaki:
- Lesson content design pass (explanation + vocab cards + exercise polish) —
  Claude Design brief draft halinde
- Backend per-type schema validation + tier/lessonCount fields
- Phase 4 Android starter
- Phase 5-9 sırayla

## Stil + kalite kuralları

- Backend Go: golangci-lint v2 yeşil, race-enabled tests yeşil. Skip yok.
- Test'ler tekrarlanabilir ve flaky olmamalı. Flaky çıkarsa root-cause fix
  (örn. token_test.go'daki base64 son-byte tampering case'i — son karakter 2
  effective bit, decode-flip-encode pattern'iyle çözüldü).
- iOS Swift: tüm public type'lar `Sendable`. Optional collection'lar
  decoder'da `?? []` ile default'lanır (omitempty contract).
- Yorumlar: WHY için, WHAT için değil. Self-evident kodu açıklama.
- AWS_SETUP.md / ROADMAP.md / CHANGELOG.md: stratejik karar buraya yazılır,
  sonra unutulmaz.

## Bilinen quirklar / dikkat noktaları

- AWS Console'da bazı gizli ücretler kapalı tutulmalı: Performance Insights,
  Enhanced Monitoring, Multi-AZ RDS (Phase 7'ye kadar), DevOps Guru, NAT
  Gateway. Hepsi $/ay yer.
- Bitnami `:latest` taglar Docker Hub'dan kalktı (Aug 2025) — minio için
  official `minio/minio` + `minio/mc` ile manuel bucket seed kullanıyoruz.
- GH Actions repo seviyesinde "Allow GitHub Actions to create and approve
  pull requests" kapalıysa release-please 403 verir. Settings → Actions →
  General'dan açık olmalı.
- Gmail confirmation maillerinde "unsubscribe" linki yanlışlıkla tıklanabilir
  ve SNS subscription deactive olur — Yahoo gibi başka mail tercih.
- Pack secret'ları Secrets Manager'da düzenlemek mümkün ama console UI'sı
  bazen gizler — "Retrieve secret value" → "Edit" akışı.

## Acil durum

- Backend down: `sudo systemctl status paktly`, `sudo journalctl -u paktly -n 100`
- DB cannot connect: RDS Console → paktly-db Available mi, SG `paktly-db-sg`
  hâlâ `paktly-web-sg`'den 5432 alıyor mu
- TLS bozuk: `sudo journalctl -u caddy`. DNS doğrula `dig api.paktly.dev`.
- Disk dolu: EC2'ye SSH, `df -h`. Genelde Docker layer cache yer kapar:
  `sudo docker system prune -af`
