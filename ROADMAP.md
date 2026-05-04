# ROADMAP

Bu doküman projenin nereye gittiğini ve hangi sırayla götürüldüğünü anlatır.
Tarihler **niyet beyanı**dır, taahhüt değil.

## Tasarım ilkeleri

1. **Pack formatı her şeyden önce gelir.** Backend ve SDK formatın
   uygulamalarıdır; format hiçbirine bağımlı değildir. Her bozucu değişiklik
   `schemaVersion` artırır.
2. **GitHub-native ve ZIP-native eş öncelikli.** Bir kanal birinci sınıf, diğeri
   "bonus" değildir. İkisi de aynı validation pipeline'ından geçer.
3. **Immutability.** Yayınlanmış `id@version` asla değişmez. Düzeltme = yeni
   sürüm.
4. **SDK offline-first olur.** İnternet sadece "yeni pack indir" anında
   gereklidir; ders çalışmak için gerekmez.
5. **Mobil = native.** Swift (iOS) + Kotlin (Android). Cross-platform
   framework'ü kullanmıyoruz; bu kararı tekrar açmıyoruz.

---

## Phase 0 — Temel (TAMAMLANDI)

- [x] Pack format spesifikasyonu v1.0.0 ([docs/PACK_FORMAT.md](docs/PACK_FORMAT.md))
- [x] JSON Schema: `manifest.schema.json`, `lesson.schema.json`
- [x] Örnek Japonca pack (hiragana + selamlaşma) + ses dosyaları
- [x] Postgres + MinIO docker-compose
- [x] Goose migrations (`packs`, `pack_versions`, `users` + ownership)

## Phase 1 — Backend MVP (TAMAMLANDI)

- [x] HTTP server (Go stdlib `net/http`, slog logger)
- [x] Config: env-driven (`.env.example`)
- [x] S3-uyumlu storage adapter (MinIO yerel, AWS prod)
- [x] Pack ingest pipeline:
  - [x] zip aç (zip-slip korumalı)
  - [x] manifest schema validation
  - [x] her ders dosyası için lesson schema validation
  - [x] media referansları gerçekten var mı kontrolü
  - [x] SHA256 + boyut limiti
- [x] GitHub release ingest (en son release'i bul, asset zip'i indir)
- [x] Email + parola auth (bcrypt + JWT)
- [x] Pack ownership: bir `id`'i ilk publish eden user sahip olur, başkası yazamaz
- [x] Presigned download URL'leri

## Phase 2 — Backend sertleştirme (TAMAMLANDI)

> Hedef: production'a koyabileceğimiz hale getirmek.

- [x] **Test**: validator (zip-slip, semver, lesson id eşleşmesi, eksik media,
  …), auth (bcrypt + JWT), cursor encode/decode, rate limiter, error format —
  hepsi `-race` ile yeşil
- [x] **Rate limiting**: anonim ve auth'lu uçlar için token-bucket (60/dk vs
  600/dk varsayılan, env ile ayarlanır)
- [x] **Arama API'si**: dil + level + tag + serbest metin (ILIKE)
- [x] **Pagination**: `/v1/packs` keyset cursor (updated_at, id)
- [x] **Yapılandırılmış hatalar**: `{ error: { code, message, fields[] } }`
  şeması, stable error code'lar
- [x] **OpenAPI 3.1 spec**: `docs/openapi.yaml`
- [x] **CI**: GitHub Actions — `go vet` + `golangci-lint` + `go test -race`
- [x] **Container image**: GHCR'a otomatik push (main + semver tag)
- [x] **Audit log**: `pack_audit_log` tablosu, her ingest'te publish/update
  satırı; `GET /v1/packs/{id}/audit` (owner-only)
- [x] **Webhook desteği**: `POST /v1/webhooks/github` (HMAC-SHA256 doğrulama),
  `POST/GET/DELETE /v1/webhooks/subscriptions` ile repo→user mapping
- [x] **Migration runner image**: `backend/Dockerfile.migrate` (goose +
  migrations); GHCR'a `languageapp-migrate` olarak basılır
- [x] **Integration test**: `make test-integration` — gerçek Postgres + MinIO
  ile uçtan uca register/login → upload → list → search → download → audit →
  duplicate-version → webhook subscriptions
- [ ] **Backend deploy** (Fly.io / Railway / VPS — kararlaştırılacak)

## Phase 3 — iOS SDK + Demo App

> Dil: **Swift**, minimum iOS 16. Paket yönetimi: Swift Package Manager.

- [ ] `LanguageAppKit` SPM paketi
- [ ] `RegistryClient` (REST: list / get / download)
- [ ] `PackStore`: indirilen pack'leri lokal disk'te saklar, hash doğrular
- [ ] `LessonRunner`: block stream'ini (explanation/vocabulary/exercise)
  SwiftUI view'larına render eder
- [ ] Egzersiz tipleri: flashcard, multipleChoice, typing, listening
  (matching + fillInBlank Phase 4'te)
- [ ] AVFoundation ile audio playback
- [ ] Demo SwiftUI app: pack ara, indir, çalış
- [ ] TestFlight'a iç beta

## Phase 4 — Android SDK + Demo App

> Dil: **Kotlin**, minimum API 26. Build: Gradle, Jetpack Compose.

- [ ] `languageapp-sdk` Kotlin kütüphanesi
- [ ] iOS ile **bire bir API paritesi** (sınıf isimleri eşleşmek zorunda değil,
  yetenekler eşleşmek zorunda)
- [ ] Aynı egzersiz tipleri
- [ ] ExoPlayer / MediaPlayer ile audio
- [ ] Demo Compose app
- [ ] Internal track beta (Play Console)

## Phase 5 — Topluluk + Yazar UX

- [ ] Web tabanlı pack tarayıcısı (read-only Next.js)
- [ ] Pack sayfası: README, sürüm geçmişi, "indirme komutu"
- [ ] CLI: `langapp pack validate`, `langapp pack publish`
- [ ] Pack yazma şablonu (cookiecutter benzeri)
- [ ] Çeviri pipeline'ı (yazarın bir pack'i başka UI dillerine çevirebilmesi)

## Phase 6 — Öğrenme döngüsü

> Bu noktaya kadar SDK sadece "ders çal"abiliyor. Buradan sonra **öğrenme**
> başlıyor.

- [ ] Spaced repetition (FSRS veya SM-2 — karar verilecek)
- [ ] İlerleme senkronizasyonu (cihazlar arası, opsiyonel)
- [ ] Streak / hedefler
- [ ] Topluluk: pack rating, yorum, "report content"

## Phase 7 — Production hardening (launch öncesi)

> Tetikleyici: ilk gerçek kullanıcılar / Instagram reklam akışı / iOS App
> Store yayını. Şimdiki dev kurulumu ($32/ay, public subnet) → "max güvenlik"
> moduna (~$120/ay) geçiş.

- [ ] **Network**: EC2 private subnet'e taşı, public subnet'te ALB ayağa
  kaldır, NAT Gateway + Internet Gateway. Inbound: ALB (443) → EC2 (8080).
- [ ] **TLS**: ACM sertifika ALB'ye (Caddy yerine), HTTP→HTTPS redirect
- [ ] **HA**: Auto Scaling Group (min 2, max 4), multi-AZ EC2
- [ ] **DB HA**: RDS Multi-AZ failover, backup retention 7 → 30 gün
- [ ] **Backup**: Cross-region snapshot replication (eu-west-1)
- [ ] **WAF**: rate limit, SQL injection / XSS rules, bot defense, country
  block (gerekirse)
- [ ] **CDN**: CloudFront ALB önünde — edge cache + DDoS + ucuz egress
- [ ] **Monitoring**: CloudWatch alarms → SNS pager (RDS CPU, EC2 health,
  5xx oranı, audit log spike). PagerDuty veya OpsGenie entegrasyonu opsiyonel.
- [ ] **Auth**: opsiyonel 2FA (TOTP), parola sıfırlama akışı (e-posta + token),
  session revoke, account lockout
- [ ] **Audit alarms**: anormal davranış tespiti — saatte 100+ upload, başka
  ülkeden login, vb. SNS bildirimi
- [ ] **Compliance temeli**: KVKK/GDPR aydınlatma metni, veri silme talebi
  endpoint'i, retention policy yazımı
- [ ] **Pen test**: launch'tan önce dış pentest (independent veya
  bug-bounty programı)

Hedef bütçe: ~$120/ay. Reklam dönüşümlerinde düşük tutar.

---

## Açık sorular (henüz karar verilmedi)

- Telif: kullanıcı ilerlemesi sunucuya gitmek **zorunda mı**, yoksa cihazda mı
  kalsın? (default: cihazda kalır, opt-in sync)
- Multi-tenant mi tek instance mı? Şimdilik tek instance.
- Pack'lerde **video** ne zaman? Format destekliyor ama validator henüz değil.
- Ödemeli pack desteği? Şimdilik **hayır**, format buna uygun ama platform değil.

## Sürüm hedefleri

| Sürüm  | Kapsar                                              |
|:------:|-----------------------------------------------------|
| 0.1.0  | Phase 0 + Phase 1 (mevcut HEAD)                     |
| 0.2.0  | Phase 2 (test + CI + audit + webhook + integration) |
| 0.3.0  | iOS SDK alpha (Phase 3'ün çekirdeği)                |
| 0.4.0  | Android SDK alpha (Phase 4'ün çekirdeği)            |
| 0.5.0  | Web pack tarayıcısı + CLI                           |
| 1.0.0  | İki SDK + 5+ pack + spaced repetition               |
