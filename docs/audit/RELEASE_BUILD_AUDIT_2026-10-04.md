# Kisan Dost — Production / Release Build Audit (2026-10-04)

Auditor: senior release engineer (assisted). Static audit only — no APK was
built (the parent cuts the release build after all audit fixes land).

## Headline finding

**The shipped 1.0.0+1 release APK contains no alarm sound.** `shrinkResources`
removed `res/raw/farming_alarm.mp3` because it is referenced only via string
URIs (`android.resource://…/raw/farming_alarm`) that the resource shrinker
cannot trace. Verified: zero `.mp3/.ogg/.wav` entries in
`~/workspace/your_files/kisan-dost-release.apk`. Alarms in 1.0.0+1 fire
silently (or with the channel fallback at best). **Fixed** with
`res/raw/keep.xml` (`tools:keep="@raw/farming_alarm"`). The next release build
must be binary-verified (`unzip -l` shows the mp3) before shipping.

## Per-item verdicts

| # | Item | Verdict | Evidence |
|---|------|---------|----------|
| 1 | Debuggable | **PASS** | No `android:debuggable` anywhere in `android/`; release block in `build.gradle.kts` does not set `isDebuggable` (defaults `false`). |
| 2 | Debug menus/screens | **PASS** | Zero `kDebugMode`-gated UI; `debugShowCheckedModeBanner: false` explicitly in `main.dart:79`; prior auth audit confirmed no hidden screens/routes. |
| 3 | Verbose logging | **PASS + fix** | All Dart logging is `debugPrint`, which is a **release no-op** in Flutter — nothing to strip. Kotlin `Log.d/v` *do* emit in release logcat (benign: task IDs only, no PII) — **fixed**: added `-assumenosideeffects` for `Log.d`/`Log.v` to `proguard-rules.pro`; `Log.i/w/e` kept for diagnostics. |
| 4 | Test data | **PASS** | Demo mode is opt-in (`prefs.getBool('demo_active') ?? false`); no test fixtures in `assets/`; pubspec bundles only `assets/images/` (+ fonts). `assets/i18n/*.json` is a stale legacy draft, unread by the app and **not bundled** (only `assets/images/` is declared). |
| 5 | Dev URLs / credentials | **PASS** | No URLs, API keys, or secrets in `android/` or `lib/` (only XML namespace URIs and doc comments). Prior secrets sweep: zero real secrets repo-wide; signing files gitignored and never committed. |
| 6 | Release signing | **PASS** | `build.gradle.kts` reads `keyAlias/keyPassword/storeFile/storePassword` from gitignored `android/key.properties` with **no hardcoded fallbacks**; when the file is absent the properties are null and the build fails at signing time rather than silently debug-signing (verified by prior sweep). |
| 7 | Manifest production-safe | **PASS** | `allowBackup="false"`, `usesCleartextTraffic="false"` + `network_security_config`; no `INTERNET` in release (debug/profile only); exported flags correct (only `MainActivity` launcher + `BootReceiver`); `versionCode/versionName` from pubspec. |
| 8 | ProGuard / R8 | **FLAG → FIXED** | `isMinifyEnabled` + `isShrinkResources` on; keep rules correct and not dangerously broad (own package only). Two fixes: (a) **missing `keep.xml` for the alarm sound** (headline finding above); (b) log stripping (item 3). |
| 9 | Versioning | **FLAG (recommendation)** | pubspec `1.0.0+1` → `versionCode=1`, `versionName=1.0.0`, consistent. **Do not ship the next build as `+1`**: recommend **`1.0.1+2`** (versionCode 1→2; patch bump reflects hardening fixes, no feature change). Version bump deliberately not applied — parent decides at build time. |
| 10 | App name | **FLAG (decision needed)** | `android:label="Kisan Dost"` (manifest), package `com.talhagohar.kisandost`, Urdu `کسان دوست` — the spelling **"Kisan Dost"** (one 'a') is used consistently everywhere in the app. The user's request wrote **"Kisaan Dost"** (two a's). Zero `Kisaan` hits in the repo. **Nothing renamed** — the user must declare the canonical spelling; if "Kisaan Dost" is desired it touches `android:label`, store listing, and UI strings. |

## Fixes applied

1. `android/app/src/main/res/raw/keep.xml` (new) — `tools:keep="@raw/farming_alarm"`.
2. `android/app/proguard-rules.pro` — strip `Log.d`/`Log.v` in release.

Both are Android-only; no Dart touched, no `flutter analyze` required. XML
validity of both files verified by parse.

## Remaining release checklist (for the parent at build time)

1. Bump pubspec to `1.0.1+2` (or the user's chosen version).
2. Build release APK from the pinned green commit; binary-verify:
   `unzip -l` shows `res/*.mp3` (alarm sound present), `classes.dex`,
   `AndroidManifest.xml` with `debuggable=false` (check via `aapt dump badging`).
3. Confirm APK installs and the alarm **plays sound** on a real device
   (the 1.0.0+1 build's silent-alarm defect must be regression-tested).
4. Resolve the "Kisan" vs "Kisaan" spelling with the user before the store
   listing is (re)written.
5. Keystore + `key.properties` backup still owed (encrypted USB + password
   manager) — unchanged standing item.
