# Originals operations runbook

> **Audience**: Paktly editor (the operator running first-party content,
> currently Ata). NOT for community-pack creators — see [CREATOR_API.md](CREATOR_API.md)
> for the creator-facing flows.
>
> **Purpose**: How to manage the `dev.paktly.originals.*` namespace —
> service account, GitHub Actions integration, quality gates, takedown.
> When a second editor is onboarded, this is the doc that bootstraps them.

---

## Contents

1. [Mental model](#1-mental-model)
2. [The `paktly-originals` service account](#2-the-paktly-originals-service-account)
3. [Namespace claim — first publish](#3-namespace-claim--first-publish)
4. [GitHub Actions integration](#4-github-actions-integration)
5. [Webhook subscription](#5-webhook-subscription)
6. [Originals quality gates](#6-originals-quality-gates)
7. [Takedown / version retraction](#7-takedown--version-retraction)
8. [Tier curation (manual until Phase 5)](#8-tier-curation-manual-until-phase-5)
9. [Token rotation](#9-token-rotation)
10. [Disaster recovery](#10-disaster-recovery)

---

## 1. Mental model

Originals are first-party content — written by Paktly (or under contract),
shipped under the `dev.paktly.originals.*` namespace, badged "Paktly
Original" in the catalog. The pattern in one diagram:

```
   Source content                   Service account                Public registry
   ─────────────────                ───────────────                ───────────────
   github.com/             ──→     paktly-originals       ──→     api.paktly.dev
   <author>/<repo>                 @paktly.dev                    pack id:
   (e.g. rapoyrazoglu/             (registry user)                dev.paktly.originals
        nihongo)                   owns the                       .ja-genki1
                                   id namespace
   author retains                  publishes via CI               namespace owned by
   personal repo                   on every tag                   editor account, repo
                                                                  is just a source
```

Two identities are involved on purpose:

- The **author's GitHub identity** owns the source repo and writes the
  content. They never publish to Paktly directly with their personal
  account.
- The **`paktly-originals` registry account** owns the `dev.paktly.originals.*`
  namespace and is the only entity that publishes there. The author's CI
  uses this account's JWT (stored as a GitHub Actions secret) to push
  releases.

This split keeps namespaces clean (only the editor blesses Originals
content) while letting authors keep their work in their own repos.

---

## 2. The `paktly-originals` service account

### Initial setup

Run once, by the editor on the production registry:

```bash
# 1. Generate a strong password and store it in your password manager
PASS=$(openssl rand -base64 32)

# 2. Register the service account
curl -X POST https://api.paktly.dev/v1/auth/register \
  -H 'Content-Type: application/json' \
  -d "{
    \"email\":       \"paktly-originals@paktly.dev\",
    \"password\":    \"$PASS\",
    \"displayName\": \"Paktly Originals\"
  }"
# → tokenResp { token, expiresAt, user }

# 3. Save the token — you'll need it for namespace claim and CI secret
echo "$TOKEN" > ~/.paktly/originals.jwt
chmod 600 ~/.paktly/originals.jwt
```

### Account hygiene

- The account email forwards to the editor's personal inbox. Bounce
  notifications, breach alerts, etc. land where they're seen.
- The password is in 1Password / equivalent — **not** in plain text on
  any machine. Rotate annually, after any suspected leak, and any time a
  collaborator stops being a maintainer.
- Never share the password. Share the *token* via per-recipient secret
  (e.g. GitHub Actions secret), and rotate that token weekly.

### Service account ≠ admin

The service account has no special server-side privileges. It's a regular
registry user that happens to own a particular namespace. There is no
"admin" role on the API — that surface lands with `admin.paktly.dev`
(see [issue #11](https://github.com/rapoyrazoglu/languageApp/issues/11)).

---

## 3. Namespace claim — first publish

Pack ids are owned by the **first user** to publish them. Subsequent
uploads from a different user fail with `PACK_OWNER_MISMATCH`. To claim
`dev.paktly.originals.ja-genki1`, the editor account must publish version
`1.0.0` first.

```bash
# Once the source repo's converter has produced a valid 1.0.0 zip:
TOKEN=$(jq -r .token <~/.paktly/originals.jwt)
paktly login --registry https://api.paktly.dev --token "$TOKEN"
paktly pack publish ./dist/genki1-1.0.0.zip
# → 201 Created, namespace claimed
```

After that, every `dev.paktly.originals.ja-genki1@*` upload from any
identity other than the service account is rejected. This is exactly what
we want.

> **One namespace per pack id, not per prefix**. Claiming `.ja-genki1`
> doesn't reserve `.ja-genki2`, `.ja-genki3`, etc. — each pack has its
> own ownership row. Republish from the editor account once for each new
> pack to keep the prefix consistent.

---

## 4. GitHub Actions integration

Once the namespace is claimed, the source repo's CI handles every
subsequent release. The editor never publishes manually after the first
claim.

### Storing the token as a CI secret

```bash
# As the editor, on the source repo:
gh secret set PAKTLY_ORIGINALS_TOKEN \
  --repo rapoyrazoglu/nihongo \
  --body "$(jq -r .token <~/.paktly/originals.jwt)"
```

GitHub masks the secret in logs. The author can use it via
`${{ secrets.PAKTLY_ORIGINALS_TOKEN }}` in workflows but never sees the
raw value. When the editor rotates the token (see [§9](#9-token-rotation))
they push the new value with the same `gh secret set` and the next run
picks it up.

### Workflow template

`.github/workflows/publish-pack.yml` on the source repo:

```yaml
name: Publish Paktly pack
on:
  push:
    tags: ['pack-v*']

jobs:
  publish:
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@v4

      - name: Build pack zip
        run: ./tools/build_paktly_pack/build.sh
        # produces ./dist/<pack-id>/

      - name: Install paktly CLI
        run: |
          curl -fsSL https://github.com/rapoyrazoglu/languageApp/releases/latest/download/paktly-linux-amd64 \
            -o /usr/local/bin/paktly
          chmod +x /usr/local/bin/paktly

      - name: Validate
        run: paktly pack validate ./dist/genki1

      - name: Publish
        env:
          PAKTLY_TOKEN: ${{ secrets.PAKTLY_ORIGINALS_TOKEN }}
        run: |
          paktly login --registry https://api.paktly.dev --token "$PAKTLY_TOKEN"
          paktly pack publish ./dist/genki1
```

Tag → workflow → publish. The editor's involvement is strictly the token
rotation.

> Until pre-built CLI releases ship at v1.0, replace the install step
> with `go install github.com/rapoyrazoglu/languageApp/backend/cmd/paktly@latest`
> or `git clone && go build`.

---

## 5. Webhook subscription

A webhook subscription is **separate** from the CI flow above and gives
us a second ingest path: any GitHub release (including ones created
manually in the UI) pushes a webhook the registry verifies and ingests
automatically.

This is mostly redundant for the CI-driven workflow but worth setting up
as a fallback for releases created outside CI.

```bash
WEBHOOK_SECRET=$(openssl rand -hex 16)

curl -X POST https://api.paktly.dev/v1/webhooks/subscriptions \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d "{
    \"repoOwner\": \"rapoyrazoglu\",
    \"repoName\":  \"nihongo\",
    \"secret\":    \"$WEBHOOK_SECRET\"
  }"

echo "Configure GitHub webhook with secret: $WEBHOOK_SECRET"
```

Then on the source repo: **Settings → Webhooks → Add webhook**:

- Payload URL: `https://api.paktly.dev/v1/webhooks/github`
- Content type: `application/json`
- Secret: `$WEBHOOK_SECRET` from above
- Events: only "Releases"

The registry verifies HMAC-SHA256 before ingesting. A bad secret returns
`401` and never touches storage.

List active subscriptions:

```bash
curl -H "Authorization: Bearer $TOKEN" \
  https://api.paktly.dev/v1/webhooks/subscriptions
```

Delete one:

```bash
curl -X DELETE -H "Authorization: Bearer $TOKEN" \
  https://api.paktly.dev/v1/webhooks/subscriptions/rapoyrazoglu/nihongo
```

---

## 6. Originals quality gates

For a pack to carry the "Paktly Original" badge in the catalog, the
editor verifies it meets these bars before flipping the tier (manual
process for now — automated in Phase 5).

### Hard requirements (validator-enforced or editor-checked)

| Bar | How to check |
|---|---|
| `id` matches `^dev\.paktly\.originals\..+` | Schema enforces reverse-DNS pattern; editor checks prefix manually |
| Schema version `1.2.0` or newer | `paktly pack validate` shows the schema |
| `localeCoverage[X] ≥ 0.9` for at least TR and EN | `paktly pack validate` output |
| `supportedLocales` includes TR and EN | Same |
| At least 50 vocabulary items | Editor checks lesson content |
| Native-speaker recordings for vocab pronunciation | Editor checks `audioStatus.vocabulary === "native"` (once schema 1.2.1 lands; today: manual sample listen) |
| At least one example sentence per vocab item | Editor checks |
| At least 3 different exercise families used | Editor checks |
| `aiCapabilities` declared (any value, including all-false) | `paktly pack validate` |
| MIT-compatible license (`CC-BY-4.0` / `CC-BY-SA-4.0`) | Editor checks `manifest.license` |
| `description` clearly states level + audience | Editor reads |

### Soft requirements (Phase 5 curation editor judgment)

- Cohesive thematic structure (Genki-style chapters, JLPT progression, …)
- `previousPack` / `nextPack` chain set up if part of a level path
- README in pack root with author bio + content sources
- Multi-locale: TR + EN are mandatory; DE, ZH, ES strongly preferred
  (even at `translationStatus: machine`)

### Promotion to Featured / Originals badge

Currently manual via SQL on the production database. Phase 5's
`admin.paktly.dev` ([issue #11](https://github.com/rapoyrazoglu/languageApp/issues/11))
gives us a UI for this. The intermediate path:

```sql
-- WIP — replaces with proper tier column once issue #N lands
UPDATE packs
SET tags = array_append(tags, 'paktly-original')
WHERE id = 'dev.paktly.originals.ja-genki1';
```

Don't do this on a whim. The editor's review checklist above must pass first.

---

## 7. Takedown / version retraction

There is no self-service delete. By design — clients may have already
downloaded a version, and yanking it would break their offline study.

Legitimate takedown reasons:

1. **Legal**: copyright complaint with valid claim (e.g. content not
   actually owned by the author), DMCA-equivalent notice
2. **Abuse**: pack distributing harmful content
3. **Critical bug**: pack actively misteaches and a fix can't get out fast
   enough (rare; usually a patch ships instead)

### Process

1. Document the reason in `docs/takedown-log.md` (private; not in repo if
   it includes PII)
2. Soft-disable: hide the pack from search and list endpoints
   ```sql
   UPDATE packs
   SET tags = array_append(tags, 'hidden:takedown')
   WHERE id = '<pack id>';
   ```
   (The `hidden:takedown` tag will be filtered out by API list/search
   handlers — implementation in Phase 5 admin work; until then, this is
   a flag the SQL-aware editor can act on.)
3. Notify the author via the email on `manifest.author.email`
4. If hard delete is required (court order, exfil): coordinate with the
   on-call engineer. The data lives in three places: `pack_versions` row,
   S3 object, audit log. Audit log entries are kept (compliance).

### Republishing after takedown

Same id, same `version` is still rejected (`VERSION_EXISTS`). The author
must bump the version and republish a fixed copy. The taken-down version
is not deleted, just hidden — fully restored by removing the
`hidden:takedown` tag if the issue is resolved.

---

## 8. Tier curation (manual until Phase 5)

The catalog distinguishes three quality tiers (per
[design/Discover/Paktly Language Detail.html](../design/Discover/Paktly%20Language%20Detail.html)):

| Tier | Badge | Criteria |
|---|---|---|
| **Official** | Green tick "Paktly Original" | First-party Originals — passes [§6](#6-originals-quality-gates) gates, `id` under `dev.paktly.originals.*` |
| **Reviewed** | Green-muted | Community pack that passes editor review on accuracy, audio quality, pacing |
| **Beta** | Yellow | Unreviewed community pack — visible but caveat-emptor |

Today's heuristic (per HANDOFF.md, soon ROADMAP-tracked):

- `id` starts with `dev.paktly.*` → Official
- `tags` include `reviewed` → Reviewed
- otherwise → Beta

This is fragile and manual. The proper fix is a real `tier` column on
`packs`, set by the editor (or by a Phase 5 admin UI) and never writable
by creators. Tracked in
[issue #5 (audioStatus + tier)](https://github.com/rapoyrazoglu/languageApp/issues/5)
and [issue #11 (admin.paktly.dev)](https://github.com/rapoyrazoglu/languageApp/issues/11).

---

## 9. Token rotation

Service account JWTs are valid for 7 days. To keep CI continuously
publishing, rotate weekly:

```bash
# Cron / calendar reminder, every Sunday:

# 1. Re-login from the editor's machine to mint a fresh token
PASS=$(op read 'op://Personal/paktly-originals/password')   # 1Password
TOKEN=$(curl -s -X POST https://api.paktly.dev/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d "{
    \"email\": \"paktly-originals@paktly.dev\",
    \"password\": \"$PASS\"
  }" | jq -r .token)

# 2. Push to GitHub Actions secret
gh secret set PAKTLY_ORIGINALS_TOKEN \
  --repo rapoyrazoglu/nihongo \
  --body "$TOKEN"

# 3. Optional: verify the next CI run picks it up
gh workflow run publish-pack.yml --repo rapoyrazoglu/nihongo
```

If a release happens to fire while the token is rotating, the worst case
is one failed CI run. Re-trigger with the same tag or push a new tag — no
data loss.

> Phase 5 idea: a `gh-action` shipped from this repo that rotates the
> token automatically off a schedule, so the editor doesn't have to
> remember.

---

## 10. Disaster recovery

If the service account is compromised (token leak, password leak, etc.):

1. **Rotate password immediately** — login on registry, change password,
   any outstanding tokens become invalid only after their natural 7-day
   expiry, so:
2. **Review audit logs** for every Originals pack:
   ```bash
   for pack in $(originals_pack_ids); do
     curl -H "Authorization: Bearer $NEW_TOKEN" \
       https://api.paktly.dev/v1/packs/$pack/audit
   done
   ```
   Look for any publish from an unfamiliar IP / UA between leak and
   rotation.
3. **If unauthorised publishes happened**: bump the offending pack's
   patch version with the correct content, mark the bad version with
   `hidden:takedown` tag.
4. **Push the new token** to all CI secrets (currently just
   `rapoyrazoglu/nihongo`).
5. **Post-mortem**: write up what happened in `docs/incidents/YYYY-MM-DD-token-leak.md`,
   reflect on whether the leak vector should be hardened (e.g. moving
   from long-lived JWTs to OAuth device flow with refresh tokens — Phase
   7 work).

If the production DB is wiped:

- Daily RDS snapshots are 7-day retention (per AWS_SETUP.md). Restore the
  most recent.
- S3 pack zips persist independently of DB; no data loss there.
- After restore, re-verify a few popular packs via `GET /v1/packs/{id}` —
  if anything's missing, the audit log of the restored DB tells you what
  was published since the snapshot.
- Audit log of the lost window is gone; this is acceptable for the small
  trade-off of low-cost backups.

---

## See also

- [CREATOR_API.md](CREATOR_API.md) — public-facing creator flows
- [AWS_SETUP.md](AWS_SETUP.md) — production infra runbook
- [AUTHORING.md](AUTHORING.md) — pack format reference
- [ROADMAP.md](../ROADMAP.md) — Phase 5+ plans for admin panel, status page, tier curation UI
- Live status: <https://status.paktly.dev> (planned)
