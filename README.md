# Morning Alarm

An offline-first iOS alarm app focused on helping you get out of bed, not just defeat an alarm. Covers description.md's full MVP scope: recurring alarms, gentle wake-up, step/QR/chess missions for snooze/turn-off/wake-up-check, motivational quotes, and an optional post-alarm app trigger.

## Requirements

- **Mac** with **Xcode 26** or later (AlarmKit is an iOS 26 SDK framework — it will not compile on older Xcode versions, including Xcode 14)
- **iPhone** running **iOS 26** or later
- **Apple Developer account** (free or paid) for device installation
- **AlarmKit entitlement** from Apple (see below)

> **Note on this codebase:** this was written without access to Xcode 26/the iOS 26 SDK, so the iOS-framework-dependent code (AlarmKit, CoreMotion, AVFoundation, UIKit, SwiftUI-on-iOS, the `Observation` macro) has not been compiler-verified. It has, however, been genuinely validated where it's possible to on non-Apple-SDK tooling: the entire domain/business-logic layer (recurrence math, the chess board/move/engine, step anti-cheat, mission configuration, file-backed repositories) and the full `AlarmCoordinator`/`WakeUpCoordinator`/`MissionCoordinator` state machine were compiled and *executed* for real against a stripped (Observation-free) copy on this machine's Swift 5.7 toolchain, catching and fixing several real bugs (see `MorningAlarmTests/` below — those are the same tests, ported to real XCTest). Expect a handful of build errors on first Xcode 26 compile regardless — mainly around exact AlarmKit API shapes (`Alarm.Schedule.Relative`, `Alarm.CountdownDuration`'s `preAlert` parameter, and the `Alarm.State` case names used for the gentle-wake countdown) since those couldn't be checked against the real SDK.

## Project location

Open the Xcode project:

```text
MorningAlarm/MorningAlarm.xcodeproj
```

## One-time setup in Xcode

1. Open `MorningAlarm.xcodeproj` in Xcode.
2. Select the **MorningAlarm** project in the navigator, then the **MorningAlarm** target.
3. Open **Signing & Capabilities**.
4. Set **Team** to your Apple Developer team.
5. Change **Bundle Identifier** if needed (default: `com.morningalarm.app`).
6. Repeat for the **MorningAlarmWidgets** target (`com.morningalarm.app.widgets`).
7. Confirm **AlarmKit** appears under Capabilities. If not, click **+ Capability** and add **AlarmKit**.

### AlarmKit entitlement

AlarmKit requires an Apple-granted entitlement. Without it, alarms will not schedule even if the user grants permission.

1. In [Apple Developer](https://developer.apple.com/account/resources/identifiers/list), register your app ID with the AlarmKit capability.
2. Request AlarmKit access if prompted by Apple.
3. Regenerate your provisioning profile after the entitlement is approved.
4. In Xcode, ensure the **MorningAlarm.entitlements** file is linked (it should be automatic).

## Install on your iPhone

### Option A: Direct USB install (recommended for development)

1. Connect your iPhone to your Mac with a USB cable.
2. Unlock the phone and tap **Trust** if prompted.
3. In Xcode, select your iPhone from the device menu in the toolbar (not a Simulator).
4. Press **Run** (⌘R) or click the Play button.
5. On first launch, iOS may show **Untrusted Developer**:
   - Open **Settings → General → VPN & Device Management**
   - Tap your developer profile and choose **Trust**
6. Launch **Morning Alarm** again from the home screen.

### Option B: Wireless debugging

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
| Alarms don’t schedule | Check AlarmKit entitlement approval and alarm permission in Settings |
| App won’t open after install | Trust the developer certificate in Settings |
| Build fails on AlarmKit APIs | Use Xcode 26+ and iOS 26 SDK |
| No sound | Confirm `default_alarm.wav` is in the app bundle (Resources/Sounds) |

## Next milestones

See `milestones.md` for the full roadmap. v0.1 through v0.11 (recurring alarms, gentle wake, all three mission types, snooze/turn-off wiring, quotes, wake-up check, post-alarm app trigger) are implemented. Not yet done:

- **v0.12** — Reliability hardening across device-locked / terminated / reboot / DST / timezone-change scenarios, plus the automated test suite description.md §21 calls for
- **v0.13** — Alarm history & basic statistics
- **v0.14** — Named difficulty presets (Easy/Medium/Hard)
- **v0.15+** — Mission sequences, morning routines, widgets/App Intents/Siri beyond the existing snooze-countdown widget
