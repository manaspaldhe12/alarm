# Morning Alarm App — Milestones

## Product Goal

Build an **offline-first iOS alarm app** that helps the user **get out of bed and start the day**, rather than simply forcing them to defeat an alarm.

Core progression:

> **Wake → move → get up → complete a small challenge → feel motivated → start the day**

Each milestone should produce a usable app. Avoid building the entire architecture before having a working alarm.

---

# v0.0 — Basic Alarm

### Goal

Prove that the fundamental alarm experience works reliably.

### Features

* Create an alarm
* Set alarm time
* Enable/disable alarm
* Delete alarm
* Default alarm sound
* Alarm fires at configured time
* Basic alarm screen
* Stop alarm
* Snooze
* Local-only operation

### UI

```text
Alarms

┌─────────────────────────────┐
│  7:00 AM              ON    │
│  Alarm                      │
└─────────────────────────────┘

              [+]
```

Alarm screen:

```text
☀️ Good morning

7:00 AM

[Snooze]    [Turn Off]
```

### Architecture introduced

* `Alarm`
* `AlarmRepository`
* `AlarmScheduler`
* `AlarmCoordinator`
* Basic SwiftUI UI
* Local persistence
* AlarmKit integration

### Acceptance criteria

* Alarm can be created.
* Alarm fires at the requested time.
* Alarm works with no internet.
* Alarm can be snoozed.
* Alarm can be turned off.
* App can be closed after scheduling.
* Alarm configuration persists.

---

# v0.1 — Recurring Alarms

### Goal

Make the alarm useful for everyday life.

### Features

* Repeat by day of week
* Weekdays
* Weekends
* Every day
* Custom recurrence
* Enable/disable recurring alarm
* Multiple alarms

Example:

```text
7:00 AM
Mon Tue Wed Thu Fri
```

### Architecture

Add:

```text
Recurrence
AlarmSchedule
```

Update:

```text
AlarmScheduler
AlarmRepository
AlarmCoordinator
```

### Acceptance criteria

* Alarm can repeat indefinitely.
* Different alarms can have different schedules.
* Disabling an alarm stops future occurrences.
* Editing an alarm correctly updates future occurrences.

---

# v0.2 — Chess Integration

### Goal

Introduce the first **cognitive wake-up mission**.

### Features

* Local chess puzzle database
* Puzzle selection by difficulty
* Chess board UI
* Move validation
* Complete puzzle mission
* Configure chess mission for alarm
* Chess mission required to turn off alarm

Example:

```text
Turn-off mission

Solve 1 puzzle
Difficulty: 1000–1200
```

### Architecture

Add:

```text
Puzzle
PuzzleRepository
ChessEngine
ChessPuzzleMission
Mission
MissionCoordinator
```

### Important constraint

**No network access.**

All puzzles and validation must work locally.

### Acceptance criteria

* Alarm can be configured with a chess mission.
* Puzzle appears when alarm is active.
* User can play the puzzle.
* Correct solution completes the mission.
* Incorrect moves don't complete it.
* App works with airplane mode enabled.

---

# v0.3 — Step Integration

### Goal

Introduce the first **physical wake-up mission**.

This is a major milestone because it changes the product from:

> "Solve something to turn off the alarm"

to:

> **"Get out of bed to turn off the alarm."**

### Features

* Step-count mission
* Configurable number of steps
* Real-time progress
* Mission completion
* Minimum elapsed time
* Basic step-rate limiting
* Basic anti-shaking validation

Example:

```text
GET MOVING

Walk 50 steps

32 / 50
████████████░░░░
```

### Architecture

Add:

```text
StepCounter
StepValidationEngine
StepMission
```

Backed by:

```text
CoreMotion / CMPedometer
```

### Acceptance criteria

* Step mission can be configured.
* Steps are detected while mission is active.
* Progress updates correctly.
* Mission completes after required steps.
* Unrealistically fast step accumulation is rejected.
* Simple phone shaking doesn't trivially complete the mission.

---

# v0.4 — Mission Framework

### Goal

Unify chess and steps under a generic mission system.

At this point, don't continue adding mission-specific logic directly to the alarm code.

### Features

Generic:

```text
Mission
MissionConfiguration
MissionResult
MissionSession
MissionCoordinator
MissionFactory
```

Supported:

```text
Steps
Chess
```

### Configuration

```text
Turn-off mission

○ Steps
○ Chess
○ QR Code
```

Only Steps and Chess are enabled initially.

### Architecture

```text
                 Mission
                    │
          ┌─────────┴─────────┐
          │                   │
     StepMission        ChessMission
```

### Acceptance criteria

The alarm engine should have no knowledge of the individual mission types.

It should simply execute:

```swift
missionCoordinator.run(mission)
```

---

# v0.5 — QR Code Mission

### Goal

Introduce a mission that **physically moves the user to another location**.

### Features

* Register QR code
* Name QR code
* Scan QR code
* Validate locally
* QR mission
* Configure QR mission for turn-off

Example:

> **Scan your bathroom QR code**

The user registers the QR code beforehand and places it somewhere away from the bed.

### Architecture

Add:

```text
QRScanner
QRCodeMission
QRCodeRepository
```

Using appropriate iOS camera/Vision APIs.

### Acceptance criteria

* User can register a QR code.
* User can place it somewhere physically distant.
* Alarm can require scanning it.
* Only the configured QR code completes the mission.
* No network connection is required.

---

# v0.6 — Snooze Missions

### Goal

Make even snoozing encourage the user to **start moving**.

### Features

* Enable mission for snooze
* Separate snooze mission configuration
* Easy mission
* Snooze duration
* Maximum snooze count
* Motivational quote after snooze

Example:

```text
Snooze

Walk 10 steps

10 / 10 ✓

Snoozed until 7:10
```

### Important product distinction

Snooze should be **easy**.

Turn-off should encourage the user to **actually get up**.

Example:

```text
Snooze:
10 steps

Turn off:
50 steps
```

---

# v0.7 — Motivational Quotes

### Goal

Introduce positive reinforcement.

### Features

Local quote database.

Quotes displayed after:

* Snooze
* Alarm completion
* Mission completion

Categories:

```text
Morning
Discipline
Exercise
Focus
Persistence
General motivation
Humor
```

Example:

> **You're moving. That's the hardest part.**

### Architecture

```text
Quote
QuoteRepository
QuoteCoordinator
QuoteEvent
```

### Acceptance criteria

* Quotes work offline.
* Quotes don't immediately repeat.
* Quote is shown after relevant actions.
* User can optionally favorite quotes.

---

# v0.8 — Wake-Up Check

### Goal

Prevent the user from completing the alarm mission and immediately going back to sleep.

### Features

* Enable/disable wake-up check
* Configurable delay
* Wake-up check mission
* Separate mission configuration
* Motivational quote after completion

Example:

```text
7:00
Alarm
 ↓
Walk 50 steps
 ↓
Alarm completed
 ↓
7:15
Wake-up check
 ↓
Walk 50 steps
 ↓
"You're officially awake."
```

### Architecture

Add:

```text
WakeUpCheck
WakeUpCoordinator
WakeUpCheckScheduler
```

### Acceptance criteria

* Wake-up check can be configured.
* It triggers after the configured delay.
* It has its own mission.
* Completing it ends the morning alarm flow.
* It works offline.

---

# v0.9 — Gentle Wake-Up

### Goal

Make waking itself more pleasant.

### Features

* Enable/disable gentle wake
* Configurable duration
* Gradual sound increase
* Local gentle wake sound

Example:

```text
6:50
      Gentle wake
         ↓
      gradually
       louder
         ↓
7:00
     Main alarm
```

### Acceptance criteria

* Gentle wake begins before main alarm.
* Volume/intensity increases over configured period.
* Main alarm still works independently.
* Disabling gentle wake does not affect the main alarm.

---

# v0.10 — Morning App Trigger

### Goal

Give the user a **positive reason to interact with the phone after getting up**.

### Features

Configure an app to open after successful alarm completion.

Initial targets:

* Calendar
* Weather
* Robinhood
* Music
* Fitness
* Todo
* News

Example:

```text
After completing alarm:

☀️ You're up!

"Make today count."

[Open Calendar]
```

### Architecture

```text
PostAlarmAction
ExternalAppLauncher
AppDestination
```

### Acceptance criteria

* User can configure a destination.
* App opens after successful completion where iOS permits.
* Missing/unavailable app fails gracefully.
* Alarm completion does not depend on external app opening.

---

# v0.11 — Complete Morning Experience

### Goal

Combine all the individual pieces into the intended product experience.

### Example

```text
6:50
│
├── Gentle wake
│
7:00
│
├── Alarm
│
├── Snooze → 10 steps
│
├── Turn off → 50 steps
│
├── Motivational quote
│
7:15
│
├── Wake-up check → 50 steps
│
├── Motivational quote
│
└── Open Calendar
```

### UX polish

* Better alarm screen
* Better mission transitions
* Positive language
* Progress animations
* Haptic feedback
* Better success states
* Morning-focused visual design

The entire experience should feel:

> **"Let's get you moving."**

rather than:

> **"You aren't allowed to turn off this alarm."**

---

# v0.12 — Reliability & Edge Cases

### Goal

Make the app trustworthy enough for daily use.

### Test extensively

* Device locked
* App suspended
* App terminated
* Force quit
* Reboot
* No network
* Airplane mode
* Low Power Mode
* Focus modes
* Multiple alarms
* Recurring alarms
* Alarm edits
* Alarm deletion
* Snooze
* Wake-up checks
* Missed alarms
* Time zone changes
* Daylight saving time
* Phone clock changes

### Architecture

Add:

```text
AlarmReconciliationService
AlarmRecoveryService
SystemStateMonitor
```

The app should reconcile its local alarm configuration with the system alarm state when appropriate.

---

# v0.13 — Alarm History & Basic Statistics

### Goal

Help the user understand their morning behavior.

### Features

* Alarm completed
* Number of snoozes
* Mission type
* Mission completion time
* Wake-up check completed
* Morning start time

Example:

```text
Today

7:00  Alarm
7:02  Snoozed
7:10  Turned off
7:25  Wake-up check ✓

Total snooze: 1
Time to get up: 10 min
```

This should remain **local-only**.

---

# v0.14 — Better Mission Difficulty

### Goal

Allow missions to become progressively more effective.

Examples:

### Steps

```text
Easy       10 steps
Medium     50 steps
Hard       100 steps
```

### Chess

```text
Easy       600–900
Medium     900–1200
Hard       1200–1500
```

### QR

```text
Easy       Nearby QR
Hard       QR across the house
```

The user should control difficulty.

---

# v0.15 — Mission Sequences

### Goal

Allow multiple actions in one alarm.

Example:

```text
GET UP

1. Walk 30 steps
       ↓
2. Scan bathroom QR
       ↓
3. Solve 1 chess puzzle
       ↓
🎉 You're up!
```

Configuration:

```text
Turn-off mission

[+] Add mission

1. Steps — 30
2. QR — Bathroom
3. Chess — 1000–1200
```

This is a natural extension of the mission abstraction developed in v0.4.

---

# v0.16 — Personal Morning Routines

### Goal

Turn the alarm into a lightweight morning routine.

Example:

```text
7:00  Alarm
 ↓
7:02  Walk 50 steps
 ↓
7:05  Scan bathroom QR
 ↓
7:15  Wake-up check
 ↓
7:16  Open Calendar
```

Allow users to configure a reusable:

> **Morning Routine**

and attach it to alarms.

---

# v0.17 — Widgets & System Integration

### Goal

Make the app feel native to iOS.

### Features

* Next alarm widget
* Alarm status widget
* Morning routine widget
* App Intents
* Siri / Shortcuts integration
* Optional Live Activity

Example widget:

```text
☀️ Morning

Next alarm
7:00 AM

Turn-off:
50 steps
```

These should remain convenience features and **never become dependencies of the alarm system**.

---

# v0.18 — Polish / Release Candidate

### Goal

Prepare for real-world daily use.

### Focus

* Onboarding
* Permissions
* Error handling
* Accessibility
* VoiceOver
* Dynamic Type
* Haptics
* Animations
* Battery impact
* Memory usage
* App launch performance
* Migration between app versions
* Data corruption recovery
* Comprehensive automated testing

---

# v1.0 — Daily Driver

The v1.0 experience should support:

### Alarm

* One-time alarms
* Recurring alarms
* Multiple alarms
* Reliable local scheduling
* Default sound
* Gentle wake

### Missions

* Steps
* QR codes
* Chess
* Configurable difficulty
* Snooze missions
* Turn-off missions
* Mission sequences

### Wake-up

* Wake-up checks
* Motivational quotes
* Post-alarm app trigger

### Privacy

* No account
* No backend
* No internet requirement
* Local data

### iOS integration

* Widgets
* App Intents
* Shortcuts/Siri
* Appropriate system alarm UI
* Optional Live Activity

---

# Milestone Dependency Graph

The implementation order should look roughly like:

```text
v0.0 Basic Alarm
       │
       ▼
v0.1 Recurring Alarm
       │
       ├──────────────┐
       ▼              ▼
v0.2 Chess        v0.3 Steps
       │              │
       └──────┬───────┘
              ▼
       v0.4 Mission Framework
              │
              ▼
       v0.5 QR Mission
              │
              ▼
       v0.6 Snooze Missions
              │
              ▼
       v0.7 Motivational Quotes
              │
              ▼
       v0.8 Wake-up Check
              │
              ▼
       v0.9 Gentle Wake
              │
              ▼
       v0.10 App Trigger
              │
              ▼
       v0.11 Complete Experience
              │
              ▼
       v0.12 Reliability
              │
              ▼
       v0.13 Statistics
              │
              ▼
       v0.14 Difficulty
              │
              ▼
       v0.15 Mission Sequences
              │
              ▼
       v0.16 Morning Routines
              │
              ▼
       v0.17 iOS Integration
              │
              ▼
       v0.18 Release Candidate
              │
              ▼
             v1.0
```

## Recommended implementation strategy

The first **four milestones should be deliberately small**:

**v0.0:** prove the alarm works
**v0.1:** prove scheduling works
**v0.2:** prove cognitive missions work
**v0.3:** prove physical missions work

After that, **v0.4's generic mission abstraction becomes the foundation for everything else**. This avoids spending weeks building a sophisticated architecture before you've proven that the core alarm experience actually works.


