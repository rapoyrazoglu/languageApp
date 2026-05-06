# Pack Authoring Guide

> **Audience**: anyone who wants to publish a language pack on Paktly — solo
> teachers, schools, language enthusiasts, content studios. No coding required;
> a text editor and a folder is enough.

> **New here?** Start with **[TUTORIAL.md](TUTORIAL.md)** — a 30-minute
> hands-on walkthrough that takes you from zero to a published pack.
> This document is the reference manual; the tutorial is the on-ramp.

This document is the single source of truth for creators. It covers:

1. [What a pack is](#1-what-a-pack-is)
2. [Pack format quick reference](#2-pack-format-quick-reference)
3. [Manifest, field by field](#3-manifest-field-by-field)
4. [Lesson structure and content blocks](#4-lesson-structure-and-content-blocks)
5. [Vocabulary blocks (with audio + IPA + examples)](#5-vocabulary-blocks)
6. [The 30 exercise types — JSON shape for each](#6-exercise-types-the-30-catalog)
7. [Media: audio, images, video](#7-media-audio-images-video)
8. [Audio strategy: TTS vs recorded — when to record](#8-audio-strategy)
9. [Pack identifiers, semver, and immutability](#9-pack-id-and-semver)
10. [License and attribution](#10-license-and-attribution)
11. [Publishing — GitHub release vs direct ZIP](#11-publishing)
12. [Validation checklist (what the registry rejects)](#12-validation-checklist)
13. [AI capabilities (Phase 8 preview)](#13-ai-capabilities-phase-8-preview)
14. [Featured / "Paktly Originals" curation rules](#14-featured-curation)
15. [Worked example — a complete pack](#15-worked-example)
16. [FAQ](#16-faq)
17. [New block types (1.2.0): dialogue / kanji / grammar](#17-new-block-types-120)
18. [Mock exams (1.2.0)](#18-mock-exams-120)
19. [Locale coverage and translation provenance (1.2.0)](#19-locale-coverage-and-translation-provenance-120)

If you spot anything unclear, file an issue at
[github.com/rapoyrazoglu/languageApp/issues](https://github.com/rapoyrazoglu/languageApp/issues).

---

## 1. What a pack is

A **pack** is a folder of structured JSON + media that teaches a language. It
contains:

- One **`manifest.json`** that describes the pack (name, language, author,
  license, list of lessons).
- One or more **`lessons/*.json`** files. Each is an ordered sequence of
  content blocks (explanations, vocabulary lists, exercises).
- Optional **`media/`** — audio recordings, images, video.

The folder is zipped into a `.zip` file and uploaded to a Paktly-compatible
registry (the official one is `api.paktly.dev`; you can self-host).

The registry validates the pack, stores it on S3, and the iOS / Android
SDKs download and run it on the user's device. Lessons run **fully offline**
once installed.

A pack is a **product** in the file-system sense: it has a stable id, a
semver version, and is immutable once published — bug fixes ship as a new
version.

---

## 2. Pack format quick reference

```
my-pack/
├── manifest.json           ← required, the pack's identity card
├── README.md               ← recommended, free-form description for humans
├── LICENSE                 ← recommended (CC-BY-4.0 or similar)
├── lessons/                ← required, at least one
│   ├── 001-intro.json
│   ├── 002-greetings.json
│   └── …
└── media/                  ← optional
    ├── audio/
    ├── images/
    └── video/
```

Pack format is currently **`1.2.0`** (the active spec). Older `1.1.0` and
`1.0.0` packs continue to validate and run; new packs should set
`schemaVersion: "1.2.0"` so they can use the full exercise catalog and the
new content block types.

```json
{
  "schemaVersion": "1.2.0"
}
```

### What's new in 1.2.0

Compared to 1.1.0, all additions are backwards-compatible:

- **Three new block types** — `dialogue` (multi-speaker conversations),
  `kanji` (character cards with on/kun readings), `grammar` (structured
  grammar patterns with formation/usage/watch-outs). See [§17 New block types](#17-new-block-types-120).
- **Multi-locale text** — every locale-sensitive field (vocab `translation`,
  example `translation`, kanji `meaning`, grammar `meaning`/`formation`/
  `usage`/`watchOut`/dialogue `context`/mnemonic) now has a paired plural
  form (`translations`, `meanings`, `formations`, ...) that takes a BCP-47
  locale → string map. The legacy single-locale field stays as a fallback;
  emit at least one of them.
- **Mock exam lessons** — top-level `examMode: true` + `passingScore` +
  `timeLimit` + `drawsFrom[]` mark a lesson as an assessment. SDK disables
  hints, enforces a single attempt, and gates pack progress on the score.
  See [§18 Mock exams](#18-mock-exams-120).
- **Diagnostic exercise tags** — optional `skills[]` and `distractorTags[]`
  on exercise blocks. Reserved for Phase 6+ SRS / analytics; SDK currently
  ignores them, but emitting them now means your pack won't need rewriting
  later.

Schema files (JSON Schema 2020-12) live in
[`schema/manifest.schema.json`](../schema/manifest.schema.json) and
[`schema/lesson.schema.json`](../schema/lesson.schema.json). You can run
them through any JSON Schema validator locally before uploading.

---

## 3. Manifest, field by field

```json
{
  "schemaVersion": "1.2.0",
  "id": "com.github.<your-handle>.<pack-slug>",
  "name": "Japanese for Beginners",
  "version": "1.0.0",
  "description": "Hiragana, katakana, and 200 essential words.",
  "language": {
    "code": "ja",
    "name": "Japanese",
    "nativeName": "日本語",
    "script": "Jpan",
    "direction": "ltr"
  },
  "uiLanguage": "tr",
  "level": "A1",
  "author": {
    "name": "Ata",
    "url": "https://github.com/rapoyrazoglu",
    "email": "ata@example.com"
  },
  "license": "CC-BY-SA-4.0",
  "homepage": "https://example.com/my-pack",
  "repository": { "type": "git", "url": "https://github.com/ata/my-pack" },
  "tags": ["japanese", "beginner", "hiragana"],
  "lessons": [
    { "id": "001-hiragana", "file": "lessons/001-hiragana.json", "title": "Hiragana basics", "order": 1 },
    { "id": "002-greetings", "file": "lessons/002-greetings.json", "title": "Greetings",      "order": 2 }
  ],
  "dependencies": [],
  "minSdkVersion": "0.3.0",
  "previousPack": "com.paktly.ja.starter",
  "nextPack":     "com.paktly.ja.beginner-2",
  "aiCapabilities": {
    "questionGeneration": true,
    "explanation": true,
    "conversation": false,
    "hint": true
  }
}
```

### Required fields

| Field | Type | Notes |
|---|---|---|
| `schemaVersion` | string | One of `"1.0.0"`, `"1.1.0"`, `"1.2.0"`. New packs use `"1.2.0"`. |
| `id` | string | Reverse-DNS unique id. Pattern: `com.github.<handle>.<slug>`. **Cannot be changed after first publish.** |
| `name` | string | Human-readable name. 1–100 chars. |
| `version` | string | Semver `MAJOR.MINOR.PATCH`. Bump rules below. |
| `language` | object | The language being taught. `code` is ISO 639-1/2 (e.g. `ja`, `en`, `zh-Hans`). |
| `author` | object | At minimum `name`; `url` and `email` optional. |
| `license` | string | Pack content license. Recommended: `CC-BY-4.0` or `CC-BY-SA-4.0`. |
| `lessons` | array | One or more lesson references. Each must point at a real file under `lessons/`. |

### Optional fields

| Field | Type | Notes |
|---|---|---|
| `description` | string | Brief paragraph for the pack browser. |
| `uiLanguage` | string | Language of the lesson explanations / translations (i.e. the learner's native language). e.g. `tr`, `en`. |
| `level` | string | CEFR level: `A1`, `A2`, `B1`, `B2`, `C1`, `C2`, or `mixed`. |
| `homepage` | URL | A landing page if you have one. |
| `repository` | object | Git repo link if your pack is open-source. |
| `tags` | string[] | Search tags. |
| `dependencies` | array | Other packs this one builds on. Each entry: `{ "id": "...", "version": "..." }`. SDK warns if a dependency isn't installed. |
| `minSdkVersion` | string | Minimum PaktlyKit version. SDK refuses to open packs that need a newer SDK. |
| `previousPack` / `nextPack` | string | Pack ids that form a curriculum chain. Lets the SDK auto-suggest the next pack when a learner finishes. |
| `aiCapabilities` | object | Declares which AI features your pack supports — see [§13](#13-ai-capabilities-phase-8-preview). |

### Semver bump rules (your `version` field)

- **MAJOR**: a lesson was deleted or its `id` changed; a vocabulary item was
  removed; the pack's content shifted enough that resuming an in-progress
  user from a prior version would be confusing.
- **MINOR**: a new lesson was added; new vocabulary appeared; a new
  exercise type started being used.
- **PATCH**: typo fixes, audio re-recordings, minor wording tweaks. Same
  set of lessons, same set of vocabulary keys.

You can publish prereleases like `1.0.0-beta.1` — anything matching
`MAJOR.MINOR.PATCH(-suffix)?`.

---

## 4. Lesson structure and content blocks

A lesson is a JSON file with three required fields and an ordered list of
**blocks**:

```json
{
  "id": "001-hiragana",
  "title": "Hiragana basics — あいうえお",
  "description": "Five vowels. Read and write each one.",
  "estimatedMinutes": 8,
  "prerequisites": [],
  "blocks": [
    { "type": "explanation", "text": "Hiragana is one of three Japanese scripts." },
    { "type": "vocabulary", "items": [ /* … */ ] },
    { "type": "exercise", "exerciseType": "flashcard", "data": { /* … */ } }
  ]
}
```

| Field | Required | Notes |
|---|---|---|
| `id` | ✓ | Lowercase letters, numbers, hyphens. Must match the manifest's `lessons[].id`. |
| `title` | ✓ | What the learner sees on the lesson card. |
| `description` | — | Optional paragraph, used by some UIs. |
| `estimatedMinutes` | — | 1–120. Helps learners plan a session. |
| `prerequisites` | — | Other lesson ids that should be done first (lesson-level chain inside the same pack). |
| `blocks` | ✓ | Array of `explanation` / `vocabulary` / `exercise` items. |

Blocks render in order and the SDK shows them one at a time. Exercises drive
their own "submit / continue" interaction; explanations and vocabulary
blocks let the learner read at their own pace and tap a global "Next"
button.

### `explanation` block

Free-form text with optional inline markdown. Use this to teach a concept
before drilling it.

```json
{
  "type": "explanation",
  "text": "**Hiragana** is the phonetic alphabet for native Japanese words. There are 46 base characters.",
  "media": { "audio": "media/audio/hiragana-intro.mp3", "image": "media/images/chart.png" }
}
```

Inline markdown supported: `**bold**`, `*italic*`, ``inline code``, links.

### `vocabulary` block

A list of words / phrases. Each `item` is one entry. See [§5](#5-vocabulary-blocks).

### `exercise` block

The interactive part. See [§6](#6-exercise-types-the-30-catalog) for every
exercise type and its `data` payload.

---

## 5. Vocabulary blocks

```json
{
  "type": "vocabulary",
  "items": [
    {
      "target": "こんにちは",
      "translation": "merhaba",
      "transliteration": "konnichiwa",
      "audio": "media/audio/konnichiwa.mp3",
      "image": "media/images/wave.png",
      "ipa": "/koɲɲitɕiwa/",
      "notes": "Used roughly noon to ~5pm. Replace with おはよう before noon.",
      "examples": [
        {
          "text": "こんにちは、田中さん",
          "translation": "Merhaba Tanaka-san",
          "audio": "media/audio/example-tanaka.mp3",
          "notes": "-さん is a polite suffix attached to names."
        }
      ]
    }
  ]
}
```

Per-item fields:

| Field | Required | Since | Notes |
|---|---|---|---|
| `target` | ✓ | 1.0.0 | Word or phrase in the language being learned. |
| `translation` | ⚠️ | 1.0.0 | Single-locale translation. **At least one of `translation` or `translations` must be present.** |
| `translations` | ⚠️ | **1.2.0** | BCP-47 locale → string map, e.g. `{ "tr": "merhaba", "en": "hello", "zh-Hans": "你好" }`. Use this in place of (or alongside) `translation` for multi-locale packs. |
| `transliteration` | — | 1.0.0 | romaji, pinyin, or any romanisation that helps the learner. |
| `audio` | — | 1.0.0 | Path to audio under `media/audio/`. **Optional** — see [§8 audio strategy](#8-audio-strategy). |
| `image` | — | 1.0.0 | Path to an image under `media/images/`. |
| `notes` | — | 1.0.0 | Free-form note shown on the card (cultural context, gotchas). |
| `ipa` | — | 1.1.0 | Phonetic transcription. Especially useful for tonal / prosody-heavy languages. |
| `examples[]` | — | 1.1.0 | Example sentences featuring the word. Each has `text` + `translation` (or `translations`) + optional `audio` + `notes`. |

### Multi-locale translations (1.2.0+)

When you target multiple UI languages, prefer `translations` over the legacy
single-string `translation`:

```json
{
  "target": "こんにちは",
  "translations": {
    "tr": "merhaba",
    "en": "hello",
    "de": "hallo",
    "zh-Hans": "你好",
    "es": "hola"
  }
}
```

The SDK resolves the displayed string with this fallback chain:

1. The user's preferred locale (e.g. `zh-Hans-CN` → `zh-Hans` → `zh`)
2. The pack's `manifest.uiLanguage` (BCP-47 chain again)
3. The legacy `translation` field, if present

Locale keys must match `^[a-z]{2,3}(-[A-Za-z][A-Za-z0-9]*)?$` — lowercase
language code, optional region or script suffix. `zh-Hans` is valid; `TR` is
not. Same multi-locale pattern applies inside `examples[].translations`.

A pack's "supported locales" are derived at registry ingest time by walking
every translatable string and recording the locale keys present. A locale
counts as supported when ≥90% of translatable items have a value for it; the
Discover "For X speakers" surfaces use this list. You don't declare it in
the manifest.

The SDK renders each item as a card in a vertical stack. Ship at least an
`audio` recording for top-tier packs (see [Featured curation rules](#14-featured-curation)).

---

## 6. Exercise types — the 30 catalog

Every exercise block has the same outer shape:

```json
{
  "type": "exercise",
  "exerciseType": "<one of 30>",
  "prompt": "<optional teacher-facing question shown above the exercise>",
  "data": { /* type-specific payload — defined per family below */ }
}
```

The 30 types are organised into **10 families**. The renderer is one
SwiftUI view per family — variants within a family share the data shape
and differ in which media they spotlight.

### Family 1 — Recall (4 types)

A two-faced card. The user reads the front, taps to flip, then self-grades
("I knew it" / "Need to study").

**Types**: `flashcard` (front first), `flashcardReverse` (back first),
`flashcardAudio` (front filled with audio), `flashcardImage` (front filled
with image).

```json
{
  "type": "exercise",
  "exerciseType": "flashcard",
  "data": {
    "front": { "text": "こんにちは" },
    "back":  { "text": "merhaba", "audio": "media/audio/konnichiwa.mp3" },
    "hint": "informal greeting"
  }
}
```

`front` and `back` are **`ExerciseMedia`** values — see [§6.appendix](#exercisemedia).
For `flashcardAudio` you'd typically populate `front.audio` only; for
`flashcardImage`, `front.image`.

### Family 2 — MultipleChoice (5 types)

Pick the correct option from a list. The variant only changes which media
the prompt uses.

**Types**: `multipleChoice` (text→text), `multipleChoiceReverse` (reversed
direction), `multipleChoiceAudio` (audio prompt), `multipleChoiceImage`
(image prompt), `multipleChoiceContext` (sentence with a missing word; the
correct option fits the blank).

```json
{
  "type": "exercise",
  "exerciseType": "multipleChoiceAudio",
  "data": {
    "prompt": { "audio": "media/audio/konnichiwa.mp3" },
    "options": ["merhaba", "günaydın", "iyi geceler", "teşekkürler"],
    "correctIndex": 0,
    "explanation": "Daytime greeting in Japan."
  }
}
```

`correctIndex` is 0-based. Provide 3–5 options.

### Family 3 — Typing (3 types)

The learner types the answer. Whitespace is trimmed; case-insensitive by
default; you can supply alternative accepted forms.

**Types**: `typing` (translation→target), `typingReverse` (target→translation),
`typingAudio` (audio prompt → typed answer).

```json
{
  "type": "exercise",
  "exerciseType": "typing",
  "data": {
    "prompt": { "text": "Hello (informal)" },
    "answer": "こんにちは",
    "acceptedAlternatives": ["コンニチハ", "konnichiwa"],
    "caseSensitive": false,
    "hint": "Five hiragana characters."
  }
}
```

`acceptedAlternatives` is a flat array — any match is accepted.
`caseSensitive` defaults to `false`.

### Family 4 — Listening (3 types)

Audio drives every variant. Always ship a real recording — there's no
fallback for listening exercises.

**Types**:
- `listening`: hear → pick text option
- `dictation`: hear → type the full sentence
- `listenAndAct`: hear → tap the matching image

```json
{
  "type": "exercise",
  "exerciseType": "dictation",
  "data": {
    "audio": "media/audio/sentence.mp3",
    "answer": "今日はいい天気ですね",
    "transcript": "今日はいい天気ですね"
  }
}
```

```json
{
  "type": "exercise",
  "exerciseType": "listenAndAct",
  "data": {
    "audio": "media/audio/inu.mp3",
    "imageOptions": ["media/images/dog.png", "media/images/cat.png", "media/images/bird.png", "media/images/fish.png"],
    "correctIndex": 0
  }
}
```

`transcript` is optional but recommended — the SDK reveals it after submit
so the learner can compare what they heard.

### Family 5 — Matching (3 types)

Pair items in two columns. Tap left → tap right. Right column is
auto-shuffled per session.

**Types**: `matching` (text↔text), `matchingAudio` (audio↔text),
`matchingImage` (image↔text).

```json
{
  "type": "exercise",
  "exerciseType": "matching",
  "data": {
    "pairs": [
      { "left": { "text": "犬" }, "right": { "text": "köpek" } },
      { "left": { "text": "猫" }, "right": { "text": "kedi" } },
      { "left": { "text": "鳥" }, "right": { "text": "kuş" } }
    ]
  }
}
```

3–6 pairs is the sweet spot. With more, the screen gets crowded; with less,
the puzzle is trivial.

### Family 6 — FillInBlank (3 types)

A sentence with one or more blanks. The learner fills each. Blanks are
marked with `{{1}}`, `{{2}}` etc. — 1-indexed.

**Types**: `fillInBlank` (free type), `fillInBlankChoice` (tap from a fixed
pool of words), `fillInMultiple` (multiple blanks per sentence).

```json
{
  "type": "exercise",
  "exerciseType": "fillInBlankChoice",
  "data": {
    "template": "{{1}} さん、おはようございます",
    "answers": ["田中"],
    "options": ["田中", "山田", "鈴木", "佐藤"],
    "acceptedAlternatives": [["タナカ", "tanaka"]],
    "caseSensitive": false
  }
}
```

`answers[i]` is the truth for blank `{{i+1}}`.
`acceptedAlternatives[i]` is a list of equally-correct fills for blank `i`.
`options` is **only** used by `fillInBlankChoice`; ignored by the others.

### Family 7 — WordOrder (2 types)

The learner re-assembles a sentence from tiles. Tap a tile to add it to the
answer row; tap an answer-row tile to send it back to the pool.

**Types**: `wordOrder` (word tiles), `letterScramble` (letter tiles).

```json
{
  "type": "exercise",
  "exerciseType": "wordOrder",
  "data": {
    "tiles": ["は", "今日", "天気", "いい"],
    "correctOrder": [1, 0, 3, 2],
    "distractors": ["きれい"],
    "translation": "Today the weather is nice."
  }
}
```

`correctOrder` is an array of indices into `tiles`. Length determines how
many slots the learner has to fill. `distractors` are extra wrong tiles
mixed into the pool to make the puzzle harder.

For `letterScramble`, `tiles` is one character per entry.

### Family 8 — Reading (3 types)

A passage followed by 1-N questions. Each question is one of three kinds:
true/false, multiple-choice, or cloze (free-text fill-ins).

**Types**: `readingTrueFalse` (single statement), `readingComprehension`
(passage + multi-choice qs), `readingCloze` (passage + multi-blank).

```json
{
  "type": "exercise",
  "exerciseType": "readingComprehension",
  "data": {
    "passage": "東京は日本の首都です。約1400万人が住んでいます。",
    "glossary": { "首都": "capital", "住んでいます": "live (continuous)" },
    "questions": [
      { "kind": "trueFalse",      "prompt": "Tokyo is in Japan.", "truthy": true },
      {
        "kind": "multipleChoice",
        "prompt": "About how many people live in Tokyo?",
        "options": ["140,000", "1.4 million", "14 million", "140 million"],
        "correctIndex": 2
      }
    ]
  }
}
```

Per-question fields:

| Field | When | Notes |
|---|---|---|
| `kind` | always | `"trueFalse"` / `"multipleChoice"` / `"cloze"` |
| `prompt` | always | The question text |
| `truthy` | trueFalse | The correct answer |
| `options` + `correctIndex` | multipleChoice | 3–5 options |
| `answers` | cloze | One string per blank |

`glossary` is optional and shown in a collapsible panel below the passage.

### Family 9 — Production (2 types)

Free-form writing. The SDK can't grade prose precisely, so the flow is:
write → submit → SDK reveals reference answer + checks any required
keywords + length minimum → user self-grades.

**Types**: `translateSentence` (translate prompt to target language),
`composeSentence` (write your own sentence using a given word).

```json
{
  "type": "exercise",
  "exerciseType": "translateSentence",
  "data": {
    "prompt": { "text": "I drink water every morning." },
    "referenceAnswer": "毎朝水を飲みます",
    "requiredWords": ["毎朝", "水"],
    "minLength": 6,
    "maxLength": 30
  }
}
```

Required keywords are checked case-insensitively. minLength/maxLength
gate the submit button.

### Family 10 — Categorization (2 types)

**Types**:
- `oddOneOut`: 4-N items, the learner taps the one that doesn't belong.
- `categorySort`: items at the bottom, named buckets at the top; the
  learner taps an item then a bucket to drop it in.

```json
{
  "type": "exercise",
  "exerciseType": "oddOneOut",
  "data": {
    "items": ["りんご", "バナナ", "ぶどう", "車"],
    "oddIndex": 3,
    "explanation": "車 is a vehicle; the others are fruits."
  }
}
```

```json
{
  "type": "exercise",
  "exerciseType": "categorySort",
  "data": {
    "items": ["りんご", "車", "バナナ", "電車"],
    "categories": [
      { "name": "fruit",   "items": ["りんご", "バナナ"] },
      { "name": "vehicle", "items": ["車", "電車"] }
    ]
  }
}
```

Each item must belong to exactly one bucket.

### Appendix — `ExerciseMedia`

A reusable shape that any exercise prompt or face can use. Any combination
of fields can be present; the SDK renders whatever is there.

```json
{
  "text": "こんにちは",
  "audio": "media/audio/konnichiwa.mp3",
  "image": "media/images/wave.png"
}
```

---

## 7. Media: audio, images, video

All media lives under `media/` inside your pack folder. Reference each
file by its relative path:

```json
"audio": "media/audio/konnichiwa.mp3"
```

### Audio

- Formats: `mp3`, `m4a`, `wav`, `aac`. `mp3` is the most universal.
- Bitrate: 96–128 kbps mono is plenty for speech. 256 kbps is wasteful.
- Length: keep individual clips under ~30 seconds. For dictation-length
  sentences, ~10 seconds is typical.
- Loudness: aim for −16 LUFS (broadcast standard). Quietest items in your
  pack should still be audible without headphones.
- File names: lowercase, hyphens, no spaces. e.g. `konnichiwa.mp3`,
  `example-tanaka.mp3`.

### Images

- Formats: `png`, `jpg`, `webp`, `heic`. PNG for diagrams; JPG for photos.
- Resolution: keep single images under 1024×1024 unless you really need
  detail. Phones don't render bigger.
- Always provide alt-text via the surrounding `notes` field where possible.

### Video

Permitted by the format (`media/video/`) but **not currently a first-class
SDK feature**. No exercise type renders video today; it's reserved for a
future phase. Don't ship 100 MB of video and expect users to download it.

### Total pack size

Soft cap: **~50 MB**. Hard cap: **500 MB** (registry rejects beyond this).
A 50-lesson pack with audio for every vocabulary item and example
typically lands at 20–40 MB.

---

## 8. Audio strategy

You have two paths and they layer cleanly. Both work offline.

### Path A — TTS only (no recordings shipped)

If your `vocabulary.audio` field is omitted, the SDK falls back to iOS's
built-in `AVSpeechSynthesizer` (the same engine Siri uses). It works
offline for every major language with a "compact" voice that ships in
iOS itself. Users can download higher-quality voices via Settings →
Accessibility → Spoken Content.

**Use this when** you're shipping a v0.1 pack and want to focus on lesson
structure first; you don't have a native speaker handy; or the language
is one of the well-supported ones (EN, ES, JA, KO, DE, FR, IT, PT, ZH,
RU, NL, TR, …).

**Limits**: TTS quality varies. For tonal languages (Mandarin, Vietnamese,
Thai) and subtle prosody-heavy languages (Japanese pitch accent, Korean
intonation), TTS can be misleading. Listening exercises (`listening`,
`dictation`, `listenAndAct`) are NOT eligible for TTS — they have no
fallback because the whole point is hearing native speech.

### Path B — Recorded audio (overrides TTS)

Drop a file in `media/audio/` and reference it from the vocabulary item
or exercise data. The SDK plays the file directly and ignores TTS for
that item.

**Use this when** you want top-quality pronunciation; your pack is aiming
for **Featured / Paktly Originals** placement (recordings are required —
see [§14](#14-featured-curation)); or you're teaching a less common
language whose TTS is rough.

You don't have to record everything. Mix-and-match works: ship recordings
for the words that benefit most (irregular pronunciation, low-frequency
items) and let TTS handle the rest.

### Recording tips

- Native speaker, neutral accent for the target audience.
- Quiet room; phone mic is fine if you're 30 cm away. A USB condenser
  mic is better.
- Trim silence at start/end. Aim for the word/sentence to start within
  100 ms of playback.
- Normalise loudness across all clips in a pack. iZotope RX, Audacity's
  Loudness Normalization, or `ffmpeg -af loudnorm=I=-16:TP=-1.5:LRA=11`
  all work.

---

## 9. Pack id and semver

### Choosing an id

Reverse-DNS, lowercase, hyphens. Once published, **the id can never
change**. Pick something that:

- Includes your handle so it doesn't collide: `com.github.<your-handle>.<slug>`
- Describes the pack content: `…nihongo-beginner`, not `…my-pack`
- Won't embarrass you in 5 years: avoid version numbers in the id (use
  the `version` field for that).

Examples:
- ✓ `com.github.ata.nihongo-beginner`
- ✓ `dev.paktly.originals.ja-n5`
- ✗ `my-pack-v2-final-FINAL`

### Versioning

Every release gets a fresh `version`. The registry **refuses** to overwrite
an existing `id@version` — this is a hard immutability rule. Bug fixes ship
as a new patch version.

You can publish prereleases:
- `1.0.0-alpha.1`, `1.0.0-beta.3`, `1.0.0-rc.2` → all valid.
- The SDK treats prereleases as installable but de-prioritises them in
  search.

---

## 10. License and attribution

### Pick a license

**Recommended**: `CC-BY-4.0` or `CC-BY-SA-4.0`.

| License | What it does |
|---|---|
| `CC-BY-4.0` | Anyone can copy, remix, redistribute, even commercially, **as long as they credit you**. The most permissive while still requiring attribution. |
| `CC-BY-SA-4.0` | Same as `CC-BY` but derivative works must use the same license (copyleft). Good if you want forks to stay open. |
| `CC-BY-NC-4.0` | Non-commercial only. **Not recommended** — incompatible with most platforms. |
| `CC0-1.0` | Public domain. No attribution required. Good for reference packs. |
| `MIT` | Common for code; less common for content but legal. |

You declare the license in `manifest.json`'s `license` field. Include a
`LICENSE` file at the pack root with the full text.

### Third-party content

If your pack uses someone else's audio, images, or text, **you must have
the right to redistribute it** under your chosen license. Public-domain
recordings (e.g. LibriVox), CC-licensed images (Wikimedia Commons), and
your own original recordings are safe. Stock-photo-site images and
copyrighted song lyrics are **not** safe.

When in doubt: record / illustrate it yourself, or skip it.

### Attribution in your README

Best practice: list every external source in the pack's `README.md` with
the original URL and its license.

---

## 11. Publishing

Two paths. Pick whichever fits your workflow.

### Path A — GitHub Release (recommended)

1. Put your pack folder in a public GitHub repo.
2. Build the zip:
   ```bash
   cd ..
   zip -r my-pack-1.0.0.zip my-pack -x "*.DS_Store"
   ```
3. `git tag v1.0.0 && git push --tags`.
4. GitHub → Releases → Draft a new release → pick the tag → upload the
   zip as an asset.
5. Tell Paktly the **repo URL**; the registry pulls the zip from the
   latest release.

This is the cleanest setup: your version control and pack publication
stay synced. Bug-fix commits → new tag → new release → registry picks it
up.

### Path B — Direct ZIP upload

If you don't use GitHub:

1. Zip your pack folder.
2. Authenticate with the registry (`POST /v1/auth/login`).
3. `POST /v1/packs/upload` with the zip as a multipart `pack` field.

The registry validates and stores it. Same id @ same version → 409 Conflict
(immutability). Bump the version and try again.

### Local validation before upload

Validate locally first to catch errors before they hit the registry. The
`paktly` CLI is the recommended way:

```bash
paktly pack validate /path/to/my-pack
# Folder OR pre-built .zip both work
```

Or, if you don't have the CLI built yet:

```bash
cd backend
go run ./cmd/paktly pack validate /path/to/my-pack
```

For machine-readable output (CI / editor integration):

```bash
paktly pack validate --json /path/to/my-pack
```

The `--json` flag emits the same result as the registry's API does, with
each error pointing at a specific JSON pointer inside the offending file.

### The full `paktly` CLI

The CLI is the friendliest way to author packs. Build it once:

```bash
cd backend
go build -o ~/bin/paktly ./cmd/paktly
```

Then anywhere on your machine:

```bash
paktly pack new <slug>          # scaffold a new pack
paktly pack validate <path>     # validate folder or zip
paktly pack publish <path>      # validate + upload to registry
paktly login                    # save token to ~/.config/paktly/config.json
```

Full walkthrough: **[TUTORIAL.md](TUTORIAL.md)**.

---

## 12. Validation checklist

The registry refuses your pack if any of these is violated:

| Check | Error |
|---|---|
| `manifest.json` exists at the archive root (or under one wrapping folder) | `MANIFEST_MISSING` |
| Manifest validates against `manifest.schema.json` | `PACK_VALIDATION_FAILED` |
| Every `lessons[].file` exists in the zip | `PACK_VALIDATION_FAILED` |
| Every lesson validates against `lesson.schema.json` | `PACK_VALIDATION_FAILED` |
| Every `audio` / `image` / `video` reference points to a file that exists in the zip | `PACK_VALIDATION_FAILED` |
| No path tries to escape the pack root (`../../etc/passwd`) | `PACK_VALIDATION_FAILED` |
| Total uncompressed size ≤ 500 MB | `PAYLOAD_TOO_LARGE` |
| `id` is owned by you (or never published before) | `PACK_OWNER_MISMATCH` |
| `id@version` doesn't already exist | `VERSION_EXISTS` |

The `error.fields[]` array lists each failure with a JSON pointer so you
can locate the exact problem.

---

## 13. AI capabilities (Phase 8 preview)

**Phase 8 hasn't shipped yet** — this section is forward-looking. You can
declare AI capabilities now, but the SDK won't act on them until the
multi-provider AI proxy lands.

```json
"aiCapabilities": {
  "questionGeneration": true,
  "explanation": true,
  "conversation": false,
  "hint": true
}
```

| Field | What it means |
|---|---|
| `questionGeneration` | The SDK can ask the AI to invent extra exercise items based on your vocabulary. |
| `explanation` | The learner taps "explain more" and gets a deeper grammar / cultural breakdown. |
| `conversation` | The pack supports a chatbot-style practice mode. |
| `hint` | The exercise UI shows a context-aware hint button. |

If your pack opts in, in Phase 8 it gets:

- A creator dashboard with usage stats per AI feature.
- A per-pack soft cap that protects you from abuse.
- AI cost is billed centrally to Paktly (creators don't pay) — Paktly
  uses a provider mix where DeepSeek is the default, with Gemini as an
  alternative the creator can opt into.

The pack always works fully offline; AI is layered on top.

---

## 14. Featured curation

Paktly's homepage and recommendation surfaces highlight a curated subset
called **Featured** packs (and our own first-party content called
**Paktly Originals**). To be eligible:

| Bar | Required for |
|---|---|
| Recorded audio for every vocabulary item | Featured + Originals |
| At least 50 vocabulary items | Originals |
| Native-speaker quality (no TTS) | Originals |
| At least one example sentence per vocabulary item | Originals |
| Schema 1.2.0 with at least 3 different exercise families used | Originals |
| `aiCapabilities` declared (even all-false is fine) | Featured |
| MIT-compatible license (`CC-BY-4.0` or `CC-BY-SA-4.0`) | Featured |
| Manifest's `description` clearly states the level + audience | Featured |
| At least 5 reviews / a Paktly editorial review | Featured |

Curation is currently manual (a single editor reviews submissions). If
you'd like your pack considered, open an issue on the repo with the
pack id and a one-paragraph pitch.

---

## 15. Worked example

A complete, valid pack — about as small as a publishable pack can be.

```
mini-japanese/
├── manifest.json
├── README.md
├── LICENSE
├── lessons/
│   ├── 001-vowels.json
│   └── 002-greetings.json
└── media/
    └── audio/
        ├── a.mp3
        ├── i.mp3
        ├── u.mp3
        ├── e.mp3
        ├── o.mp3
        └── konnichiwa.mp3
```

### `manifest.json`

```json
{
  "schemaVersion": "1.2.0",
  "id": "com.github.ata.mini-japanese",
  "name": "Mini Japanese",
  "version": "1.0.0",
  "description": "Five vowels, three greetings. Ten minutes total.",
  "language": { "code": "ja", "name": "Japanese", "nativeName": "日本語", "script": "Jpan", "direction": "ltr" },
  "uiLanguage": "tr",
  "level": "A1",
  "author": { "name": "Ata" },
  "license": "CC-BY-SA-4.0",
  "tags": ["japanese", "beginner"],
  "lessons": [
    { "id": "001-vowels",    "file": "lessons/001-vowels.json",    "title": "Vowels",    "order": 1 },
    { "id": "002-greetings", "file": "lessons/002-greetings.json", "title": "Greetings", "order": 2 }
  ],
  "aiCapabilities": { "explanation": true, "hint": true }
}
```

### `lessons/001-vowels.json`

```json
{
  "id": "001-vowels",
  "title": "あいうえお",
  "estimatedMinutes": 4,
  "blocks": [
    {
      "type": "explanation",
      "text": "Japanese has **five vowel sounds**. Each maps to one hiragana symbol."
    },
    {
      "type": "vocabulary",
      "items": [
        { "target": "あ", "translation": "a", "audio": "media/audio/a.mp3", "ipa": "/a/" },
        { "target": "い", "translation": "i", "audio": "media/audio/i.mp3", "ipa": "/i/" },
        { "target": "う", "translation": "u", "audio": "media/audio/u.mp3", "ipa": "/u/" },
        { "target": "え", "translation": "e", "audio": "media/audio/e.mp3", "ipa": "/e/" },
        { "target": "お", "translation": "o", "audio": "media/audio/o.mp3", "ipa": "/o/" }
      ]
    },
    {
      "type": "exercise",
      "exerciseType": "multipleChoiceAudio",
      "prompt": "Hangi harf?",
      "data": {
        "prompt": { "audio": "media/audio/a.mp3" },
        "options": ["あ", "い", "う", "え"],
        "correctIndex": 0
      }
    },
    {
      "type": "exercise",
      "exerciseType": "matching",
      "data": {
        "pairs": [
          { "left": { "text": "あ" }, "right": { "text": "a" } },
          { "left": { "text": "い" }, "right": { "text": "i" } },
          { "left": { "text": "う" }, "right": { "text": "u" } }
        ]
      }
    }
  ]
}
```

### `lessons/002-greetings.json`

```json
{
  "id": "002-greetings",
  "title": "Selamlaşma",
  "estimatedMinutes": 3,
  "blocks": [
    {
      "type": "vocabulary",
      "items": [
        {
          "target": "こんにちは",
          "translation": "merhaba",
          "transliteration": "konnichiwa",
          "audio": "media/audio/konnichiwa.mp3",
          "ipa": "/koɲɲitɕiwa/",
          "examples": [
            { "text": "こんにちは、田中さん", "translation": "Merhaba Tanaka-san" }
          ]
        }
      ]
    },
    {
      "type": "exercise",
      "exerciseType": "typing",
      "data": {
        "prompt": { "text": "merhaba" },
        "answer": "こんにちは",
        "acceptedAlternatives": ["コンニチハ", "konnichiwa"]
      }
    },
    {
      "type": "exercise",
      "exerciseType": "wordOrder",
      "data": {
        "tiles": ["さん", "こんにちは", "田中"],
        "correctOrder": [1, 2, 0],
        "translation": "Hello, Tanaka-san"
      }
    }
  ]
}
```

That's a working pack. Zip it, upload it, you're live.

---

## 16. FAQ

**Q: Can I charge money for my pack?**
A: Not through Paktly. The platform only distributes free, openly-licensed
packs. You're welcome to set up tip jars (GitHub Sponsors, Ko-fi) and
mention them in your `README.md`.

**Q: Can I host my own registry?**
A: Yes — fully supported, first-class. The backend is open source and runs
under `docker compose`. The SDK accepts any base URL. See
`SELF_HOSTING.md` (coming in Phase 5).

**Q: What if my pack uses a language Paktly doesn't have UI translations
for?**
A: Pack content is fully decoupled from the SDK's UI language. You can
write a Klingon pack with `uiLanguage: "en"` (English explanations) and
it works fine on a Turkish-localised app.

**Q: Can I update my pack after publishing?**
A: Yes — bump the `version` and republish. The old version stays available
for users who already downloaded it; new users get the new version.

**Q: Can I delete a pack?**
A: Take-down requests for legal / abuse reasons are honoured. There's no
self-service "delete my pack" button — once content is in the registry,
users may have downloaded it, and we don't want to break their offline
experience without cause.

**Q: What's the minimum SDK version a `1.2.0` pack needs?**
A: `0.3.0` (the version of PaktlyKit that introduced the 30-type catalog).
Set `manifest.minSdkVersion: "0.3.0"` so older SDKs refuse to install
your pack rather than misrendering exercises they don't know about.

**Q: My audio files are huge — what should I do?**
A: Run them through `ffmpeg -i input.wav -codec:a libmp3lame -b:a 96k
output.mp3`. 96 kbps mono is plenty for speech and shrinks files ~10×
versus uncompressed wav.

**Q: How do I test my pack before publishing?**
A: Either point a local SDK build at the file directly (Phase 3g demo
app supports a "load local pack" mode), or run the CLI validator:
`go run ./cmd/validate-pack /path/to/my-pack.zip`.

**Q: Where do I report bugs in the spec or this guide?**
A: <https://github.com/rapoyrazoglu/languageApp/issues>.

---

## 17. New block types (1.2.0)

Three block types were added in 1.2.0. They sit alongside `explanation` /
`vocabulary` / `exercise` and follow the same `{ "type": "...", ... }` shape.
You can mix them freely inside a lesson's `blocks` array.

### 17.1 `dialogue`

A multi-speaker conversation. Use this when a lesson teaches a real-world
exchange (greeting at a register, asking directions, a phone call). Each
line carries its own audio path so the SDK can play one line at a time and,
in a future phase, support role-play mode.

```json
{
  "type": "dialogue",
  "contexts": {
    "tr": "Üniversite kampüsünde tanışan iki öğrenci.",
    "en": "Two students meeting on campus."
  },
  "lines": [
    {
      "speaker": "A",
      "target": "はじめまして。私は田中です。",
      "translations": {
        "tr": "Tanıştığımıza memnun oldum. Ben Tanaka.",
        "en": "Nice to meet you. I'm Tanaka."
      },
      "audio": "media/audio/dialogue-1-a.mp3"
    },
    {
      "speaker": "B",
      "target": "山田です。よろしく。",
      "translation": "I'm Yamada. Pleased to meet you."
    }
  ]
}
```

| Field | Required | Notes |
|---|---|---|
| `lines[]` | ✓ | At least 2 lines. |
| `lines[].target` | ✓ | The line in the target language. |
| `lines[].translation` / `translations` | ⚠️ | At least one of them per line. |
| `lines[].speaker` | — | Free-form label, e.g. `"A"`, `"店員"`, `"Tanaka"`. |
| `lines[].audio` | — | Per-line audio file. |
| `context` / `contexts` | — | Optional setting / scene description shown above the dialogue. |

### 17.2 `kanji`

Kanji character cards. Don't squeeze kanji into vocabulary blocks — kanji
aren't words, they're characters with multiple readings, stroke counts,
radicals, and mnemonic stories. The dedicated block keeps that structure
intact.

```json
{
  "type": "kanji",
  "items": [
    {
      "character": "日",
      "meanings": { "tr": "gün, güneş", "en": "day, sun" },
      "onyomi": ["ニチ", "ジツ"],
      "kunyomi": ["ひ", "-び", "-か"],
      "strokes": 4,
      "jlptLevel": "N5",
      "mnemonics": { "tr": "Bir pencereden gelen güneş." },
      "examples": [
        {
          "word": "今日",
          "reading": "きょう",
          "translations": { "tr": "bugün", "en": "today" }
        }
      ]
    }
  ]
}
```

| Field | Required | Notes |
|---|---|---|
| `character` | ✓ | The kanji glyph (1–8 chars; usually 1). |
| `meaning` / `meanings` | ⚠️ | At least one of them. |
| `onyomi[]` | — | Sino-Japanese readings (typically katakana). |
| `kunyomi[]` | — | Native readings (typically hiragana, with `-` markers for okurigana). |
| `strokes` | — | Integer 1–100. |
| `jlptLevel` | — | `N5` / `N4` / `N3` / `N2` / `N1`. |
| `radicals[]` | — | Component radicals. |
| `mnemonic` / `mnemonics` | — | Memory aid story. |
| `examples[]` | — | Compound words demonstrating the kanji. Each: `word` + `reading?` + `translation`/`translations`. |

### 17.3 `grammar`

Structured grammar pattern. Most grammar-heavy languages (Japanese, Korean,
German, ...) follow a near-standard teaching template:
**[Formation] / [Usage] / [Watch out] / [Related patterns]**. The grammar
block makes that template a first-class structure so the SDK can render each
slot separately (a future phase will let learners filter "show only
examples", jump to related patterns, etc.).

```json
{
  "type": "grammar",
  "pattern": "～は～です",
  "level": "N5",
  "meanings":   { "tr": "~ dır/dir (kibar)", "en": "~ is ~ (polite)" },
  "formations": { "tr": "İsim + は + İsim + です" },
  "usages":     { "tr": "Japonca'nın en temel cümle yapısı." },
  "watchOuts":  { "tr": "は burada 'wa' okunur, 'ha' değil." },
  "related":    ["～は～じゃないです", "～は～でした"],
  "examples": [
    {
      "text": "私は学生です。",
      "translations": { "tr": "Ben öğrenciyim.", "en": "I am a student." }
    }
  ]
}
```

| Field | Required | Notes |
|---|---|---|
| `pattern` | ✓ | The pattern itself, e.g. `"～は～です"`. |
| `meaning` / `meanings` | ⚠️ | One-line gloss; at least one of them. |
| `level` | — | `N5`–`N1` or `A1`–`C2`. |
| `formation` / `formations` | — | How the pattern is built. |
| `usage` / `usages` | — | When to use it (paragraph). |
| `watchOut` / `watchOuts` | — | Common pitfalls / nuance. |
| `examples[]` | — | Sentences using the pattern. Same shape as vocabulary examples. |
| `related[]` | — | Free-form references to related grammar pattern names. |
| `audio` | — | Pronunciation of the archetypal form. |

---

## 18. Mock exams (1.2.0)

Set `examMode: true` at the lesson level to mark the lesson as an
assessment. Use this for chapter-end exams, mid-term tests, or pack-final
quizzes. The SDK changes its behaviour: hints are disabled, the learner
gets one attempt, the score gates pack progress, and the result screen
shows a per-skill breakdown.

```json
{
  "id": "n5-foundations-final",
  "title": "Pack 1 — Final Exam",
  "examMode": true,
  "passingScore": 0.8,
  "timeLimit": 600,
  "drawsFrom": ["001-greetings", "002-pronouns", "003-numbers"],
  "blocks": [
    { "type": "exercise", "exerciseType": "multipleChoice", "data": { /* ... */ } },
    { "type": "exercise", "exerciseType": "typing",         "data": { /* ... */ } },
    { "type": "exercise", "exerciseType": "matching",       "data": { /* ... */ } }
    // ...20 items typical, exercise-only
  ]
}
```

| Field | Required | Notes |
|---|---|---|
| `examMode` | — | `true` to enable exam mode. Default `false`. |
| `passingScore` | — | Score (0..1) needed to clear the exam. Defaults to `0.8` if `examMode: true` and this is omitted. |
| `timeLimit` | — | Seconds. SDK shows a countdown and auto-submits at 0. |
| `drawsFrom[]` | — | Lesson ids this exam covers; the score breakdown labels chapters using these ids. |

**Authoring rules of thumb:**

- Exam lessons should contain **only** `exercise` blocks. No `explanation`,
  no `vocabulary` introductions — the exam tests, it doesn't teach.
- Aim for ~20 items per chapter exam, ~50 for a pack-final.
- Distribution: equal weight per `drawsFrom` chapter is the safe default
  (so a 12-chapter pack-final has ~1.7 items per chapter). If your skill
  tags suggest a different weighting, use them — but make the choice
  deliberately.
- Mix exercise families. A featured-eligible pack-final touches at least
  3 of the 10 families.
- Place the exam lesson last in `manifest.lessons[]` so the path UI ends
  on it; flag the previous lesson as its prerequisite.

---

## 19. Locale coverage and translation provenance (1.2.0)

Two locale signals come out of every 1.2.0 pack — one **derived** from
content, one **declared** by the author. Both surface in the registry's
catalog and in the SDK's UI.

### 19.1 `supportedLocales` and `localeCoverage` (derived)

The registry walks every translatable atom in your pack at ingest time and
produces:

| Signal | What it measures | UI use |
|---|---|---|
| `supportedLocales: ["tr", "en"]` | Locale codes that cover **≥90%** of the *core teaching atoms*. Drives the Discover "For X speakers" filter. | Binary filter signal — pack appears in those locales' catalogs. |
| `localeCoverage: { "tr": 0.996, "en": 0.534, ... }` | Pool-wide fraction (0..1) of *every* translatable atom each locale fills. | Transparency chip — "EN: %53" badge so users know examples may fall back to another locale. |

**Atom-kind allowlist** — these contribute to `supportedLocales`:

- `vocabulary.items[].translations`
- `kanji.items[].meanings`
- `grammar.meanings` / `formations` / `usages` / `watchOuts`

**Pool-only atoms** (count toward `localeCoverage` but NOT toward the
≥90% supported threshold):

- `vocabulary.items[].examples[].translations`
- `dialogue.lines[].translations`, `dialogue.contexts`
- `kanji.items[].examples[].translations`, `kanji.items[].mnemonics`
- `grammar.examples[].translations`

The split exists because example sentences and dialogues are valuable but
heavyweight — a pack whose vocab/grammar/kanji headlines are translated to
EN but whose example sentences are TR-only is **legitimately EN-supported**:
the SDK's locale fallback chain renders examples in the next-best locale,
and the user gets a usable EN learning experience.

### 19.2 `manifest.translationStatus` (declared)

Independent of the derived signals, you declare per-locale **provenance**
in your manifest. This is purely a quality declaration — the registry
trusts you.

```json
"translationStatus": {
  "tr":      "native",
  "en":      "native",
  "de":      "machine",
  "zh-Hans": "machine",
  "es":      "reviewed"
}
```

| Value | Meaning | UI badge |
|---|---|---|
| `native` | Human-authored or curated dictionary source. | none / green tick |
| `machine` | LLM auto-translated, no human review. | "Auto-translated" |
| `reviewed` | Machine-translated, then reviewed by a native speaker. | "Verified" |
| `partial` | Some atoms missing for this locale (e.g. legacy migration). | "Partial" |

Pattern for an evolving pack:

1. **1.0.0** — `{ "tr": "native", "en": "native" }`. Auto-translate not run yet.
2. **1.1.0** — add `{ "de": "machine", "zh-Hans": "machine", "es": "machine" }` after a Gemini/DeepSeek pass.
3. **1.2.0** — promote DE to `"reviewed"` once a native speaker has gone over the auto output.

The registry ingests `translationStatus` verbatim; immutability still
applies (every version is its own row).

### 19.3 Reading the CLI output

`paktly pack validate` shows both signals on a successful run:

```
OK   ./genki1
     id=dev.paktly.originals.ja-genki1  version=1.0.0  schema=1.2.0
     size=2.3MB  sha256=ab12cd34ef56…
     lessons=13  ai=questionGeneration,explanation,hint
     supportedLocales=en,tr
     localeCoverage=tr=99.6% en=53.4% de=38.8% es=38.8% zh-Hans=38.8%
```

Read this as: the pack ships full TR (vocab/grammar/kanji headlines AND
examples), full EN core (headlines), but EN examples are TR-only — so EN
users will see Japanese targets translated to English in vocab cards but
example sentences in Turkish until you fill the gap in a follow-up version.
