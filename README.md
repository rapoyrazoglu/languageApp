# languageApp

Topluluk tarafından oluşturulan **dil paketleri** ile çalışan, açık formatlı bir
dil öğrenme platformu. Yazarlar derslerini GitHub repolarında veya doğrudan ZIP
yükleyerek dağıtır; SDK bunları indirip cihazda çalıştırır.

> Bu repo şu anda **aktif geliştirme** aşamasındadır. Public API'ler ve pack
> formatı `1.0.0` öncesinde değişebilir.

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

## Lisans

Henüz seçilmedi (kod için MIT veya Apache-2.0 düşünülüyor). Pack içeriklerinin
lisansı her pack'in kendi `manifest.json` `license` alanında belirtilir.
