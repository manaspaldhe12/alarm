# Morning Alarm

[![Build installable IPA](https://github.com/manaspaldhe12/alarm/actions/workflows/build-ipa.yml/badge.svg)](https://github.com/manaspaldhe12/alarm/actions/workflows/build-ipa.yml)

### 📲 [Download the latest build (MorningAlarm.ipa)](https://github.com/manaspaldhe12/alarm/releases/download/latest/MorningAlarm.ipa)

Rebuilt automatically on every push to `main` — always the newest code. Unsigned; install with Sideloadly or AltStore (no Xcode needed) — see [Install on your iPhone](#install-on-your-iphone) below.

An offline-first iOS alarm app focused on helping you get out of bed, not just defeat an alarm. Covers description.md's full MVP scope: recurring alarms, gentle wake-up, step/QR/chess missions for snooze/turn-off/wake-up-check, motivational quotes, and an optional post-alarm app trigger.

## Requirements

- **iPhone** running **iOS 26** or later.
- **Apple Developer account** — a free Apple ID is enough, for either install path below. AlarmKit needs no paid Developer Program membership, no special entitlement, and no Apple approval (see "AlarmKit setup" below) — the $99/yr program only matters if you later want App Store/TestFlight distribution or a feature that's genuinely gated (this app doesn't use any).
- To install: either **a Mac with Xcode 26+** (Option B/C below), or **any computer** (Mac or Windows, no Xcode needed) to run a sideloading tool once (Option A below) — see "Install on your iPhone".

> **Note on this codebase:** this was originally written without access to Xcode 26/the iOS 26 SDK, so the iOS-framework-dependent code (AlarmKit, CoreMotion, AVFoundation, UIKit, SwiftUI-on-iOS, the `Observation` macro) wasn't compiler-verified at the time. That's since changed: [`.github/workflows/build-ipa.yml`](.github/workflows/build-ipa.yml) now compiles and runs the full test suite against a real Xcode 26/iOS 26 SDK on every push to `main` — check the [Actions tab](https://github.com/manaspaldhe12/alarm/actions) or the badge below for current status. Before that CI existed, the non-Apple-SDK-dependent portions were validated the hard way: the entire domain/business-logic layer (recurrence math, the chess board/move/engine, step anti-cheat, mission configuration, file-backed repositories) and the full `AlarmCoordinator`/`WakeUpCoordinator`/`MissionCoordinator` state machine were compiled and *executed* for real against a stripped (Observation-free) copy on a local Swift 5.7 toolchain, catching and fixing several real bugs — see `MorningAlarmTests/` for the same tests ported to real XCTest.

## Project location

Open the Xcode project:

```text
MorningAlarm/MorningAlarm.xcodeproj
```

## One-time setup in Xcode

1. Open `MorningAlarm.xcodeproj` in Xcode.
2. Select the **MorningAlarm** project in the navigator, then the **MorningAlarm** target.
3. Open **Signing & Capabilities**.
4. Set **Team** to your Apple ID (a free personal team is fine — see "AlarmKit setup" below).
5. Change **Bundle Identifier** if needed (default: `com.morningalarm.app`).
6. Repeat for the **MorningAlarmWidgets** target (`com.morningalarm.app.widgets`).

### AlarmKit setup

AlarmKit needs **no Xcode capability, no entitlement, and no Apple approval** — it's a runtime-permission framework like Camera or Location, not a managed/restricted one. All it needs:

1. `NSAlarmKitUsageDescription` in `Info.plist` (already present in this project).
2. A call to `AlarmManager.shared.requestAuthorization()` at runtime, which shows a normal system permission prompt (already wired up in `AlarmKitScheduler`).

Don't add an "AlarmKit" capability under Signing & Capabilities or a `com.apple.developer.alarmkit` entitlement — that key isn't real. It was mistakenly added to this project early on (a known pattern of LLM-fabricated entitlements — see [this Apple Developer Forums thread](https://developer.apple.com/forums/thread/797950), where an Apple engineer flagged the exact same fake entitlement causing exactly this kind of confusion), and per that thread, an unrecognized entitlement key like that can make Xcode reject your provisioning profile on a real device. `MorningAlarm.entitlements` is now intentionally empty.

If you hit an actual AlarmKit-related build/signing error, treat it as a real bug to investigate on its own terms rather than reaching for an entitlement — nothing in this app should need one.

## Install on your iPhone

### Option A: Without Xcode — sideload the CI-built .ipa (free)

Every push to `main` runs [`.github/workflows/build-ipa.yml`](.github/workflows/build-ipa.yml): a GitHub Actions macOS runner with a real Xcode 26 install builds the app, runs the full `MorningAlarmTests` suite, and publishes an **unsigned** `.ipa` to a rolling `latest` release:

```text
https://github.com/manaspaldhe12/alarm/releases/download/latest/MorningAlarm.ipa
```

("Unsigned" here just means CI doesn't hold any Apple credentials — no certificate, provisioning profile, or Apple ID ever touches GitHub Actions. The sideloading tools below strip whatever signature is present and re-sign with your own identity regardless, so a CI-side signature would be pointless complexity.)

You still need **some** computer (Mac or Windows, old or new — it does not need to run Xcode) to do the one-time pairing these tools require; after that, installs/updates can happen straight from your iPhone.

**Using Sideloadly** (simpler, manual refresh every 7 days):

1. Install [Sideloadly](https://sideloadly.io/) on any Mac or Windows computer.
2. Download `MorningAlarm.ipa` from the link above.
3. Connect your iPhone by USB, unlock it, and trust the computer if prompted.
4. Open Sideloadly, drag `MorningAlarm.ipa` into it, select your device, enter your (free) Apple ID and password when prompted.
5. Click **Start**. Sideloadly signs the app with a certificate generated from your Apple ID and installs it.
6. On your iPhone: **Settings → General → VPN & Device Management**, tap your Apple ID under "Developer App", tap **Trust**.
7. A **free** Apple ID's signature expires after **7 days** — after that the app won't open until you repeat steps 2–6 with a fresh `.ipa` from the same URL (it's always the latest build).

**Using AltStore** (a bit more setup, then refreshes itself over Wi-Fi):

1. Install [AltServer](https://altstore.io/) on a companion Mac or Windows computer and AltStore on your iPhone through it (AltStore's site walks through both — this is a one-time pairing step).
2. Sign in with your free Apple ID when AltServer prompts for it.
3. In AltStore on your iPhone, use **My Apps → +** and pick a downloaded `MorningAlarm.ipa`, or add a custom source pointing at the releases feed if you want in-app updates.
4. Same 7-day free-tier limit applies, but AltServer/AltStore will try to auto-refresh the app in the background over Wi-Fi as long as AltServer is reachable (i.e. your companion computer is on and on the same network periodically) — less manual upkeep than Sideloadly once it's set up.

Either way, sideloaded apps are capped at **3 apps signed under a free Apple ID at once** — remove old test builds if you hit that limit.

### Option B: Direct USB install via Xcode (needs a Mac that can run Xcode 26)

1. Connect your iPhone to your Mac with a USB cable.
2. Unlock the phone and tap **Trust** if prompted.
3. In Xcode, select your iPhone from the device menu in the toolbar (not a Simulator).
4. Press **Run** (⌘R) or click the Play button.
5. On first launch, iOS may show **Untrusted Developer**:
   - Open **Settings → General → VPN & Device Management**
   - Tap your developer profile and choose **Trust**
6. Launch **Morning Alarm** again from the home screen.

### Option C: Wireless debugging (also needs Xcode)

1. Connect via USB once and enable **Connect via network** in Xcode’s **Devices and Simulators** window.
2. Select your phone wirelessly from the device menu and press **Run**.

## First launch

1. When prompted, allow **Alarms** permission for Morning Alarm.
2. Tap **+** to create an alarm and set a time.
3. Toggle the alarm **ON**.
4. Close the app — the alarm is scheduled with AlarmKit and should fire at the set time, even when locked and offline.

## Testing an alarm quickly

1. Create an alarm for **1–2 minutes** from now.
2. Lock your phone or switch to another app.
3. When the alarm fires, use the system alarm UI or open the app for the in-app **Snooze** / **Turn Off** screen.

## Unit tests

There's a `MorningAlarmTests` target (⌘U in Xcode, or `xcodebuild test`) covering:

- **Domain logic** — `Recurrence`/`Weekday`/`LocalTime` next-fire-date math (including weekday-skipping and week-wraparound), the chess board/move parser and `LocalChessEngine` (FEN parsing, capture/castling/en-passant/promotion, solution-sequence validation), `StepValidationEngine`'s anti-cheat gates (cadence rejection, minimum elapsed time), `MissionConfiguration` Codable round-trips and summaries, `QRCodeRegistration` hashing, and that the bundled `puzzles.json` puzzles all have parseable solution moves.
- **Persistence** — real file I/O round-trips for `FileAlarmRepository`, `FileQRCodeRepository`, and `WakeUpCheckStateStore`, including "survives a fresh instance" (i.e. app relaunch) checks.
- **Coordinators** — the full `AlarmCoordinator` state machine (ringing → mission → snoozed/morning-complete, max-snooze enforcement, recurring-vs-one-time turn-off behavior, gentle-wake→ringing transitions, wake-up-check scheduling, mission cancellation) and `WakeUpCoordinator`/`MissionCoordinator`/`QuoteCoordinator`, all driven through hand-written fakes (`MorningAlarmTests/Fakes.swift`) of `AlarmScheduler`/`AlarmAudioPlayer`/`AlarmRepository`/`StepCounter`/`QRCodeRepository`/`PuzzleRepository`/`QuoteRepository`/`ExternalAppLauncher` — no AlarmKit, CoreMotion, AVFoundation, or network access needed to run them.

These tests were developed against a stripped, Observation-free copy of the coordinators on this machine's local Swift toolchain (no Xcode available here) and actually compiled and ran — 76/76 passing — before being ported to the real XCTest target above; porting is mechanical (enum→XCTestCase, custom asserts→XCTAssert*) but hasn't itself been re-run through Xcode 26, so treat first-run hiccups there as porting nits, not logic bugs.

## Current features

- Create, edit, enable/disable, delete, and **repeat** alarms (weekdays / weekends / every day / custom days)
- Default bundled alarm sound (`default_alarm.wav`)
- Alarm fires via **AlarmKit** (works offline, when locked, without the app open)
- **Gentle wake-up**: a configurable pre-alarm volume ramp via AlarmKit's pre-alert countdown (best-effort in the background; guaranteed once the app is foregrounded)
- **Missions** for snooze, turn-off, and wake-up check, independently configurable per alarm:
  - **Steps** — CoreMotion/`CMPedometer`-backed, with anti-cheat (minimum elapsed time + max plausible step rate to reject shaking)
  - **QR code** — register a code anywhere in your home, scan it on-device (AVFoundation) to complete
  - **Chess puzzle** — bundled, fully offline puzzle set (`Resources/Puzzles/puzzles.json`), rating-range selectable, validated locally
- **Wake-up check** — a second, independently-scheduled check after a configurable delay, survives app relaunch
- **Motivational quotes** — bundled, categorized, shown after snooze / turn-off / wake-up check, no immediate repeats
- **Post-alarm app trigger** — optional "Open Calendar/Weather/etc." after turning off, never required to dismiss
- Local JSON persistence (alarms, QR registrations, and pending wake-up checks all survive app restart)
- Widget extension for AlarmKit snooze countdown UI

## Expected behavior

What should actually happen on-device, so you can tell a bug from something by design while testing.

**When an alarm fires**
- AlarmKit alerts at full system volume with the bundled sound (`default_alarm.wav`), even locked and offline.
- Tapping either alert button (Snooze/Stop) opens the app straight into the matching mission — it does not silently stop the alarm the way a stock AlarmKit alert would, because both buttons are wired to open the app (`.custom` behavior + `stopIntent`/`secondaryIntent`) rather than letting AlarmKit handle them natively.
- The alarm keeps ringing for the entire mission — it does not go silent just because you tapped a button or started the mission. It only stops once you actually finish (or fail out of) the mission.
- **Volume can't be used to cheat**: turning the phone's volume down while an alarm is ringing or a mission is in progress gets forced back to max within moments (`VolumeForcer`). This is intentional — it's off during gentle wake-up's pre-alarm ramp (a deliberate soft build-up) and once you're actually done (snoozed confirmation shown / morning complete / idle).
- **Force-quitting mid-mission doesn't get you out of it, but it does briefly go silent.** The mission's in-app sound is ordinary app-process audio, so it can't survive the process being killed outright by a force-quit — that part is unavoidable for any app. But apps like Alarmy have always worked around exactly this by handing the actual alerting off to the OS (local notifications with sound, delivered whether or not the app's process is alive) instead of relying on the app process to keep making noise — and per [Apple's own AlarmKit FAQ](https://developer.apple.com/forums/thread/797158), "all alarms are expected to persist regardless of app or device state changes, once they are successfully scheduled," i.e. AlarmKit itself is that same kind of OS-owned mechanism. While a mission is in progress the app continuously re-arms AlarmKit's native alert a few seconds out (`AlarmCoordinator.missionInsuranceDelay`, currently 6s, refreshed every 3s) — a legitimate, still-in-progress mission never lets that fire date arrive (so no spurious extra alert), but a force-quit leaves the alarm silent for at most a handful of seconds before AlarmKit's native alert (with its own sound, OS-driven regardless of this app's process) fires again and reopens the app. Finishing the mission (or reaching snooze/turn-off) cancels this re-arm loop.
- **That re-arm survives more than one force-quit in a row.** The re-fired alert above relaunches the app back into a bare "ringing, tap a button" screen by default — which, on its own, has no insurance loop running yet, so a *second* force-quit before you tap anything would have nothing left to re-arm it with. `MissionInsuranceStateStore` persists which alarm has a mission genuinely in progress (written the moment you tap Snooze/Turn Off, cleared only once you actually finish it) specifically so a re-ring can check that flag and jump straight back into the same mission — restarting insurance coverage immediately — instead of waiting for another button tap first. If you're testing this: watch for it via the **Insurance Log** (waveform icon in the alarm list toolbar), which records every re-arm attempt and its outcome so a "why didn't it come back" report can be diagnosed from evidence instead of guesswork.
- **Force-quitting *before* tapping Snooze/Turn Off at all can still lose the alert.** On-device testing found AlarmKit's own record of an actively-alerting alarm doesn't reliably survive a force-quit at that stage either, contrary to what [Apple's AlarmKit FAQ](https://developer.apple.com/forums/thread/797158) implies ("all alarms are expected to persist regardless of app or device state changes") — reopening the app afterward showed the alarm's AlarmKit state as completely blank ("not scheduled"), not merely silenced. Left alone, the app's own startup logic (`reconcileScheduledAlarms`) used to treat "no AlarmKit record" as "never scheduled" and silently reschedule straight for the alarm's *next* regular occurrence — so reopening the app after this happened showed nothing wrong at all, with no indication the alarm had ever been missed. It now checks whether the alarm's regular time passed within the last `AlarmCoordinator.missedAlarmGracePeriod` (20 minutes) before doing that, and if so shows the ringing screen (with mission-gating applying normally) instead of silently rescheduling past it.

**Completing the mission**
- **Snooze**: alarm re-arms for the configured snooze duration; you'll see a snoozed confirmation screen, then it rings again at the new time.
- **Turn off**: a recurring alarm reschedules for its next occurrence; a one-time alarm disables itself. If the reschedule itself fails, the alarm falls back to disabled rather than claiming to still be armed with nothing actually scheduled.

**Editing and relaunching**
- Editing an existing alarm's time starts from that alarm's own scheduled time, not a hardcoded 7 AM — 7 AM is only the default for a brand-new alarm.
- Relaunching the app (or backgrounding/foregrounding) never clobbers an alarm that's mid-snooze — its overridden fire time is preserved instead of being reset back to its regular schedule.
- An error message shown for one action (save, delete, snooze, turn off, reload) always reflects that action's own latest outcome — it won't show a stale error left over from something else you did earlier.

**Wake-up check**
- Fires as a second, independent AlarmKit alert a configurable delay after the main alarm, with its own mission gate, and survives an app relaunch while pending.

## Architecture

```text
SwiftUI UI (Features/)
    ↓
AlarmCoordinator · MissionCoordinator · QuoteCoordinator · WakeUpCoordinator  (Application/)
    ↓
Alarm / Mission / Chess / QR / Quotes / WakeUp domain models  (Domain/)
    ↓
AlarmKitScheduler · PedometerStepCounter · QRScannerView · LocalChessEngine ·
BundledPuzzleRepository · BundledQuoteRepository · File-backed repositories  (Infrastructure/)
```

The alarm engine only ever knows it needs a `Mission`; it never knows whether that mission is steps, a QR code, or a chess puzzle — see design.md §28 for the reasoning.

## Known simplifications (by design, not bugs)

- The chess "engine" validates a user's move against the puzzle's known solution sequence rather than implementing full chess legality (checks, pins, stalemate). See the comment in `Infrastructure/Chess/ChessEngine.swift`.
- Gentle wake-up audio is guaranteed only when the app is foregrounded during the countdown; AlarmKit's own full-volume alert at the real alarm time is what's guaranteed regardless.
- The wake-up check reuses the same AlarmKit alert configuration (with Snooze/Turn Off buttons) as a real alarm, rather than a dedicated simpler alert type.

## Troubleshooting

| Problem | What to try |
|--------|-------------|
| “Failed to code sign” | Set your Team under Signing & Capabilities for both targets |
| Alarms don’t schedule | Check the Alarms permission in Settings; confirm `MorningAlarm.entitlements` has no stray `com.apple.developer.alarmkit` key (it isn't real — see "AlarmKit setup" above) |
| App won’t open after install | Trust the developer certificate in Settings |
| Build fails on AlarmKit APIs | Use Xcode 26+ and iOS 26 SDK |
| No sound | Confirm `default_alarm.wav` is in the app bundle (Resources/Sounds) |

## Next milestones

See `milestones.md` for the full roadmap. v0.1 through v0.11 (recurring alarms, gentle wake, all three mission types, snooze/turn-off wiring, quotes, wake-up check, post-alarm app trigger) are implemented. Not yet done:

- **v0.12** — Reliability hardening across device-locked / terminated / reboot / DST / timezone-change scenarios, plus the automated test suite description.md §21 calls for
- **v0.13** — Alarm history & basic statistics
- **v0.14** — Named difficulty presets (Easy/Medium/Hard)
- **v0.15+** — Mission sequences, morning routines, widgets/App Intents/Siri beyond the existing snooze-countdown widget
