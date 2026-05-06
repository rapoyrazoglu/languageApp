# Creator API & operations guide

> **Audience**: anyone who has a pack ready to publish on Paktly. Solo authors,
> service accounts (Originals workflow), self-hosters who run their own
> registry.
>
> **Pairs with**: [AUTHORING.md](AUTHORING.md) — what a pack is and how to
> write one. This document picks up where that ends: how to ship, monitor,
> and evolve packs against a live registry.
>
> **Authoritative contract**: [openapi.yaml](openapi.yaml). When this doc and
> the OpenAPI spec disagree, OpenAPI wins.

---

## Contents

1. [Quick start — first publish in 5 commands](#1-quick-start--first-publish-in-5-commands)
2. [Authentication](#2-authentication)
3. [Pack lifecycle](#3-pack-lifecycle)
4. [GitHub Release ingest (Path A)](#4-github-release-ingest-path-a)
5. [Coverage signals](#5-coverage-signals)
6. [`translationStatus` lifecycle](#6-translationstatus-lifecycle)
7. [Audit log](#7-audit-log)
8. [Rate limits](#8-rate-limits)
9. [Error codes](#9-error-codes)
10. [`paktly` CLI cheat-sheet](#10-paktly-cli-cheat-sheet)
11. [End-to-end example — Genki I publish](#11-end-to-end-example--genki-i-publish)
12. [FAQ / troubleshooting](#12-faq--troubleshooting)
13. [Self-hosting your own registry](#13-self-hosting-your-own-registry)

---

## 1. Quick start — first publish in 5 commands

```bash
# 1. Build the CLI once (until pre-built releases ship at v1.0)
cd /path/to/languageApp/backend
go build -o ~/bin/paktly ./cmd/paktly
export PATH="$HOME/bin:$PATH"

# 2. Register an account on the production registry
curl -X POST https://api.paktly.dev/v1/auth/register \
  -H 'Content-Type: application/json' \
  -d '{"email":"you@example.com","password":"correct horse battery staple"}'

# 3. Save the token locally for the CLI
paktly login --registry https://api.paktly.dev

# 4. Validate the pack you've authored (folder OR pre-built .zip)
paktly pack validate ./my-pack

# 5. Publish — same id+version is rejected (immutability), bump on revisions
paktly pack publish ./my-pack
```

That's the whole loop. Re-publishes for the same `id@version` are rejected —
bump `manifest.version` and try again.

---

## 2. Authentication

The registry issues short-lived JWTs. Every authenticated endpoint expects
`Authorization: Bearer <token>`.

### Register

```http
POST /v1/auth/register
Content-Type: application/json

{ "email": "you@example.com", "password": "correct horse battery staple" }
```

Returns `201 Created` with a `tokenResp`:

```json
{
  "token": "eyJhbGciOi...",
  "expiresAt": "2026-05-13T12:00:00Z",
  "user": { "id": "...", "email": "you@example.com" }
}
```

`409 EMAIL_TAKEN` if the email is already registered.

### Log in

```http
POST /v1/auth/login
Content-Type: application/json

{ "email": "you@example.com", "password": "..." }
```

Same `tokenResp` shape. `401 UNAUTHORIZED` on bad credentials.

### Inspect the active token

```http
GET /v1/auth/me
Authorization: Bearer <token>
```

Returns the user record. `401 TOKEN_EXPIRED` once the JWT is past its
expiry.

### CLI helpers

```bash
paktly login --registry https://api.paktly.dev
# prompts for email + password, exchanges them for a token,
# writes ~/.config/paktly/config.json (chmod 0600)

paktly login --token "$PAKTLY_TOKEN"
# skips the prompt; useful in CI where the token comes from a secret
```

The CLI's stored config:

```jsonc
// ~/.config/paktly/config.json
{
  "registry": "https://api.paktly.dev",
  "token":    "eyJhbGciOi...",
  "expiresAt":"2026-05-13T12:00:00Z"
}
```

Token TTL is 7 days. The CLI doesn't auto-refresh — you re-login when
`paktly` reports `401 TOKEN_EXPIRED`. For service accounts in CI, mint a
fresh token at the start of every workflow run.

### Service accounts (Originals & maintained packs)

A pack id is owned by the **first user** to publish it; subsequent uploads
from a different user fail with `PACK_OWNER_MISMATCH`. To keep namespaces
clean for first-party content, the convention is:

1. Create a dedicated registry account (e.g. `paktly-originals@paktly.dev`).
2. Publish all packs in `dev.paktly.originals.*` from that account.
3. Mint a long-lived JWT (or rotate weekly) and store it as a CI secret
   on the source repo (`PAKTLY_ORIGINALS_TOKEN`).
4. CI workflow runs `paktly login --token "$PAKTLY_ORIGINALS_TOKEN"` and
   then `paktly pack publish` — the personal account of whoever wrote the
   content stays out of the publish path.

See [ORIGINALS_OPS.md](ORIGINALS_OPS.md) for the full ops runbook.

---

## 3. Pack lifecycle

A pack moves through these states from authoring to user-visible:

```
  authored               validated              published                 audited
  ────────               ─────────              ─────────                 ───────
  manifest.json     →    paktly pack       →   paktly pack          →   audit log
  + lessons/             validate <path>       publish <path>            tracks every
  + media/                  ↓                      ↓                     publish/update
                        no errors                stored on S3            with timestamp,
                                                 row in pack_versions    source, IP, UA
                                                 webhook → discoverable
```

### Validate

Lokal validation runs the same JSON Schema and same media-reference walker
the registry does — passing `paktly pack validate` locally guarantees the
registry won't reject your zip for structural reasons. (It can still reject
on ownership / version conflicts; those are server-side.)

```bash
paktly pack validate ./my-pack            # human-readable output
paktly pack validate --json ./my-pack     # machine-readable, for CI / editors
```

Output on success:

```
OK   ./my-pack
     id=com.github.you.my-pack  version=1.0.0  schema=1.2.0
     size=2.3MB  sha256=ab12cd34ef56…
     lessons=13  ai=questionGeneration,explanation,hint
     supportedLocales=en,tr
     localeCoverage=tr=99.6% en=53.4% de=38.8% es=38.8% zh-Hans=38.8%
```

The last two lines appear on schema 1.2.0+ packs that ship multi-locale
`translations` maps — see [§5](#5-coverage-signals).

### Publish

```bash
paktly pack publish ./my-pack             # validates first, then uploads
paktly pack publish ./my-pack.zip         # already-zipped works too
```

Under the hood: zips the folder (skipping dotfiles), runs validate, posts
multipart to `POST /v1/packs/upload`. Outcome:

| HTTP | Meaning |
|---:|---|
| `201 Created` | First publish for a brand-new id |
| `200 OK` | New version on an id you already own |
| `403 PACK_OWNER_MISMATCH` | id exists, owned by someone else |
| `409 VERSION_EXISTS` | exact id@version already published — bump `version` |
| `413 PAYLOAD_TOO_LARGE` | exceeds 500 MB hard cap |
| `422 PACK_VALIDATION_FAILED` | server-side validation found errors; `error.fields[]` lists each |

### Version bump rules

Stick to semver discipline — the SDK and registry rely on it:

| Bump | When |
|---|---|
| **major** | Lesson removed, lesson `id` changed, or pack restructured enough to confuse a returning learner |
| **minor** | New lesson added, new vocabulary, new exercise type used |
| **patch** | Typo fixes, audio re-recordings, single-string corrections, `translationStatus` upgrades |

Pre-releases (`1.0.0-beta.3`, `1.0.0-rc.1`, …) are valid but de-prioritised
in search.

### Immutability

The registry will **never** overwrite a published `id@version`. Bug fixes
ship as new versions. Old versions stay accessible to clients that already
downloaded them — this is intentional, so a user's offline study experience
doesn't break when an author republishes.

---

## 4. GitHub Release ingest (Path A)

If your pack lives in a public GitHub repo, you don't need to upload zips
manually. Tag a release; the registry pulls the asset.

### One-shot manual import

```http
POST /v1/packs/import-github
Authorization: Bearer <token>
Content-Type: application/json

{ "repoUrl": "https://github.com/you/my-pack" }
```

The registry calls the GitHub API, finds the latest release, downloads the
first `.zip` asset under the size cap, runs the same validation pipeline,
and inserts. Same response shape and error codes as `/v1/packs/upload`.

### Continuous: webhook subscription

Subscribe once; every subsequent `pack-v*` tag pushes a webhook that the
registry verifies (HMAC-SHA256) and ingests automatically.

```http
POST /v1/webhooks/subscriptions
Authorization: Bearer <token>
Content-Type: application/json

{
  "repoOwner": "you",
  "repoName":  "my-pack",
  "secret":    "<32-char random string — store this; you'll set the same secret in GitHub>"
}
```

Then on the GitHub side: **Settings → Webhooks → Add webhook**

- Payload URL: `https://api.paktly.dev/v1/webhooks/github`
- Content type: `application/json`
- Secret: same `secret` you sent in the subscription
- Events: only `Releases` (publishing a new release fires the webhook)

The registry verifies the HMAC signature before ingesting; bad signatures
return `401` and never touch S3 / DB.

List / delete subscriptions:

```http
GET    /v1/webhooks/subscriptions             # auth required, returns yours
DELETE /v1/webhooks/subscriptions/{owner}/{repo}
```

### When to use which

- **Manual `/v1/packs/upload`** — local-only authoring, no GitHub repo, or
  one-off uploads of pre-built zips
- **`/v1/packs/import-github`** — pack lives on GitHub but you publish on
  your own schedule; you call this when you're ready
- **Webhook subscription** — fully automated; tagging the source repo is
  the publish trigger

Originals workflow combines #2 and #3: webhook subscribes to the source
repo, but the editor service account owns the namespace — see
[ORIGINALS_OPS.md](ORIGINALS_OPS.md).

---

## 5. Coverage signals

The registry walks every translatable string in your lesson content at
ingest time and produces two locale signals. Both live on the
`pack_versions` row and surface in the API response:

### `supportedLocales: string[]`

Locale codes that cover **≥90%** of the *core teaching atoms* (atom-kind
allowlist). Drives the Discover "For X speakers" filter — a pack appears
in those locales' catalog surfaces.

**Atoms that count toward the allowlist:**

- `vocabulary.items[].translations`
- `kanji.items[].meanings`
- `grammar.meanings` / `formations` / `usages` / `watchOuts`

**Atoms that don't** (they count toward `localeCoverage` but not the
support threshold):

- vocabulary `examples[].translations`
- `dialogue.lines[].translations`, `dialogue.contexts`
- kanji `examples[].translations`, kanji `mnemonics`
- grammar `examples[].translations`

The split exists because example sentences and dialogues are valuable but
heavyweight content. A pack with English vocabulary headlines but
Turkish-only example sentences is **legitimately EN-supported**: the SDK's
locale fallback chain renders examples in the next-best locale, the
learner gets a usable EN experience.

### `localeCoverage: { [locale]: number }`

Pool-wide fraction (0..1) of *every* translatable atom each locale fills.
Surfaced as a transparency chip in the SDK ("EN: 53%") so users can see
when example sentences fall back to another locale before downloading.

### Reading both signals

```jsonc
{
  "id": "dev.paktly.originals.ja-genki1",
  "supportedLocales": ["en", "tr"],
  "localeCoverage": {
    "tr":      0.996,
    "en":      0.534,
    "de":      0.388,
    "zh-Hans": 0.388,
    "es":      0.388
  }
}
```

Read this as: TR is fully covered (vocab + examples + dialogues); EN
covers the headlines (`supportedLocales`) but only ~half the pool —
example sentences are still in TR.

### Legacy 1.0.0 / 1.1.0 packs

A pack that ships only the legacy single-string `translation` (no
`translations` map) reports **zero supported locales**. The registry can't
know which locale that string is in. Migrate to `translations` maps to
opt into the catalog filter — see [AUTHORING.md §5](AUTHORING.md#5-vocabulary-blocks).

---

## 6. `translationStatus` lifecycle

Independent of the derived `supportedLocales` / `localeCoverage`, you
declare per-locale **provenance** in your manifest. This is a quality
signal — the registry trusts you, and the SDK uses it for badging.

```jsonc
"translationStatus": {
  "tr":      "native",
  "en":      "native",
  "de":      "machine",
  "zh-Hans": "machine",
  "es":      "reviewed"
}
```

Enum: `native` / `machine` / `reviewed` / `partial` — full meaning in
[AUTHORING.md §19](AUTHORING.md#19-locale-coverage-and-translation-provenance-120).

### Common evolution pattern

```
1.0.0   { tr: native, en: native }                 — original release
1.1.0   + { de: machine, zh-Hans: machine, es: machine }
                                                    — auto-translate sprint
1.1.1   { de: reviewed }                            — native speaker pass on DE
1.1.2   { de: native }                              — DE fully native after edits
1.2.0   adds new lessons; locales preserved
```

Each `translationStatus` change is a manifest edit → patch version bump.
The SDK shows badges accordingly: "Auto-translated" for `machine`,
"Verified" for `reviewed`, no badge for `native`.

---

## 7. Audit log

Every publish / update writes a row to `pack_audit_log`. The pack owner
can read it via:

```http
GET /v1/packs/{id}/audit
Authorization: Bearer <token>
```

Returns a chronological array:

```jsonc
[
  {
    "packId": "com.github.you.my-pack",
    "version": "1.0.0",
    "action": "publish",
    "source": "upload",
    "userId": "...",
    "ipAddress": "203.0.113.42",
    "userAgent": "paktly-cli/0.3.0",
    "createdAt": "2026-05-06T19:00:00Z"
  },
  {
    "packId": "com.github.you.my-pack",
    "version": "1.0.1",
    "action": "update",
    "source": "github",
    "sourceUrl": "https://github.com/you/my-pack/releases/download/v1.0.1/my-pack-1.0.1.zip",
    "userId": "...",
    "createdAt": "2026-05-08T10:00:00Z"
  }
]
```

`403 FORBIDDEN` if you're not the pack owner.

Useful for: catching unexpected ingests, verifying webhook firings, IP
forensics if a CI token is suspected leaked.

---

## 8. Rate limits

Token-bucket per principal:

| Principal | Default capacity | Default refill |
|---|---:|---:|
| Anonymous (per IP) | 60 / minute | 1 / sec |
| Authenticated (per user) | 600 / minute | 10 / sec |

When you exhaust the bucket the response is `429 RATE_LIMITED` with a
`Retry-After: <seconds>` header. The CLI doesn't auto-retry — handle the
sleep in your CI script if you're hitting limits (you usually aren't —
typical publish flow is a handful of requests).

Self-hosted registries can override via env: `RATE_LIMIT_ANON_PER_MIN`,
`RATE_LIMIT_USER_PER_MIN`.

---

## 9. Error codes

Every error response uses a single shape:

```jsonc
{
  "error": {
    "code": "PACK_VALIDATION_FAILED",
    "message": "human-readable summary",
    "fields": [
      { "path": "lessons/001.json#/blocks/0/items/2", "message": "missing translation" }
    ]
  }
}
```

`fields[]` is present only on validation errors and lists every offending
location with a JSON pointer.

| Code | HTTP | When |
|---|:---:|---|
| `BAD_REQUEST` | 400 | Generic bad input — e.g. malformed multipart |
| `INVALID_JSON` | 400 | JSON body didn't parse |
| `MISSING_FIELD` | 400 | Required field absent |
| `UNAUTHORIZED` | 401 | Missing or invalid auth header |
| `TOKEN_EXPIRED` | 401 | JWT past its expiry — re-login |
| `FORBIDDEN` | 403 | Authenticated but not allowed (e.g. someone else's audit log) |
| `NOT_FOUND` | 404 | Pack / version / endpoint doesn't exist |
| `CONFLICT` | 409 | Generic state conflict |
| `EMAIL_TAKEN` | 409 | Registration with an existing email |
| `VERSION_EXISTS` | 409 | Republishing the same `id@version` — bump version |
| `PACK_OWNER_MISMATCH` | 403 | Uploading to an id someone else owns |
| `PACK_VALIDATION_FAILED` | 422 | Pack failed schema / media / structure checks; `fields[]` populated |
| `PAYLOAD_TOO_LARGE` | 413 | Pack zip exceeds the 500 MB hard cap |
| `RATE_LIMITED` | 429 | Token bucket empty; `Retry-After` header included |
| `BAD_GATEWAY` | 502 | Registry hit an upstream issue (e.g. GitHub API for `/import-github`) |
| `INTERNAL` | 500 | Unexpected server error — please report |

---

## 10. `paktly` CLI cheat-sheet

```bash
paktly help                    # full subcommand list
paktly version                 # version banner

# auth
paktly login                                 # interactive
paktly login --registry <url>                # custom registry (self-hosting)
paktly login --token "$JWT"                  # CI / scripted

# packs
paktly pack new <slug>                       # scaffold a fresh pack
paktly pack new <slug> --interactive         # prompts for fields
paktly pack validate <path>                  # folder OR .zip
paktly pack validate --json <path>           # machine output
paktly pack publish <path>                   # validate + upload
paktly pack publish --skip-validate <path>   # not recommended
```

Build the binary once:

```bash
cd backend && go build -o ~/bin/paktly ./cmd/paktly
```

(Pre-built releases at <https://github.com/rapoyrazoglu/languageApp/releases>
arrive once the project hits 1.0.0.)

---

## 11. End-to-end example — Genki I publish

Concrete walkthrough with the production registry + a service account.
Adapt for your own pack by replacing identifiers.

### Setup (once)

```bash
# 1. Service account registration (Originals — see ORIGINALS_OPS.md)
curl -X POST https://api.paktly.dev/v1/auth/register \
  -H 'Content-Type: application/json' \
  -d '{
    "email":    "paktly-originals@paktly.dev",
    "password": "<long random>"
  }'
# → tokenResp with the first JWT

# 2. Save the JWT as a GitHub Actions secret on the source repo
gh secret set PAKTLY_ORIGINALS_TOKEN \
  --repo rapoyrazoglu/nihongo \
  --body "$(jq -r .token <<< "$registration_response")"

# 3. Subscribe a webhook so future tags auto-publish
WEBHOOK_SECRET=$(openssl rand -hex 16)
curl -X POST https://api.paktly.dev/v1/webhooks/subscriptions \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d "{
    \"repoOwner\": \"rapoyrazoglu\",
    \"repoName\":  \"nihongo\",
    \"secret\":    \"$WEBHOOK_SECRET\"
  }"
# Then add the webhook on GitHub side with the same secret.
```

### Per-release flow (handled by CI)

`.github/workflows/publish-pack.yml` on `rapoyrazoglu/nihongo`:

```yaml
name: Publish Paktly pack
on:
  push:
    tags: ['pack-v*']
jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build pack zip
        run: ./tools/build_paktly_pack/build.sh
      - name: Publish via paktly CLI
        env:
          PAKTLY_ORIGINALS_TOKEN: ${{ secrets.PAKTLY_ORIGINALS_TOKEN }}
        run: |
          paktly login --registry https://api.paktly.dev \
                       --token "$PAKTLY_ORIGINALS_TOKEN"
          paktly pack publish ./dist/genki1
```

After `git tag pack-v1.0.0 && git push --tags`:

1. CI builds the zip
2. `paktly pack publish` validates locally, uploads
3. Registry stores the zip on S3 (`packs/dev.paktly.originals.ja-genki1/1.0.0.zip`)
4. Pack appears in `GET /v1/packs?language=ja` immediately
5. iOS demo app (Discover tab) shows it under TR + EN filters
6. Audit log records the publish under the editor service account

### Verifying the result

```bash
# Public read — anyone can hit this
curl https://api.paktly.dev/v1/packs/dev.paktly.originals.ja-genki1 | jq

# Owner-only audit
curl -H "Authorization: Bearer $TOKEN" \
  https://api.paktly.dev/v1/packs/dev.paktly.originals.ja-genki1/audit | jq

# Download the zip (presigned URL)
curl -L "$(curl https://api.paktly.dev/v1/packs/dev.paktly.originals.ja-genki1/versions/1.0.0/download | jq -r .url)" \
  -o genki1-1.0.0.zip
```

---

## 12. FAQ / troubleshooting

**Q: `paktly login` says `401 UNAUTHORIZED` even though the password's right.**
A: The registry treats unverified emails as inactive in some operator
configurations; check `GET /v1/auth/me` after logging in elsewhere. On
`api.paktly.dev` (public registry) verification is currently off, so this
usually means a typo.

**Q: Webhook fires but registry returns `401`.**
A: HMAC signature mismatch. The `secret` in the GitHub webhook config must
match the `secret` you sent in `POST /v1/webhooks/subscriptions` exactly —
no leading/trailing whitespace, same character set.

**Q: `409 VERSION_EXISTS` when retrying a failed publish.**
A: An earlier attempt actually committed the pack version (e.g. before a
network blip). Either bump the patch and try again, or check the audit
log to confirm what's already there.

**Q: `403 PACK_OWNER_MISMATCH` on first publish.**
A: Someone else registered the id namespace before you. Pick a different
prefix (include your handle, e.g. `com.github.your-handle.your-pack`).
For squatted official-looking ids, open an issue on the repo for editor
review.

**Q: My pack is 12 MB but uploading takes minutes.**
A: Check rate limit headers — you might be sharing an IP with other
clients. Authenticated upload has a 10x larger budget than anonymous.

**Q: Can I delete a published version?**
A: There's no self-service delete. Take-down requests for legal / abuse
reasons are honoured by the editor — open an issue. Bug fixes are always
"new patch version", not retraction.

**Q: How do I test against a self-hosted registry?**
A: `paktly login --registry http://localhost:8080` works. Flip the
`Authorization` header to point at your stack, the rest is identical.
See [§13](#13-self-hosting-your-own-registry).

**Q: Can I publish multiple locales of the same pack?**
A: Yes — that's exactly the multi-locale `translations` map flow (schema
1.2.0+). One pack, many locales, derived `supportedLocales` makes it
discoverable in each. See [AUTHORING.md §5](AUTHORING.md#5-vocabulary-blocks).

---

## 13. Self-hosting your own registry

The whole stack runs under `docker compose`:

```bash
git clone https://github.com/rapoyrazoglu/languageApp
cd languageApp/backend
cp .env.example .env
# edit JWT_SECRET (run: openssl rand -base64 48)
make up         # postgres + minio + bucket seed
make migrate-up
make run        # http://localhost:8080
```

Point the CLI at it:

```bash
paktly login --registry http://localhost:8080
paktly pack publish ./my-pack
```

Point an iOS / Android client at it by setting the `RegistryClient` base
URL (in PaktlyKit, this is just an `init` parameter — the SDK is fully
registry-agnostic).

A full walkthrough including AWS-style production deployment is planned
for `docs/SELF_HOSTING.md` (Phase 5). The AWS deployment runbook for
hosted Paktly is at [AWS_SETUP.md](AWS_SETUP.md) — adapt to your account.

---

## Where to ask

- Bug reports / feature requests: <https://github.com/rapoyrazoglu/languageApp/issues>
- Originals operations: see [ORIGINALS_OPS.md](ORIGINALS_OPS.md)
- Pack format questions: [AUTHORING.md](AUTHORING.md)
- Live status: <https://status.paktly.dev> (planned)
