# Session handoff — Paktly

> Yeni bir Claude Code session açıldığında **CLAUDE.md ile birlikte bu
> dosyayı oku**. Burası "şu anda nerdeyiz, sıradaki ne" cevabını verir;
> CLAUDE.md ise stabil proje kararlarını tutar.

Son güncelleme: 2026-05-06 · branch: `main` · push edilmemiş commit yok ama
uncommitted UI iş yığını var (aşağıda).

---

## TL;DR — bir cümlede durum

Backend + iOS SDK + 30-type exercise catalog + Demo app + creator CLI hazır
ve yeşil; **Discover / Home / Lesson Runner ekranları tasarım spec'lerine
göre uygulandı**, son birkaç oturumda micro-detail polish yapılıyor (current
node nefes animasyonu, sticky header, featured kart kuralları, language
detail author avatarları). **Lesson content ekranları (explanation +
vocabulary kartları + exercise polish)** için Claude Design'a verilecek
brief draft halinde, görsel asset bekleniyor.

---

## Repo haritası (CLAUDE.md'yi tamamlar)

```
backend/                 Go API (canlı: api.paktly.dev)
  cmd/api/               main binary
  cmd/paktly/            ⭐ creator CLI: `pack new / validate / publish`,
                         `login`, embedded templates, 14 unit test
  cmd/validate-pack/     legacy single-purpose validator (paktly tarafından
                         süperseded; silmedik, geriye uyum için duruyor)
  internal/pack/         schema validator, manifest model
ios/                     PaktlyKit Swift package
  Sources/PaktlyKit/
    Models/              Manifest, Lesson, Block + 30-type ExerciseData
    Registry/            RegistryClient, RegistryError, APIModels
    Store/               PackStore, PaktlyZip (dep-free pkzip), InstalledPack
    Audio/               PaktlyAudioPlayer (AVFoundation + TTS fallback)
    Views/               LessonRunnerState, LessonRunnerView, all block +
                         exercise family views (10 family, 30 types)
    Resources/           en + tr Localizable.strings (zh-Hans/de/es stub)
  Tests/PaktlyKitTests/  60 tests, all green
  Demo/PaktlyDemo/       ⭐ demo iOS app (Xcode project, synchronized groups)
    PaktlyDemo/          Swift sources (see "Demo app state" below)
schema/                  manifest.schema.json, lesson.schema.json (1.2.0)
design/                  ⭐ HTML design specs (paste-into-Claude-Design output)
  Home/                  Paktly Spec - Home.html
  Discover/              Paktly Discover.html, Paktly Language Detail.html
docs/                    PACK_FORMAT, AUTHORING, TUTORIAL, openapi, AWS_SETUP
HANDOFF.md               this file
ROADMAP.md               phases 0-9 + locked decisions
CLAUDE.md                stable project context, decisions
```

---

## Demo app — ekran-ekran durum

### Home tab
- Top-left: language pill butonu — emoji bayrak değil, **native script**
  (`日本語`) + `[A1]` chip + `⌄` chevron, tek pill
- Center: kompakt 60pt pack header — "PACK 1" caption (heavy, tracked) +
  pack name (22pt rounded bold) + meta (language · lessons)
- Body: **lesson path** — winding serpentine
  - Node Ø 84pt, vertical pitch 200pt, 6-cycle swing `[-78,-26,26,78,26,-26]`
  - Connector: cubic Bezier dashed (4pt, 6/8 dash, divider color)
  - Node states (spec section 4):
    - Completed: accent face + accentInk shelf + ✓ heavy
    - **Current**: white face + **ink shelf** + **outline ⭐ ink color** +
      3pt accent ring + **breath 1.04 / 1.6s `withAnimation(.repeatForever)`**
    - Locked (everything after current): muted face + lock
    - Upcoming case enum'da var ama state mapping kullanmıyor
- Bottom: floating tab bar pill + **back/next chevrons lesson içindeyken**
- Locked node tap → `PlacementTestSheet` (real mini-quiz, 80% threshold)

### Discover tab
- Sticky header (~178pt — spec hedefi 188pt, hafif eksik): solid `DS.background`
  + `safeAreaInset(edge: .top)` (scroll content arkaya geçmiyor, status bar
  alanını da kaplıyor)
  - "Keşfet" largeTitle
  - Search pill (clear ⓧ butonlu)
  - Filter pills: Hepsi / Yeni / En çok beğenilen / Ücretsiz
  - Bottom hairline divider
- Featured card: sabit 168pt yükseklik, **green gradient** (DS.accent →
  DS.accentInk per spec line 102 "#58CC02 (accent)"), `[FEATURED]` tag,
  pack name (28pt heavy), description, `[Önizle ▶]` white pill
- "Türkçe konuşanlar için" — 2-col grid, locale-aware
  - Tile: language glyph (gradient + flag emoji, 92pt) + level chip overlay +
    native script + display name + pack name
  - Card hue (red/blue/yellow/orange) hash-deterministic per pack id
- "Bu hafta popüler" — compact list rows, hue avatar + tier badge
- "Seviyeye göre" — 3×2 grid (A1-C2), per-cell pack count, tap → LanguageDetailView

### Language Detail
- Reached from `By level` cell tap, or pack picker's "Discover for X speakers"
- Tier filter chips: All / Official / Community + count badges (App Store
  "·14" pattern)
- Level filter chips: dynamic (only present levels), `Text(verbatim:)` for
  "A1" type codes
- DetailPackRow: language gradient avatar (left) + pack name + tier badge +
  description + author bubble (initials-based 18pt circle) + level + version
- **Avatar derivation**: `DS.PackHue.forPack(authorName)` — author name hash
  → 4-color rotation. No real avatar URLs in registry yet.
- **Like count NOT shown** — spec says "yapan avatar + ad + beğeni" but no
  rating data exists; Phase 6 SRS telemetry'den sonra eklenir

### Settings tab
- Account card (Sign in / signed-in display)
- Registry card (URL editor, Reset / Apply)
- About card (version, source, website)

### Lesson Runner (push from Home)
- Full-screen, custom-rendered (SDK'nın `LessonRunnerView`'ını **kullanmıyor**
  — kendi state ownership'i)
- Owns `@StateObject LessonRunnerState`, sync lesson load in init
- Block routing: explanation / vocabulary / exercise → SDK public views
- Exercise blocks self-advance via `onFinish(_)` callback
- **Bottom row**: floating tab bar + flanking ← / → chevrons (`LessonNavCircle`)
  - 56pt 3D pressable circles, same physics as path nodes
  - Driven by `LessonRunnerState.canGoBack` / `canAdvance`
  - Disabled (gri, opacity 0.55) when at boundaries
- `services.activeLessonState` set on appear, nil on disappear → RootView
  watches this to show/hide the chevrons
- System nav bar back chevron (top-left) leaves the lesson entirely

### PlacementTestSheet
- 4-phase: intro / running / result / noQuestions
- Samples up to 5 exercises from skipped lessons (filtered to multipleChoice
  / typing / recall families — sheet boyutuyla uyumsuz tipler hariç)
- 80% pass threshold → `services.setCurrentLesson(packId, target.id)` →
  araları tamamlanmış sayılır

### Auth modal sheet
- Login / Register tab picker, email + password (+ optional displayName for
  register)
- 8-char min password, basic email shape check
- Stores token in `~/.config/paktly/config.json` (CLI side); demo's
  AppServices keeps in UserDefaults

---

## Custom design system (`DesignSystem.swift`)

| Token | Light | Dark |
|---|---|---|
| `background` | `#FAFAF7` (paper) | `#131F24` (teal-aside) |
| `surface` | `#FFFFFF` | `#1F2D33` |
| `surfaceMuted` | `#F1F1ED` | `#2A383F` |
| `divider` | `#E8E8E5` | `#37464F` |
| `textPrimary` (ink) | `#1A1A1A` | `#F7F7F4` |
| `textSecondary` | `#6E6E6E` | `#AEB7BB` |
| `textTertiary` | `#A8A8A8` | `#7A858B` |
| `accent` | `#58CC02` | `#58CC02` |
| `accentInk` | `#3A8A00` | `#93D851` |
| `accentMuted` | `#D7FFB8` | `#1F4A0A` |
| `success` / `warning` / `danger` | spec'in tightly-scoped renkleri (hearts/streak only) |

`DS.PackHue` enum: 4 renk (red / blue / yellow / orange) + ink companion.
Pack-tile background variety için. Featured asla bu enum'dan çekilmez —
her zaman accent green.

`DS.PackHue.forPack(id)` — pack id unicode toplam → modulo 4. Stable hash,
process restart'ta aynı pack aynı renkte.

---

## Build / run

```bash
# Backend tests
cd backend && go test ./cmd/paktly/... ./internal/pack/... -race

# Backend CLI (creator-side)
go run ./cmd/paktly help
go run ./cmd/paktly pack new my-pack --language ja --ui-language tr --level A1

# iOS SDK tests (60 tests)
swift test --package-path ios

# Demo app build (smoke check)
cd ios/Demo/PaktlyDemo
xcodebuild -project PaktlyDemo.xcodeproj -scheme PaktlyDemo \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build

# Demo app run in simulator
xed ios/Demo/PaktlyDemo/PaktlyDemo.xcodeproj
# ⌘R in Xcode
```

Demo Xcode projesi PaktlyKit'i `XCLocalSwiftPackageReference "../../../ios"`
ile linkliyor — kullanıcı bunu manuel olarak ekledi (target → Frameworks
ekranında). Yeni bir clone'da File → Add Package Dependencies → Add Local
yapması gerekebilir.

---

## Recent uncommitted work (push edilmemiş)

Şu anda working tree'de (commit edilmemiş):

- **Demo app — design spec compliance pass**
  - `DesignSystem.swift` — Duo green palette, PackHue enum 4 colors, fonts
  - `PressableButton.swift` — 3D shelf (depth 8) + circle variant + ringColor
  - `LessonPathView.swift` — 84pt node, 200pt pitch, cubic Bezier, ink shelf
    on current, outline star, breath animation rewrite
  - `HomeView.swift` — language pill, compact pack header, locale-aware path
  - `RootView.swift` — custom FloatingTabBar + LessonNavRow (ile back/next)
  - `FloatingTabBar.swift` (yeni) — custom material pill replaces UITabBar
  - `LessonNavRow.swift` + `LessonNavCircle` — chevron buttons
  - `LessonRunnerScreen.swift` — rewritten to own state + render blocks directly
  - `PackPickerSheet.swift` — bottom sheet "For X speakers" gruplu
  - `DiscoverView.swift` — full refactor: sticky header (safeAreaInset,
    188pt-target), featured (green sabit), 2-col tile grid, popular list,
    by-level grid
  - `LanguageDetailView.swift` (yeni) — tier + level filters, AuthorAvatar
  - `QualityTier.swift` (yeni) — heuristic until backend ships field
  - `PlacementTestSheet.swift` (yeni) — mini-quiz to skip ahead
  - `LanguageFlag.swift` — speakerLabel format string + display name
  - `Localizable.xcstrings` — 80+ key (en + tr filled, de/es/zh-Hans stub)
- **SDK** — küçük conformance ek'leri:
  - `Pack: Hashable, Identifiable`
  - `User: Hashable`
  - `LessonRef: Hashable, Identifiable`
  - `InstalledPack: Hashable` (manuel hash impl: packId+version+rootURL)

Önemli: **commit'lerde Claude attribution YOK**. Author = `rapoyrazoglu`.
Memory'de `feedback_commit_authorship.md` kuralı sabit.

---

## Locked decisions (memory'den)

Hepsi `~/.claude/projects/.../memory/` altında:

- `feedback_commit_authorship.md` — **No Co-Authored-By, no Claude attribution**
- `project_ai_strategy.md` — DeepSeek default, Paktly creator'a key verir
- `project_ui_languages.md` — TR / EN / DE / zh-Hans / ES day-one minimum
- `project_video_policy.md` — Video pack'lerde asla zorunlu değil
- `project_audio_strategy.md` — AVSpeechSynthesizer offline TTS-first;
  recorded audio override; featured pack'ler için kayıt zorunlu
- `project_content_priority.md` — Originals: TR + EN her target;
  zh-Hans English-only first; DE/ES English+JA first

Plus iOS demo'da app-init'te `UserDefaults.AppleLanguages = ["tr"]` —
demo modunda TR locked. Production app per-user setting okuyacak.

---

## Bilinen veri boşlukları

Bunlar UI'da gösterilemiyor çünkü backend cevabında YOK:

- **Lesson count per pack** — `Pack` model'de yok. Tile'da pack name fallback
- **Like count / rating** — Phase 6 SRS telemetry'siyle gelecek
- **Quality tier server-side** — şu an heuristic (`dev.paktly.*` →
  Official, `tags ∋ "reviewed"` → Reviewed, else Beta)
- **Featured pack rotation** — şu an "ilk official pack". Manuel weekly
  curation Phase 5'te
- **Author avatar** — initials-based bubble (no profile photos)
- **Streak chip slot** — top bar'da rezerve, Phase 6 SRS'le doldurulur

---

## Sıradaki — öncelik sırası

### 1. Visual polish — design HTML pixel-match
**Status**: HTML spec dosyaları render edebilen browser'da görünüyor ama
Claude'un access'i sadece HTML metni + spec notları (React component'leri
external CDN'den yükleniyor, dosya değil).

**User preference**: kullanıcı Chrome screenshot atarsa bire bir match.
Şu an spec metninden ekstrapole.

Atlanan / küçük gap'ler:
- Sticky header height ~178pt vs spec 188pt (10pt eksik)
- Spec section 5 "press timing 90ms in / 160ms out cubic-bezier
  (0.2,0.8,0.2,1)" — bizdeki spring(0.18, 0.65) approx
- Lesson content pages (explanation + vocab + exercise polish) için ayrı
  Claude Design brief draft halinde

### 2. Lesson content design pass (Claude Design'a brief'i ver)
- Brief önceki konuşmada draft'landı: 9 ekran (explanation, vocab card
  variants, exercise families top-5, completion screen, edge states)
- HTML spec gelince SDK'daki `Sources/PaktlyKit/Views/`'u refactor

### 3. Backend per-type schema validation (yarım kaldı, Phase 3e.1 follow-up)
- 30 exercise tipinin her birinin `data` payload'ı şu an `type: object` open
- Per-type sub-schemas: `oneOf` discriminated by `exerciseType`
- Creator'ın kötü pack'i upload'ta `paktly pack validate` ile yakalanır
- Estimate: ~1 oturum, 30 sub-schema + per-type Go validator dispatch

### 4. Backend tier + lessonCount field
- `Pack` response'a `lessonCount: int` ekle (manifest'ten count)
- `Pack` response'a `tier: string` ekle (ingest sırasında set, creator yazamaz)
- Demo'da `QualityTier.derive(_:)` heuristic → pack.tier okuyacak şekilde swap
- Estimate: ~0.5 oturum

### 5. Phase 4 Android starter
- Kotlin module, RegistryClient + PackStore parity (no UI)
- iOS SDK'ya bire bir API parity zorunlu değil — capability parity
- Estimate: ~3-5 oturum

### 6. Phase 5 — CLI + web pack browser + self-hosting docs
- `paktly` CLI çoğu hazır; eksik: `paktly pack diff`, `paktly pack info`
- Web pack browser: Next.js read-only catalog, paktly.dev frontend
- SELF_HOSTING.md: docker compose ile kendi registry'ni kur

### 7. Phase 6 — SRS algoritması (FSRS veya SM-2)
- Pure logic + tests (UI yok)
- iOS SDK + demo app entegrasyonu sonra

### 8. Phase 7 — Production hardening (private subnet, ALB, multi-AZ, WAF)
### 9. Phase 8 — AI proxy stub (`/v1/ai/...`, DeepSeek default)
### 10. Phase 9 — Creator billing (Stripe Connect)

---

## Bug / TODO listesi

- [ ] Lesson runner'da exercise blocks bottom padding `120pt` — floating
  tab bar + ChromeNavCircle row `LessonRunnerScreen.swift:97` — daha az
  olabilir, kontrol gerek
- [ ] Discover featured card 168pt sabit — bazı manifesto'larda description
  2-line lineLimit'i kesiyor; spec uyumlu ama UX kontrol gerek
- [ ] Language detail row'da level chip bazen çok dar ekranlarda çıkamıyor
  (HStack overflow) — `lineLimit(1)` yerine flex davranış lazım
- [ ] DE / zh-Hans / ES locale slot'ları boş; demo TR'de kilitli olduğundan
  bu sorun değil ama production deployment öncesi doldur
- [ ] PaktlyKit SDK'sının `LessonRunnerView` kullanılmıyor demo'da; ya silmek
  lazım ya genişletip üst exercise / vocabulary view'larını da bir top-level
  runner'da toplamak (clean api)
- [ ] `cmd/validate-pack` legacy kalıntı; `paktly pack validate` ile
  süperseded — ileride sil

---

## Yeni session açan Claude için ipuçları

1. **Build her zaman kontrol et**: `swift test --package-path ios` yeşil
   olmalı (60 test). Demo app: `xcodebuild ... build` BUILD SUCCEEDED olmalı.
2. **xcstrings dosyasına manuel müdahale yapma** — Xcode auto-extraction'la
   yarışıyor. Yeni key eklemen gerekiyorsa bash + Python script ile (örnek
   bu HANDOFF'un earlier conversation history'sinde var).
3. **Design spec'leri** `design/Home/`, `design/Discover/` altında. HTML
   açıp Chrome'da görüntülemek gerek; Claude metnine sadece spec notları
   ulaşıyor (React component'ler unicode CDN'den).
4. **Kullanıcı'nın direkt yorumları** çoğu zaman küçük detayları kapsar
   ("topbarda kart sızıyor", "current node hareket etmiyor", "X yazısı
   raw key görünüyor"). Spec'i baştan okumak ve micro-detail'leri tek tek
   karşılaştırmak işe yarıyor.
5. **iOS Simulator build target**: iPhone 16e iOS 26.2 (kullanıcının
   simulator'ı). Deployment target 16.6.
6. **TR locked**: app `UserDefaults.AppleLanguages = ["tr"]` yapıyor; UI
   her zaman Turkish render olur (catalog'da TR doluysa). DE/zh-Hans/ES
   stub state'te.
7. **Memory directory** `/Users/rapoyrazoglu/.claude/projects/-Users-rapoyrazoglu-Documents-projeler-paktly-languageApp/memory/` —
   her session başında MEMORY.md auto-load'lı.
