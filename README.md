# Morning Alarm

An offline-first iOS alarm app focused on helping you get out of bed. This is **v0.0** — a basic alarm with local scheduling, snooze, and turn-off.

## Requirements

- **Mac** with **Xcode 26** or later
- **iPhone** running **iOS 26** or later
- **Apple Developer account** (free or paid) for device installation
- **AlarmKit entitlement** from Apple (see below)

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

## v0.0 features

- Create, edit, enable/disable, and delete alarms
- Default bundled alarm sound (`default_alarm.wav`)
- Alarm fires via **AlarmKit** (works offline, when locked, without the app open)
- Basic alarm screen with **Snooze** and **Turn Off**
- Local JSON persistence (alarms survive app restart)
- Widget extension for AlarmKit snooze countdown UI

## Architecture (v0.0)

```text
SwiftUI UI
    ↓
AlarmCoordinator
    ↓
AlarmRepository + AlarmScheduler
    ↓
File storage + AlarmKit
```

## Troubleshooting

| Problem | What to try |
|--------|-------------|
| “Failed to code sign” | Set your Team under Signing & Capabilities for both targets |
| Alarms don’t schedule | Check AlarmKit entitlement approval and alarm permission in Settings |
| App won’t open after install | Trust the developer certificate in Settings |
| Build fails on AlarmKit APIs | Use Xcode 26+ and iOS 26 SDK |
| No sound | Confirm `default_alarm.wav` is in the app bundle (Resources/Sounds) |

## Next milestones

See `milestones.md` for the full roadmap. Up next:

- **v0.1** — Recurring alarms (weekdays, weekends, custom)
- **v0.2** — Chess puzzle missions
- **v0.3** — Step-count missions
