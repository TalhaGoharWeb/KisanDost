# Kisan Dost — Secrets & Credentials Sweep (2026-10-04)

**Scope:** entire repository at `~/workspace/kisan-dost` (all tracked files).
**Context:** Kisan Dost is a fully offline Flutter app with no backend, no
accounts, no Firebase, no Supabase — so the expected result is *zero*
credentials, and that is what the sweep confirms.

## Method

- `git ls-files` scanned for sensitive filenames (`keystore`, `key.properties`,
  `.env`, `google-services`, `*.pem`, `*.p12`, `*secret*`, `*credential*`,
  `*token*`): **no hits**.
- `git log --all` verified `android/key.properties` and
  `android/app/kisandost-release.keystore` were **never committed** in any
  history — no history rewrite needed.
- Grep sweeps (case-insensitive, word-boundary aware) over `.dart`, `.kt`,
  `.kts`, `.xml`, `.json`, `.properties`, `.gradle`, `.yaml`, `.md`:
  - `BEGIN PRIVATE KEY` / RSA / EC private key blocks: none.
  - `api_key` / `apikey` / `secret` / `passwd` assignments with quoted values: none.
  - `bearer <token>`, `"token": "<value>"`: none.
  - Known key prefixes (`AIza…`, `AKIA…`, `ghp_…`, `gho_…`, `xox…`,
    `sk-live-…`, JWT `eyJ…`): none.
  - Long base64-ish string literals (≥40 chars, potential embedded keys): none.
  - `test123` / `admin123` / `password123` / `letmein` / debug passwords: none.
  - `firebase` / `supabase` / `google-services`: hits only in `build/`
    intermediates (Gradle lint cache referencing `maven.google`) — build
    artifacts, not source, not credentials.

## Signing credentials (verified safe)

- `android/key.properties` and `android/app/kisandost-release.keystore` exist
  **locally only**, file mode `600`, and are gitignored via
  `android/.gitignore` (`key.properties`, `**/*.keystore`). Confirmed
  untracked: `git ls-files | grep -i "keystore\|key.properties"` returns empty.
- `android/app/build.gradle.kts` reads the signing config from
  `key.properties` only if the file exists; when absent, all properties are
  `null` — **no fallback/default passwords are embedded**, and the release
  build fails at signing time with a clear missing-config error rather than
  silently signing with a debug key.

## Classified hits

| # | Location | Classification | Action |
|---|----------|----------------|--------|
| 1 | `android/app/build.gradle.kts:38,46,48` — mentions of `keyPassword` / `storePassword` | **False positive** — property *reads* from the gitignored `key.properties`; no values in source | None |
| 2 | `lib/services/unit_converter.dart:6`, `lib/services/unit_display.dart:5`, `lib/l10n/app_locale.dart:13`, `test/unit/unit_converter_test.dart:7` — the word "hardcode" | **False positive** — comments *prohibiting* hardcoded values | None |
| 3 | `build/**` lint-cache `maven.google` references | **False positive** — Gradle build artifacts, not app source | None |

**Real secrets found: 0. Nothing removed. Nothing to rotate.**

## Residual notes

- The local `key.properties` / keystore backup reminder stands (user action,
  unchanged): keep them on encrypted USB + password manager; they were never
  in git, so there is nothing to purge from history.
- No secrets-management infrastructure is needed or was added — the app is
  offline and has no credentials to manage.
