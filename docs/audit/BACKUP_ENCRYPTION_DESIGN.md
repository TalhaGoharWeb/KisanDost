# Backup Encryption Design — Owner Decision #6

**Date:** 2026-10-18 · **Branch:** `prod-readiness` · **Status:** implemented

Owner decision: encrypted backups with a recovery method the farmer can
actually use. Unencrypted backup REMAINS available as an explicit choice
(plain `.db` copy + JSON sidecar, as before).

---

## 1. Recovery model (the part the farmer must actually use)

- At backup time the farmer chooses **خفیہ بیک اپ** (encrypted) or
  **سادہ بیک اپ** (unencrypted). The choice is explicit in the UI; there
  is no silent default.
- For an encrypted backup the farmer sets a **passphrase** (any length ≥ 4
  characters, Urdu or any script) and may type an optional **hint**
  (e.g. "میرے بیٹے کا نام").
- The hint is stored **in plaintext** in the backup sidecar. It is only a
  hint — it must never BE the passphrase and the UI warns about this.
- **No cloud escrow, no admin backdoor, no recovery email.** The
  passphrase never leaves the phone. It is never stored anywhere (not in
  SharedPreferences, not in the sidecar, nowhere).
- **Loud consequence, stated in the UI in Urdu:** اگر پاس فریز بھول
  گئے تو بیک اپ ہمیشہ کے لیے ضائع ہو جائے گا — اسے کوئی بھی بحال نہیں
  کر سکے گا۔ (A forgotten passphrase = permanently unrecoverable.)

This is the standard passphrase-recovery trade-off: the alternative
(any escrow) would defeat the whole purpose of encryption for a farmer
whose threat model includes a shared/lost phone.

## 2. Threat model

Protects against:

- **Backups at rest on a shared family phone** — a sibling/relative
  browsing files cannot read the farm's financial records.
- **Backups sent via share (WhatsApp/Bluetooth/USB)** — anyone who
  intercepts the shared file gets ciphertext only.
- **A lost/stolen phone** — the backup files are unreadable without the
  passphrase (assuming the phone itself is locked, which is outside our
  control).

Does NOT protect against:

- Someone who knows the passphrase (by design).
- Malware/keyloggers on the phone at restore time (outside app scope).
- A weak passphrase (short, guessable). The UI nudges toward a memorable
  phrase; brute-forcing a 4-char passphrase is trivial, and we say so in
  the code comments — the passphrase's real strength comes from the
  farmer's memory, not the KDF.

## 3. Cryptographic design (all primitives vetted — NEVER hand-rolled)

Package: **`encrypt: ^5.0.3`** (high-level API over PointyCastle).
`package:crypto` (already a dependency) supplies PBKDF2-HMAC-SHA256 and
HMAC-SHA256. No custom ciphers, no custom KDF, no custom MAC.

### 3.1 Key derivation

```
salt            = 16 random bytes (per backup, CSPRNG via Random.secure())
kdf             = PBKDF2-HMAC-SHA256(passphrase_utf8, salt, 210_000 iterations)
derived         = 64 bytes
  encKey        = derived[0..32)    → AES-256 key
  macKey        = derived[32..64)   → HMAC-SHA256 key
```

210,000 iterations follows the OWASP 2023 guidance for PBKDF2-HMAC-SHA256
(slow enough to hurt bulk guessing, fast enough on low-end phones:
~1 s on a 2020-class device — acceptable at backup/restore time only).

### 3.2 Authenticated encryption

- **Cipher:** AES-256-GCM (12-byte random nonce per backup). GCM is
  authenticated encryption: any modification of the ciphertext is
  detected by the tag check.
- **Belt and braces:** an additional HMAC-SHA256 (Encrypt-then-MAC) over
  `salt ‖ nonce ‖ ciphertext`, keyed with `macKey`, is appended to the
  file. This gives a cheap integrity check before touching the GCM
  decryptor and a second independent authentication layer.

### 3.3 Wrong-password vs tampered-file — the verifier

GCM/HMAC alone cannot distinguish "wrong passphrase" from "tampered
file" (both fail authentication). We separate them with a stored
**verifier**, a deliberate and documented trade-off:

```
verifier = HMAC-SHA256(macKey, "kisan-dost-backup-verifier" ‖ salt)
```

- 32 bytes, stored in the file header in plaintext.
- On open: derive keys → check verifier first.
  - Verifier mismatch → **wrong passphrase**
    (اردو: "پاس فریز غلط ہے — دوبارہ کوشش کریں")
  - Verifier OK but ciphertext HMAC fails → **tampered/corrupt file**
    (اردو: "بیک اپ فائل میں تبدیلی پائی گئی ہے — یہ محفوظ نہیں ہے")
  - Both OK → GCM decrypt; a tag failure here is treated as tampering.

**Trade-off acknowledged:** the verifier lets an attacker confirm a
guessed passphrase offline slightly faster (one HMAC instead of one
PBKDF2+GCM). This does not reduce practical security: the attacker
already has the ciphertext and can already test guesses offline via the
GCM tag. The UX gain (a farmer who mistypes sees "wrong passphrase",
not "your file is corrupt") is worth it.

### 3.4 File format (`.db.enc`)

```
offset  size   field
0       8      magic "KDSTENC1" (0x4B445354454E4331)
8       16     salt
24      12     GCM nonce
36      32     verifier (HMAC-SHA256(macKey, "kisan-dost-backup-verifier"‖salt))
68      N      AES-256-GCM ciphertext of the .db bytes
68+N    32     HMAC-SHA256(macKey, salt‖nonce‖ciphertext)
```

Total overhead: 100 bytes. All crypto parameters live in the file
header, so the `.db.enc` file is self-contained — sharing one file is
enough to restore elsewhere. The JSON sidecar (`.db.enc.json`) carries
only non-secret metadata:

```json
{
  "appVersion": "1.0.6",
  "schemaVersion": 13,
  "createdAt": "2026-10-18T…",
  "sha256": "<sha256 of the .db.enc bytes>",
  "label": "…",
  "encrypted": true,
  "hint": "میرے بیٹے کا نام",     // plaintext hint, optional
  "kdf": "pbkdf2-hmac-sha256",
  "kdfIterations": 210000
}
```

Encrypted backups are named `kisandost_backup_<stamp>_v<ver>.db.enc`
(+ numeric suffix on same-second collisions).

## 4. Service behavior (`BackupService` / `RestoreService`)

- `createBackup({label, passphrase, hint})`:
  - No passphrase → old plaintext path, unchanged.
  - With passphrase → checkpoint + close live DB, copy to temp, encrypt
    temp → `<name>.db.enc.tmp`, **atomic rename** to final name, write
    sidecar, return `BackupInfo` with `isEncrypted: true`.
  - Interrupted export → the `.tmp` file never becomes a listed backup
    (`listBackups` only matches `*.db` / `*.db.enc`); a `finally` removes
    a leftover temp file. **No partial file is ever listed.**
- `verifyBackup(path, {passphrase})`:
  - Plain `.db` → unchanged structural checks (magic, integrity_check,
    required tables, user_version, sidecar sha256).
  - `.db.enc` without passphrase → throws `BackupException`
    ("یہ خفیہ بیک اپ ہے — بحال کرنے کے لیے پاس فریز درکار ہے")
    instead of the old cryptic "یہ درست ڈیٹا بیس فائل نہیں ہے".
  - `.db.enc` with passphrase → wrong-password vs tampered errors per
    §3.3, then decrypt to a temp file and run the same structural
    checks on the decrypted bytes (plus sidecar sha256 of the `.enc`
    bytes when a sidecar exists). Temp file is deleted in `finally`.
- `restoreReplace(path, {passphrase})` / `restoreMerge(path, {passphrase})`:
  - Encrypted input → passphrase required, decrypt to temp, restore
    from temp, delete temp in `finally`. The pre-restore safety backup
    is encrypted with the **same passphrase** (a plaintext safety copy
    of an encrypted backup would defeat the point).
- `importBackupFile(pickedPath, {passphrase})`: accepts `.db` and
  `.db.enc`; encrypted picks require the passphrase up front and are
  verified after import; failed imports clean up their partial copy
  (unchanged behavior).
- `listBackups()`: lists both `.db` and `.db.enc`; `BackupInfo` gains
  `isEncrypted` and `hint` (from sidecar; orphan `.db.enc` files list as
  encrypted with an empty hint).
- `decryptBackupToTemp(path, passphrase)` is public so the UI (or a
  future export flow) can obtain decrypted bytes without duplicating
  crypto code. It never returns keys — only a temp file path.

## 5. UI (`BackupScreen`)

- "نیا بیک اپ بنائیں" opens a dialog: explicit choice
  **خفیہ بیک اپ (پاس فریز کے ساتھ)** vs **سادہ بیک اپ (بغیر پاس فریز)**;
  passphrase + confirm fields (obscured, ≥ 4 chars, must match), optional
  hint field; loud warning that a forgotten passphrase is unrecoverable.
- Backup cards show a 🔒 "خفیہ" badge and the hint (if any) for
  encrypted backups.
- Restore of an encrypted backup prompts for the passphrase first; the
  passphrase is kept in memory only for the duration of the restore.
- Sharing an encrypted backup shares the `.db.enc` file (self-contained);
  the hint is NOT shared automatically — it stays in the local sidecar.

## 6. What stays plaintext (documented, accepted)

- The filename, file size, sidecar metadata (label, timestamps, hint),
  and the header (magic/salt/nonce/verifier) are plaintext. Only the
  database bytes are secret.
- Automatic daily backups (`maybeAutoBackup`) remain **unencrypted** —
  they run unattended with no farmer present to type a passphrase.
  Farmers who need encryption make manual encrypted backups.
- Unencrypted manual backup remains an explicit, honest choice in the UI.

## 7. Future considerations (NOT in scope)

- Changing a backup's passphrase (would need re-encryption — easy to add
  later via `decryptBackupToTemp` + re-encrypt).
- Biometric-gated passphrase storage in the Android keystore — rejected
  for now: it silently reintroduces the "shared phone" weakness (anyone
  whose biometrics unlock the phone reads the backups).
