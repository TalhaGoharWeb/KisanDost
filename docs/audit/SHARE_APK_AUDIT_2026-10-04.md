# Share APK Feature — Security Audit (2026-10-04)

**Scope:** `MainActivity.kt` (`shareApkFile()` + `"shareApk"` channel handler),
`lib/screens/dashboard_screen.dart` (`_shareApk()`), `res/xml/filepaths.xml`,
`AndroidManifest.xml` (FileProvider declaration).

## Verdict up front

No data-exposure vulnerability: the shared file was always hardcoded to the
app's own APK with no attacker-controlled input. **But the feature was
completely broken** — `FileProvider.getUriForFile()` threw on every device
because the APK lives under `/data/app`, which no configured FileProvider
root covers. Every tap ended in the Urdu error snackbar. Fixed by staging a
private cache copy and sharing that.

## Findings

### 1. [High — functionality/security] `getUriForFile()` could never resolve `packageCodePath` — FIXED

**Evidence:** `MainActivity.kt` (old code):
```kotlin
val apkFile = File(context.packageCodePath)
val uri = FileProvider.getUriForFile(context, context.packageName + ".fileprovider", apkFile)
```
`context.packageCodePath` resolves to `/data/app/~~…==/com.talhagohar.kisandost-…==/base.apk`.
`filepaths.xml` declares only `files-path` (`/data/data/<pkg>/files`),
`cache-path` (`/data/data/<pkg>/cache`) and `external-files-path`
(`/storage/emulated/0/Android/data/<pkg>/files`). androidx `FileProvider`
matches the file's canonical path against these roots and throws
`IllegalArgumentException: Failed to find configured root that contains …`
when none matches — which is the case here on every Android version and
every APK install layout (`/data/app/<pkg>-*/base.apk` and the `~~` split
layout alike).

**Impact:** fail-closed (the exception → `result.error("SHARE_FAILED")` →
Dart shows «ایپ شیئرنگ میں خرابی پیش آئی»), so no leak — but the feature
never worked.

**Fix applied** (`MainActivity.kt::shareApkFile`): copy `packageCodePath`
to a fixed-name file in the app-private cache dir
(`kisandost-share.apk`; `cache-path` is already a configured root), set
owner-only permissions, then `getUriForFile()` + share. Partial copies are
deleted on failure and rethrown as `SHARE_FAILED`. The staged file is
overwritten on each share, so at most one copy ever exists in private
cache; it is deliberately not deleted right after `startActivity` because
the receiving app reads it asynchronously after the chooser returns.

### 2. [OK] Only the intended APK can be shared

- Dart calls `invokeMethod('shareApk')` with **no arguments**; the native
  handler reads no `call.arguments` for this method.
- Both the source (`context.packageCodePath`) and the staged destination
  (`cacheDir/kisandost-share.apk`) are hardcoded. No user input, intent
  extra, or route parameter can redirect the share to another file.
- Path traversal is impossible: there is no path string to traverse.

### 3. [OK] URI permissions are temporary and scoped

- `FLAG_GRANT_READ_URI_PERMISSION` is set on the `ACTION_SEND` intent only,
  launched via `Intent.createChooser`. The grant goes solely to the
  user-chosen target component and dies with the receiving activity.
- No `grantUriPermission()` permanent grants anywhere; FileProvider is
  `android:exported="false"`.

### 4. [OK] Intent construction

`ACTION_SEND` + `EXTRA_STREAM` (content URI) + MIME
`application/vnd.android.package-archive` + chooser. This is the standard
secure pattern; the grant covers the stream URI.

### 5. [OK] No private-data exposure through this flow

The only file ever minted into a content URI here is the staged APK copy.
`kisan_dost.db` (`/data/data/<pkg>/databases/`), backups, and exported
CSV/PDFs are unreachable: no code path in this flow accepts a file
argument. The broad `filepaths.xml` roots (`files-path "."` etc.) are
currently unused by any working feature — `FileProvider` only serves URIs
the app explicitly mints, so the broad paths alone grant nothing.

### 6. [OK] Dart side

`dashboard_screen.dart::_shareApk()` passes no path/parameter; shows a
«preparing…» snackbar and a friendly Urdu error on `PlatformException`
without leaking exception internals beyond `e.message` (acceptable).

## Deliberately not changed

- **`filepaths.xml` left as-is.** The broad roots are dormant (nothing
  working mints URIs from them today). Narrowing is defense-in-depth but
  risks breaking future legitimate sharing; the actual exposure (one
  hardcoded APK) is already minimal.
- **No `<root-path>` added.** It would serve `/data/app` directly without
  a copy, but it widens the FileProvider's servable surface for no
  functional gain over the cache-staging approach.
- **Copy runs on the calling (UI) thread**, matching the original code's
  structure. A ~73 MB copy typically takes well under a second; moving it
  to a background thread would be a UX nicety, not a security fix.

## Verification

- Kotlin brace/paren balance checked; change mirrors verified patterns
  (`use {}`, `copyTo`, `setReadable(true, true)`).
- No Dart files touched → no `flutter analyze` run required.
- Full `flutter test` intentionally not run (parallel agents active).
- Real-device check still needed: tap «ایپ شیئر کریں» → chooser appears →
  received APK installs/opens correctly.

## Residual risks

- Staged copy (~73 MB) persists in private cache until the next share or
  OS cache eviction. App-private and owner-only; contains no user data
  (it's the app binary itself).
- On devices where the app was installed from an App Bundle with splits,
  `packageCodePath` (base APK) alone may not install standalone. The
  distributed release is a monolithic APK, so this does not apply today.
- `e.message` in the Dart error snackbar could surface a raw exception
  string; acceptable, non-sensitive.
