# languageApp

Topluluk tarafından oluşturulan **dil paketleri** ile çalışan, açık formatlı bir
dil öğrenme platformu. Yazarlar derslerini GitHub repolarında veya doğrudan ZIP
yükleyerek dağıtır; SDK bunları indirip cihazda çalıştırır.

> Bu repo şu anda **aktif geliştirme** aşamasındadır. Public API'ler ve pack
> formatı `1.0.0` öncesinde değişebilir.

## Canlı dağıtım

Backend AWS'de (Frankfurt, eu-central-1) çalışıyor:

- **API**: <https://api.paktly.dev>
- **Marka**: paktly.dev (DNS + TLS Caddy + Let's Encrypt)
- **Mimari özeti**: tek EC2 (t4g.small) → Caddy → Go binary → RDS Postgres + S3
- **Otomatik deploy**: `main`'e push → GH Actions GHCR'a image basar → EC2'deki
  Watchtower 5 dk içinde pull edip yeniden başlatır
- Adım adım kurulum: [docs/AWS_SETUP.md](docs/AWS_SETUP.md)


## Mimari

```
┌─────────────┐     pack zip       ┌──────────────┐     manifest+    ┌──────────┐
│  Yazar      │  ───────────────►  │   Backend    │  ◄─────────────► │ Postgres │
│  (GitHub /  │                    │   (Go API)   │                  └──────────┘
│   ZIP)      │                    │              │     pack zip     ┌──────────┐
└─────────────┘                    │              │  ──────────────► │  S3 /    │
                                   │              │                  │  MinIO   │
┌─────────────┐  presigned GET     │              │                  └──────────┘
│  iOS/Android│  ◄─────────────────┤              │
│    SDK      │                    └──────────────┘
└─────────────┘
```

- **Pack formatı** açık ve dokümantedir → bkz. [docs/PACK_FORMAT.md](docs/PACK_FORMAT.md)
- **Şemalar** JSON Schema ile tanımlıdır → [schema/](schema/)
- **Backend** tek başına çalışan Go binary'sidir → [backend/](backend/)
- **Mobil**: Swift (iOS) + Kotlin (Android) — henüz yazılmadı

## Repo yapısı

```
.
├── backend/             Go API (registry + ingest + auth)
│   ├── cmd/api/         entry point
│   ├── internal/        auth, db, github, httpapi, pack, storage, config
│   ├── migrations/      goose SQL migrations
│   ├── docker-compose.yml   Postgres + MinIO (yerel geliştirme)
│   └── Makefile
├── docs/
│   └── PACK_FORMAT.md   pack spesifikasyonu (TR)
├── schema/
│   ├── manifest.schema.json
│   └── lesson.schema.json
├── packs/
│   └── example-nihongo/ örnek Japonca pack (hiragana + selamlaşma)
├── README.md
└── ROADMAP.md
```

## Şu an çalışan kısım

Backend MVP'si ayağa kalkıyor ve uçtan uca pack ingest edebiliyor:

| Özellik                           | Durum |
|-----------------------------------|:-----:|
| Pack format spesifikasyonu (1.0.0)| OK    |
| JSON Schema (manifest + lesson)   | OK    |
| Örnek pack (Japonca)              | OK    |
| Postgres + MinIO docker-compose   | OK    |
| Goose migrations (packs, users)   | OK    |
| ZIP upload + zip-slip koruması    | OK    |
| Manifest/lesson schema validation | OK    |
| Media referans bütünlüğü          | OK    |
| GitHub release import             | OK    |
| S3 presigned download URL         | OK    |
| Email + parola auth (bcrypt+JWT)  | OK    |
| Pack ownership (id rezervasyonu)  | OK    |
| Yapılandırılmış hata formatı      | OK    |
| Arama + cursor pagination         | OK    |
| Token-bucket rate limiting        | OK    |
| OpenAPI 3.1 spec                  | OK    |
| CI (vet + lint + test + race)     | OK    |
| Image build → GHCR                | OK    |
| iOS SDK                           | —     |
| Android SDK                       | —     |
| Pack dizin UI                     | —     |

Yol haritası için [ROADMAP.md](ROADMAP.md).

## Hızlı başlangıç (backend)

Gereksinimler: Go 1.22+, Docker, [goose](https://github.com/pressly/goose).

```bash
cd backend
cp .env.example .env
# .env içinde JWT_SECRET'i `openssl rand -base64 48` ile değiştir

make up              # postgres + minio + bucket
export DATABASE_URL="postgres://langapp:langapp_dev@localhost:5432/langapp?sslmode=disable"
make migrate-up
make run             # http://localhost:8080
```

Sağlık kontrolü:

```bash
curl localhost:8080/healthz
```

## API uçları (özet)

| Method | Path                                              | Auth | Açıklama                              |
|--------|---------------------------------------------------|:----:|---------------------------------------|
| GET    | `/healthz`                                        |  —   | sağlık kontrolü                       |
| POST   | `/v1/auth/register`                               |  —   | email + parola ile kayıt              |
| POST   | `/v1/auth/login`                                  |  —   | JWT döner                             |
| GET    | `/v1/auth/me`                                     |  ✓   | aktif kullanıcı                       |
| GET    | `/v1/packs?language=&level=&tag=&q=&limit=&cursor=` |  —   | arama + cursor pagination             |
| GET    | `/v1/packs/{id}`                                  |  —   | tek pack + sürümleri                  |
| GET    | `/v1/packs/{id}/versions/{version}/download`      |  —   | presigned indirme URL'i               |
| POST   | `/v1/packs/upload`                                |  ✓   | multipart `pack` alanıyla zip yükleme |
| POST   | `/v1/packs/import-github`                         |  ✓   | `{ "repoUrl": "..." }` ile içe aktar  |

**Tam API kontratı** ve hata kodları: [docs/openapi.yaml](docs/openapi.yaml).
Hatalar tek tip şemada gelir: `{ "error": { "code", "message", "fields[] } }`.

## Pack yazmak

Tek satırlık tarif: bir `manifest.json` + `lessons/*.json` + (opsiyonel) `media/`
hazırla, ZIP'le, GitHub release'e yükle veya `/v1/packs/upload`'a POST et.
Detaylar: [docs/PACK_FORMAT.md](docs/PACK_FORMAT.md). Çalışan örnek:
[`packs/example-nihongo/`](packs/example-nihongo/).

## Katkı / commit mesajı kuralı

Sürümler [release-please](https://github.com/googleapis/release-please) ile
otomatik üretilir. Commit mesajı **Conventional Commits** formatında olmalı:

| Prefix | Anlam | Versiyon etkisi |
|---|---|---|
| `feat:` | Yeni özellik | minor (`0.x.0`) |
| `fix:` | Bug fix | patch (`0.0.x`) |
| `feat!:` veya body'de `BREAKING CHANGE:` | Geriye dönük uyumsuz değişiklik | major (`x.0.0`) |
| `docs:` | Yalnız dokümantasyon | release etmez ama CHANGELOG'a girer |
| `chore:`, `ci:`, `refactor:`, `test:` | İç işler | release etmez |

Örnek:
```
feat(ios): add LessonRunner block renderer
fix(backend): clamp pagination limit to [1,100]
feat!: rename pack manifest field `level` to `cefrLevel`
```

Akış: main'e push → release-please bot bir **Release PR** açar/günceller →
hazır olunca o PR'ı merge edersin → tag + GitHub release + Docker image
tagleri otomatik oluşur.

## Lisans

Kod **MIT** lisansı altında — bkz. [LICENSE](LICENSE). Self-hosting tam
desteklenir; SDK ve backend registry-agnostiktir, paktly.dev'i hiç
kullanmadan tüm sistemi çalıştırabilirsin (docker compose ile birkaç dakika).

Her **pack içeriği** kendi `manifest.json` `license` alanındaki lisansı
taşır (CC-BY-4.0 veya CC-BY-SA-4.0 önerilir).

## Sürdürülebilirlik modeli

Paktly **Obsidian'a benzer** bir model izler:

- **Temel her şey ücretsiz + open source**: pack format, backend, SDK, mobile
  app çekirdeği. İndir, kendin host et, hiç ödeme yapmadan kullan.
- **Paktly hosted (paktly.dev)** convenience servisidir — fiyatlandırma sadece
  AI açıklamaları ve cihazlar arası sync gibi sunucu maliyetli özellikler için
  (Phase 8'de). Free tier: pack ara, indir, lokal çalıştır.
