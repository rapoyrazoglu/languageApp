# Build your first pack in 30 minutes

This is a hands-on walkthrough — you'll go from zero to a published pack on
the registry in under half an hour. Every command in this tutorial is real;
copy and run them.

If you want the full reference instead of a tutorial, jump to
[AUTHORING.md](AUTHORING.md). If you've never used a terminal before, skim
[GETTING_STARTED.md](GETTING_STARTED.md) first.

**What you'll build**: a tiny Japanese pack — three vocabulary words and one
flashcard exercise — that any Paktly-compatible app can install and study.

## Prerequisites

- macOS or Linux terminal
- Go 1.22+ installed (`go version` to check)
- A text editor
- A free [GitHub account](https://github.com/) (used as your Paktly login)

If you've cloned this repo, you already have everything else. If not:

```bash
git clone https://github.com/rapoyrazoglu/languageApp.git
cd languageApp
```

## Step 1 — Build the `paktly` CLI (1 minute)

The CLI is a Go binary that ships in this repo. Build it once and put it on
your `$PATH`:

```bash
cd backend
go build -o ~/bin/paktly ./cmd/paktly
export PATH="$HOME/bin:$PATH"   # add to ~/.zshrc to make permanent

paktly version
# paktly 0.3.0
```

(Pre-built releases will arrive at <https://github.com/rapoyrazoglu/languageApp/releases>
once the project hits 1.0; until then it's `go build`.)

## Step 2 — Scaffold a new pack (1 minute)

```bash
cd ~  # or wherever you keep projects

paktly pack new nihongo-greetings \
  --id com.github.YOUR_HANDLE.nihongo-greetings \
  --name "Japanese Greetings" \
  --description "Three essential greetings for absolute beginners." \
  --language ja \
  --ui-language en \
  --level A1 \
  --author "Your Name"
```

Replace `YOUR_HANDLE` with your GitHub username. The CLI creates a folder
`nihongo-greetings/` with everything you need:

```
nihongo-greetings/
├── manifest.json       — pack identity card (already filled in)
├── README.md           — for humans browsing the pack
├── LICENSE             — CC-BY-4.0 boilerplate (edit if you want)
├── lessons/
│   └── 001-getting-started.json — sample lesson (you'll edit this)
└── media/
    ├── audio/          — empty, drop .mp3 files here
    └── images/         — empty
```

If you'd rather scaffold interactively (no flags), just run `paktly pack new
nihongo-greetings` and the CLI prompts for each field.

## Step 3 — Open the pack and edit the sample lesson (10 minutes)

```bash
cd nihongo-greetings
code .   # or `xed .`, or open with any text editor
```

Open `lessons/001-getting-started.json`. Replace it with this:

```json
{
  "id": "001-getting-started",
  "title": "Three essential greetings",
  "description": "こんにちは, おはよう, こんばんは — the three greetings you'll use every day.",
  "estimatedMinutes": 6,
  "blocks": [
    {
      "type": "explanation",
      "text": "Japanese greetings change with the time of day. Use **おはよう** in the morning, **こんにちは** during daylight hours, and **こんばんは** after dark. They're informal — add **ございます** to おはよう and you get the polite form."
    },
    {
      "type": "vocabulary",
      "items": [
        {
          "target": "おはよう",
          "translation": "good morning",
          "transliteration": "ohayō",
          "ipa": "/ohajoː/",
          "notes": "Used until ~10am. Add ございます (gozaimasu) for polite contexts."
        },
        {
          "target": "こんにちは",
          "translation": "hello / good afternoon",
          "transliteration": "konnichiwa",
          "ipa": "/koɲɲitɕiwa/",
          "notes": "Roughly noon to ~5pm."
        },
        {
          "target": "こんばんは",
          "translation": "good evening",
          "transliteration": "konbanwa",
          "ipa": "/kombaɴwa/",
          "notes": "After dark."
        }
      ]
    },
    {
      "type": "exercise",
      "exerciseType": "multipleChoice",
      "prompt": "Which greeting fits 8am?",
      "data": {
        "prompt": { "text": "It's 8am. Your colleague says...?" },
        "options": ["おはよう", "こんにちは", "こんばんは", "さようなら"],
        "correctIndex": 0,
        "explanation": "おはよう is the morning greeting."
      }
    },
    {
      "type": "exercise",
      "exerciseType": "matching",
      "data": {
        "pairs": [
          { "left": { "text": "おはよう" },   "right": { "text": "morning" } },
          { "left": { "text": "こんにちは" }, "right": { "text": "afternoon" } },
          { "left": { "text": "こんばんは" }, "right": { "text": "evening" } }
        ]
      }
    }
  ]
}
```

**What's in this lesson:**

- **Explanation block** — your teaching moment. Markdown is supported.
- **Vocabulary block** — three items, each with target / translation /
  transliteration / IPA / notes. No audio yet — Paktly's iOS SDK will fall
  back to system TTS until you record some.
- **Multiple-choice exercise** — one of 30 exercise types. The runner
  shows the prompt, lists the options, marks the right answer after submit.
- **Matching exercise** — tap-to-pair drill.

Save the file and move on.

## Step 4 — Validate locally (10 seconds)

Before uploading, run the same validator the registry uses:

```bash
paktly pack validate .
```

You should see:

```
OK   .
     id=com.github.YOUR_HANDLE.nihongo-greetings  version=0.1.0  schema=1.2.0
     size=2.4KB  sha256=ab12cd34ef56…
     lessons=1  ai=none
```

If you see `FAIL` instead, the CLI prints each error with a JSON pointer
showing exactly where the problem is:

```
FAIL .
  lessons/001-getting-started.json#/blocks/2/data
    correctIndex must be < length of options
```

Fix and re-run. Common errors:

- Missing required field (e.g. `target` or `translation` on a vocab item)
- `correctIndex` pointing past the end of `options`
- Unknown exercise type (typo in `exerciseType`)
- Media reference to a file that doesn't exist (e.g. `audio: "media/audio/missing.mp3"`)

## Step 5 — Authenticate against the registry (1 minute)

Create an account on the registry (or log into an existing one):

```bash
paktly login --registry https://api.paktly.dev
```

Enter your email and password. The CLI saves the token to
`~/.config/paktly/config.json` (chmod 0600) so you only do this once.

Don't have an account yet? Register via the API directly:

```bash
curl -X POST https://api.paktly.dev/v1/auth/register \
  -H 'Content-Type: application/json' \
  -d '{"email":"you@example.com","password":"correct horse battery staple"}'
```

This returns a token. Then `paktly login` to save it locally, OR set
`PAKTLY_TOKEN` env var directly.

## Step 6 — Publish (10 seconds)

```bash
paktly pack publish .
```

The CLI runs validation again (always — even with `--skip-validate` we'd
warn loudly), zips your folder, posts the multipart upload, and decodes
the response:

```
PUBLISHED  com.github.YOUR_HANDLE.nihongo-greetings@0.1.0
           sha256=ab12cd34ef56…  size=2.4KB
           registry=https://api.paktly.dev
```

Your pack is now live. Anyone with the Paktly iOS app can search for
"japanese" or "greetings" and download it instantly.

## Step 7 — Verify in the iOS demo (2 minutes)

Open the Paktly demo app on your iPhone or simulator
(`xed ios/Demo/PaktlyDemo/PaktlyDemo.xcodeproj`, ⌘R), tap the **Discover**
tab, search for your pack name. Tap it → tap **Install** → tap **Open** →
your lesson runs end-to-end with the explanation, vocabulary cards, and
both exercises.

Test on a real device too — the audio fallback uses iOS's built-in TTS,
so even without recordings, your three greetings will be spoken aloud
in Japanese (the system pronunciation isn't perfect but it's a starting
point).

## Step 8 — Iterate (the rest of forever)

Once you've shipped 0.1.0, you can:

- **Add audio** — record native-speaker pronunciations (your phone's voice
  memos app + 30 seconds of editing in Audacity is enough). Drop them into
  `media/audio/`, reference from each vocab item's `audio` field, then bump
  the version to `0.1.1` and `paktly pack publish .`.

- **Add more lessons** — copy `lessons/001-getting-started.json` to
  `lessons/002-...json`, write new content, list it in `manifest.json`'s
  `lessons` array, bump to `0.2.0` (minor — new content), publish.

- **Use richer exercise types** — try `dictation` (audio → typed answer),
  `wordOrder` (drag tiles into a sentence), `readingComprehension` (passage
  + multi-choice questions). All 30 types are documented in
  [AUTHORING.md §6](AUTHORING.md#6-exercise-types--the-30-catalog).

- **Apply for featured placement** — once your pack has at least 50
  vocabulary items, recorded native audio for every item, and three
  different exercise families used, open an issue on the repo to request
  Featured curation. (Editor: Ata.)

## What can go wrong

| Problem | Likely cause |
|---|---|
| `paktly: command not found` | Binary not on `$PATH`. Check `which paktly` and `echo $PATH`. |
| `registry rejected upload (403 PACK_OWNER_MISMATCH)` | Your `id`'s namespace is owned by another account. Pick a fresh `id` (e.g. include your GitHub username in the reverse-DNS path). |
| `registry rejected upload (409 VERSION_EXISTS)` | You already published this id+version. Bump `version` in `manifest.json` and try again. |
| `paktly login` returns `401 UNAUTHORIZED` | Wrong email/password. Or the registry is reachable but your account doesn't exist yet — register via the curl snippet above. |
| TTS sounds wrong on iOS | Some less-common languages need premium voices. Tell users to download via Settings → Accessibility → Spoken Content → Voices. |

## Beyond this tutorial

- [AUTHORING.md](AUTHORING.md) — full reference, every field, every exercise type
- [PACK_FORMAT.md](PACK_FORMAT.md) — the spec itself (schema 1.2.0)
- [docs/openapi.yaml](openapi.yaml) — REST API contract if you want to integrate beyond the CLI
- [GitHub issues](https://github.com/rapoyrazoglu/languageApp/issues) — bugs, feature requests, featured curation

Have fun. Ship something useful.
