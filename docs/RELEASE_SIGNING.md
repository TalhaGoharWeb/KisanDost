# Release signing — Kisan Dost

## What exists

| Item | Location | Committed? |
|---|---|---|
| Release keystore (RSA 4096, valid 30 years, alias `kisandost`) | `android/app/kisandost-release.keystore` | **NO — gitignored** |
| Passwords (`storePassword`, `keyPassword`, `keyAlias`, `storeFile`) | `android/key.properties` | **NO — gitignored** |
| Release signing wiring | `android/app/build.gradle.kts` (`signingConfigs.release`) | yes |
| R8 config (`minifyEnabled`, `shrinkResources`) | `android/app/build.gradle.kts` + `proguard-rules.pro` | yes |

`flutter build apk --release` / `flutter build appbundle --release` signs with
the release key. If `android/key.properties` is missing the build **fails loudly**
instead of silently falling back to debug keys — that is deliberate.

## ⚠️ BACK UP THE KEYSTORE — READ THIS

**If you lose `android/app/kisandost-release.keystore` (or forget the passwords
in `android/key.properties`), you can NEVER update the Play Store listing
again.** Google Play requires every update to be signed with the *same* key.
There is no recovery, no reset, no appeal — the only option is publishing a
brand-new app listing and asking every farmer to reinstall.

Do this now, before the first upload:

1. Copy `android/app/kisandost-release.keystore` to **two** safe places
   (e.g. an encrypted USB drive + a password manager's file storage).
2. Store the `storePassword` / `keyPassword` from `android/key.properties`
   in the same password manager (do NOT email them, do NOT paste them in chat).
3. Optional but recommended: enrol in **Play App Signing** when creating the
   Play listing — Google then holds the *upload* key's public counterpart and
   can re-issue your upload key if it is lost. (The keystore above remains the
   key of last resort; keep the backups regardless.)

## CI / release machines

Any machine that builds the release must provide `android/key.properties`
(plus the keystore file it points to). In GitHub Actions, store the keystore
bytes and the three secrets (`KEYSTORE_BASE64`, `STORE_PASSWORD`,
`KEY_PASSWORD`) as repository secrets and reconstruct the files in the
workflow before `flutter build appbundle`. The CI workflow added in Phase 12
does not build releases yet — add that job when the first Play upload is
planned.

## Fingerprints (to match at Play Console enrolment)

Run this to show them (needs the keystore + password):

```sh
keytool -list -v -keystore android/app/kisandost-release.keystore -alias kisandost
```

Compare the SHA-256 shown here with what the Play Console expects for the
upload key. If they don't match, stop — you are signing with the wrong key.
