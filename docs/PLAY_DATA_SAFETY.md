# Play Console — Data safety worksheet for Kisan Dost

Copy these answers into Play Console → App content → Data safety.
They are based on the **actual** `android/app/src/main/AndroidManifest.xml`
and the app's real behaviour (fully offline, no accounts, no analytics SDK).

## Does your app collect or share any user data?

**Data collection: No.** Kisan Dost works 100% offline. There is no login,
no analytics, no crash reporting, no advertising SDK, and no network code —
the app never transmits anything anywhere.

**Data sharing: only what the farmer explicitly shares.** The app offers
Backup, CSV export, and PDF reports through Android's system **share sheet**
(`share_plus`). Nothing leaves the device unless the farmer taps Share and
chooses a destination themselves. (In Play's taxonomy this is
"user-initiated sharing" and does not count as data sharing by the app,
but declare it here for honesty.)

- Data encrypted in transit: **N/A** — the app sends no data over any network.
- Data deletion: the farmer's data lives in a local SQLite file on their own
  device; uninstalling the app deletes it. The in-app "delete everything"
  option wipes the database.

## Permissions and why the app needs them

| Permission | Why (for the Play declaration) |
|---|---|
| `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM` | Core feature: farming task reminders (e.g. "پانی لگائیں") must fire at the exact time the farmer set. Inexact alarms would make reminders useless. |
| `POST_NOTIFICATIONS` | Shows the task reminder notifications. |
| `USE_FULL_SCREEN_INTENT` | Task alarms open a full-screen alarm screen with the alarm sound, like an alarm clock. (Android 14+: this needs the Play declaration + justification; a short demo video of the alarm firing helps approval.) |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | Farming alarms must fire even in Doze mode; without this, the OS may delay a 6 AM irrigation reminder until the phone is next used. (Play requires justification — explain the alarm use case.) |
| `RECEIVE_BOOT_COMPLETED` | Re-schedules the farmer's pending task alarms after the phone restarts, so no reminder is lost. |
| `VIBRATE` | Alarm vibration alongside the alarm sound. |
| `WAKE_LOCK` | Keeps the CPU awake briefly while the alarm service starts the reminder. |
| `FOREGROUND_SERVICE` / `FOREGROUND_SERVICE_MEDIA_PLAYBACK` | The alarm runs as a foreground service while playing the alarm sound (`farming_alarm.mp3`). |

No location, contacts, camera, microphone, or storage permissions are used.
File sharing goes through `FileProvider` (no broad storage access).

## Sensitive permissions — action items before submission

1. `USE_FULL_SCREEN_INTENT` and `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` are
   **restricted/special** permissions. Play may reject the listing without a
   written justification and, for full-screen intent, a demo video. Prepare
   both: a screen recording of setting a task reminder and the full-screen
   alarm firing, plus one paragraph explaining why exact farming alarms are
   the app's core function.
2. Target SDK / `targetSdkVersion` follows the Flutter stable default — keep
   it current before each release; Play blocks outdated targets.
3. App id: `com.talhagohar.kisandost` · version `1.0.0 (1)`.
