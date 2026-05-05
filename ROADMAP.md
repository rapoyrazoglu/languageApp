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
- [x] **Backend deploy** — AWS, eu-central-1, ~$32/ay (paktly.dev). Auto-deploy
  Watchtower + GHCR ile. Detaylar [docs/AWS_SETUP.md](docs/AWS_SETUP.md).

## Phase 2.5 — Pack format v1.1 (mini-faz)

> Phase 3 öncesi pedagojik elementleri zorunlu / yarı-zorunlu kıl. iOS SDK'yı
> direkt v1.1'e karşı yazalım, sonradan refactor olmasın.

- [ ] **Vocabulary genişletme**: word, reading, meaning + `audio` (zorunlu),
  `examples[]` (opsiyonel ama önerilen), `ipa` (opsiyonel)
- [ ] **Example sentence bloğu**: yeni block tipi `example` — text + translation
  + audio + grammar referansı
- [ ] **Level path**: manifest'te `previousPack` + `nextPack` (opsiyonel),
  curated paketler için zincir
- [ ] **Audio kuralı**: vocabulary item'ı için audio yoksa validator warning
  (zorunluluk değil ama featured olabilmesi için şart — Phase 5)
- [ ] Schema bump 1.0.0 → 1.1.0 (geriye uyumlu, eski paketler hâlâ çalışır)
- [ ] Validator update + test
- [ ] Örnek pack'i (`example-nihongo`) v1.1'e migrate et + audio ekle

## Phase 3 — iOS SDK + Demo App

> Dil: **Swift**, minimum iOS 16. Paket yönetimi: Swift Package Manager.
> Registry-agnostik: SDK herhangi bir paktly-uyumlu registry URL'ine bağlanabilir
> (kendi self-host'unu kullananlar dahil).

- [ ] `LanguageAppKit` SPM paketi
- [ ] `RegistryClient` (REST: list / get / download) — base URL configurable
- [ ] `PackStore`: indirilen pack'leri lokal disk'te saklar, hash doğrular
- [ ] `LessonRunner`: block stream'ini (explanation/vocabulary/example/exercise)
  SwiftUI view'larına render eder
- [ ] Egzersiz tipleri: flashcard, multipleChoice, typing, listening
  (matching + fillInBlank Phase 4'te)
- [ ] AVFoundation ile audio playback (vocabulary item'larından)
- [ ] Demo SwiftUI app: pack ara, indir, çalış. Default registry api.paktly.dev,
  Settings'ten değiştirilebilir
- [ ] Lokal pack yükleme: cihazda var olan zip'i SDK'ya beslemek (registry'siz mod)
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

## Phase 5 — Topluluk + Yazar UX + Self-hosting

> "Yapılandırılmış açık" modelin uygulaması: kim isterse pack publish edebilir,
> kim isterse kendi registry'sini kurabilir. Curation gatekeeping yerine
> öne çıkarmayla yapılır.

- [ ] **AUTHORING.md**: kaliteli pack nasıl yazılır — örnek cümleler,
  audio kuralları, level path, tipik tuzaklar. "Paktly Originals" referans
  paketleri burada listelenir.
- [ ] **SELF_HOSTING.md**: docker compose ile kendi registry'ini ayağa kaldır,
  S3-compatible storage, mobil app'i kendi URL'ine yönlendir. Paktly hosted
  servisini hiç kullanmadan tüm sistem nasıl çalıştırılır.
- [ ] **Web tabanlı pack tarayıcısı** (read-only Next.js) — paktly.dev'in
  search/discovery yüzü. Featured packs öne çıkarılır.
- [ ] Pack sayfası: README, sürüm geçmişi, "indirme komutu"
- [ ] **CLI**: `paktly pack validate`, `paktly pack publish`, `paktly pack new`
- [ ] Pack yazma şablonu (cookiecutter benzeri)
- [ ] Çeviri pipeline'ı (yazarın bir pack'i başka UI dillerine çevirebilmesi)
- [ ] **Featured curation** mekanizması: biz manuel "Paktly seçimi" işaretleriz,
  search'te öne çıkar
- [ ] **Creator incentive program**:
  - İlk 50 creator için $20/ay ücretsiz AI quota + "Founding Creator" badge
  - Kalite eşiği aşan pack'ler featured slot + push bildirimi
  - Discord/forum + verified creator badge + "Pack of the week"
  - Pack yazma yarışmaları (örn. "yeni dil topluluğa ekle" challenge'ı)

## Phase 5b — Paktly Originals (paralel olarak Phase 3-4 ile)

> İlk 5 referans pack'i biz yazıyoruz. "Featured by Paktly" rozetleriyle
> showcase görevi görür, topluluk creator'larına kalite barı koyar, ileride
> licensable asset olur (3rd party platformlara satış / partnership).

- [ ] **Japonca N5** — Hiragana + Katakana + temel kelime (50+ ders, 500+
  kelime, native audio)
- [ ] **İngilizce A1-A2** (TR konuşan için) — günlük konuşma, dilbilgisi
- [ ] **Korece TOPIK I** — Hangul + ortalık konuşma
- [ ] **İspanyolca A1**
- [ ] **Almanca A1**

Her biri:
- Native speaker audio (script + studio kayıt)
- Bunpo-grade dilbilgisi açıklamaları
- Örnek cümleler her vocab item için
- AI capability declarations (questionGeneration + explanation)
- CC-BY-SA 4.0 lisansı (kullanıcı dağıtabilir, atıf zorunlu)

## Phase 6 — Öğrenme döngüsü

> Bu noktaya kadar SDK sadece "ders çal"abiliyor. Buradan sonra **öğrenme**
> başlıyor.

- [ ] Spaced repetition (FSRS veya SM-2 — karar verilecek), client-side
- [ ] Streak / hedefler (lokal)
- [ ] Topluluk: pack rating, yorum, "report content"
- [ ] **İlerleme senkronizasyonu** (cihazlar arası) — opt-in, paid feature
  (Phase 8'in parçası)

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

## Phase 8 — Paid cloud features

> Sürdürülebilirlik için. Obsidian modeli: temel kullanım sonsuz ücretsiz +
> kendi self-host eden hiç ödemez. Sadece Paktly hosted'in convenience
> özellikleri ücretli.

- [ ] **AI proxy** (`/v1/ai/...`): multi-provider (Gemini + DeepSeek + OpenAI +
  Anthropic + **Ollama** for self-hosters). Provider-agnostic interface,
  config-driven default.
  - Gemini Flash: default, KVKK/GDPR güvenli
  - DeepSeek V3: ucuz alternatif (~50% maliyet)
  - Ollama: self-host eden kullanıcı kendi yerel modeline yönlendirir
- [ ] **Per-user token quota**: subscription tier'a göre, audit log'a yazılır
- [ ] **Per-pack soft cap** ($5/gün/pack default): abuse koruması, aşılınca
  pack AI feature'ları 24 saat dondurulur, creator'a mail
- [ ] **Pack AI capability declaration**: manifest'te `aiCapabilities` (Phase
  2.5'te schema'ya eklendi), backend'de gating
- [ ] **Creator dashboard**: analytics-only başlangıçta (kullanım, top prompt'lar,
  hata oranı). Billing yok — Paktly subscription'tan absorb eder.
- [ ] **iOS Siri TTS fallback**: vocab'da audio yoksa AVSpeechSynthesizer kullanır
- [ ] **Cross-device sync**: ilerleme + indirilen packlist + favoriler
  E2E encrypted blob olarak Postgres'te
- [ ] **Stripe entegrasyonu**: aylık abonelik, free trial, iptal akışı
- [ ] **Free tier limitleri**: anonim N istek/dk + auth user M istek/saat
  (rate limiting zaten var). AI için ayrı kota: free=0 token, paid=X/ay
- [ ] **Account management UI**: web sayfası — abonelik durumu, ödeme yöntemi,
  kullanım, iptal
- [ ] **Pricing page**: paktly.dev/pricing — net plan karşılaştırması

Hedef: 5-10 paid kullanıcı break-even, 50+ kullanıcı kâr eder.

## Phase 9 — Creator billing + revenue share (uzun vade)

> Phase 8'de creator'lar AI'i ücretsiz alıyor (Paktly absorb ediyor). Bu
> aşama creator'lara billing + gelir kazanma seçenekleri ekler.

- [ ] **Creator Stripe Connect onboarding** — KYC + payout
- [ ] **Pre-fund AI**: creator pack'i için AI quota satın alır, kendi pack'i
  daha çok AI desteklesin diye
- [ ] **Tip jar / Patreon entegrasyonu** — pack sayfasında destek butonu
- [ ] **Subscription revenue share** (Spotify modeli): Paktly+ gelirinin
  belli yüzdesi pack kullanım metriklerine göre creator'lara paylaşılır
- [ ] **Epic Games modeli**: creator gelir eşiğini geçtikten sonra Paktly
  küçük yüzde kesinti yapar (ör. ilk $1000 ücretsiz, sonrası %12)
- [ ] **Tax / 1099 / KVKK uygunluk**: legal danışmanlık gerekir bu noktada

---

## Açık sorular (henüz karar verilmedi)

- Pack'lerde **video** ne zaman? Format destekliyor ama validator henüz değil.
- **Translation/UI lokalizasyon**: pack içeriği dışında app UI'ı kaç dile?
  Şimdilik TR + EN.
- **Curation komitesi**: "Paktly seçimi" featured paketleri kim onaylıyor —
  tek başına ben mi, topluluk vote mu?
- **AI default provider**: Gemini mi DeepSeek mi başlangıçta? (multi-provider
  mimari yine de yazılır, değiştirmek 1 config satırı)

## Stratejik seçenekler (uzun vade, hedef değil)

Topluluk + pack katalogu + kullanıcı tabanı belli bir noktaya geldiğinde
seçenekler:

1. **Bağımsız büyüme**: subscription revenue ile sürdürülebilir, kendi başımıza
2. **Acquisition target**: Duolingo / Babbel / Mondly / Memrise bizi alır
   (pack format spec + registry tech + Paktly Originals + community)
3. **Asset licensing**: Paktly Originals'i platform-agnostic content olarak
   3rd party platformlara satarız / lisanslarız
4. **Open source halo**: Wikipedia-vakfı modeli, donation-driven; subscription
   minimum operasyonel maliyet için kalır
5. **Edu kurumlarına SaaS**: okullar / kurslar kendi Paktly instance'larını
   self-host edip kendi içeriklerini barındırır (paid support contract)

Bunlar **opsiyon**, hedef değil. Önce kullanıcılar için iyi ürün çıkar.

## Karara bağlananlar

- **Lisans**: kod MIT, pack içerikleri her pack'in `manifest.json`'daki kendi
  lisansı (genelde CC-BY veya CC-BY-SA önerilir).
- **Self-hosting**: birinci sınıf desteklenir. SDK ve backend tamamen
  registry-agnostic.
- **Paid model**: Obsidian benzeri local-first. Temel her şey ücretsiz +
  open source. Sadece convenience features (AI, cross-device sync) paid.
- **Kullanıcı ilerlemesi**: default cihazda kalır, opt-in cloud sync (Phase 8).
- **Multi-tenant**: tek instance, paktly.dev tek registry. Self-hosting
  isteyen kendi instance'ını çalıştırır.
- **Ödemeli pack**: hayır. Sadece ücretsiz / CC-lisanslı pack'ler. Yazarlar
  ister tip jar / GitHub Sponsors koyabilir, biz aracılık yapmıyoruz.

## Sürüm hedefleri

| Sürüm  | Kapsar                                              |
|:------:|-----------------------------------------------------|
| 0.1.0  | Phase 0 + Phase 1                                   |
| 0.2.0  | Phase 2 + AWS deploy + auto-deploy                  |
| 0.2.1  | Phase 2.5 — pack format v1.1 (audio + examples)     |
| 0.3.0  | iOS SDK alpha (Phase 3'ün çekirdeği)                |
| 0.4.0  | Android SDK alpha (Phase 4'ün çekirdeği)            |
| 0.5.0  | Web pack tarayıcısı + CLI + self-hosting docs       |
| 0.6.0  | Spaced repetition + topluluk (Phase 6)              |
| 1.0.0  | İki SDK + 5+ Paktly Originals + SRS                 |
| 1.1.0  | Paid cloud (AI multi-provider + sync, Phase 8)      |
| 1.2.0  | Creator billing + revenue share (Phase 9)           |
