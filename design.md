Yes. For **iOS 26+**, I would structure this as a set of clean abstraction layers rather than letting the UI talk directly to `AlarmKit`, `CoreMotion`, QR scanning, etc.

The important change from the earlier architecture is that **AlarmKit should be the system-facing alarm layer**. Apple provides `AlarmKit` for managing alarms, including alarm presentation/state and alarm metadata. ([Apple Developer][1])

# iOS 26+ Architecture

```text
┌──────────────────────────────────────────────────────────┐
│                    Presentation Layer                    │
│                                                          │
│ SwiftUI Screens                                          │
│ Alarm List • Alarm Editor • Mission UI • Alarm UI        │
│ Wake-up Check • Quotes • Settings                        │
└──────────────────────────┬───────────────────────────────┘
                           │
┌──────────────────────────▼───────────────────────────────┐
│                    Application Layer                     │
│                                                          │
│ AlarmCoordinator                                         │
│ MissionCoordinator                                       │
│ WakeUpCoordinator                                        │
│ MorningRoutineCoordinator                                │
│ QuoteCoordinator                                         │
└──────────────────────────┬───────────────────────────────┘
                           │
┌──────────────────────────▼───────────────────────────────┐
│                      Domain Layer                        │
│                                                          │
│ Alarm                                                    │
│ Mission                                                  │
│ MissionConfiguration                                     │
│ AlarmState                                               │
│ WakeUpCheck                                              │
│ MorningRoutine                                           │
│ Quote                                                    │
│ Puzzle                                                   │
└──────────────────────────┬───────────────────────────────┘
                           │
┌──────────────────────────▼───────────────────────────────┐
│                  Infrastructure Layer                    │
│                                                          │
│ AlarmScheduler                                           │
│ StepCounter                                              │
│ QRScanner                                                │
│ ChessPuzzleEngine                                        │
│ AudioPlayer                                              │
│ QuoteRepository                                          │
│ PuzzleRepository                                         │
│ LocalStore                                               │
│ ExternalAppLauncher                                      │
└──────────────────────────┬───────────────────────────────┘
                           │
┌──────────────────────────▼───────────────────────────────┐
│                     iOS Frameworks                       │
│                                                          │
│ AlarmKit • SwiftUI • SwiftData • CoreMotion              │
│ AVFoundation • Vision/VisionKit • WidgetKit              │
│ ActivityKit • AppIntents • UIKit                         │
└──────────────────────────────────────────────────────────┘
```

---

# 1. Domain Layer

This should contain **zero iOS-specific code** wherever practical.

The domain layer defines what the app *means*.

## `Alarm`

```swift
struct Alarm: Identifiable, Codable {
    let id: UUID

    var time: LocalTime
    var recurrence: Recurrence
    var enabled: Bool

    var sound: AlarmSoundConfiguration
    var gentleWake: GentleWakeConfiguration?

    var snooze: SnoozeConfiguration
    var turnOffMission: MissionConfiguration

    var wakeUpCheck: WakeUpCheckConfiguration?

    var motivationalQuotes: QuoteConfiguration
    var postAlarmAction: PostAlarmAction?
}
```

---

# 2. Mission Abstraction

This is one of the most important abstractions.

Do **not** make the rest of the application know whether a mission is QR, steps, or chess.

```swift
enum MissionType: Codable {
    case steps
    case qrCode
    case chessPuzzle
}
```

Then:

```swift
struct MissionConfiguration: Codable {
    let type: MissionType
    let difficulty: MissionDifficulty
}
```

But the runtime behavior should be abstracted further:

```swift
protocol Mission {
    var id: UUID { get }
    var type: MissionType { get }

    func start() async
    func cancel() async
}
```

And:

```swift
protocol MissionSession {
    var progress: MissionProgress { get }

    func start() async
    func cancel() async

    var completion: AsyncStream<MissionResult> { get }
}
```

The application layer should be able to say:

```swift
let mission = missionFactory.create(configuration)

let session = await mission.start()
```

without knowing what the underlying mission is.

---

# 3. Mission Implementations

## Step Mission

```text
Mission
   │
   └── StepMission
          │
          └── StepCounter
                │
                └── CMPedometer
```

Responsibilities:

* Monitor steps
* Track steps since mission started
* Apply rate limiting
* Apply anti-cheating heuristics
* Report progress
* Determine completion

The mission itself should **not** directly manipulate UI.

---

# 4. QR Mission

```text
Mission
   │
   └── QRCodeMission
          │
          └── QRScanner
                │
                └── VisionKit / AVFoundation
```

The mission should expose:

```swift
struct QRMissionProgress {
    let scanned: Bool
}
```

The UI decides how the scanner is presented.

This separation is important because the QR scanner is an infrastructure concern, while:

> "The user has successfully completed their QR mission"

is domain/application logic.

---

# 5. Chess Mission

```text
Mission
   │
   └── ChessPuzzleMission
          │
          ├── PuzzleRepository
          │
          └── ChessEngine
```

Separate:

### Puzzle selection

```swift
protocol PuzzleRepository {
    func puzzle(
        difficulty: ClosedRange<Int>
    ) async throws -> Puzzle
}
```

### Chess validation

```swift
protocol ChessEngine {
    func validate(
        move: ChessMove,
        position: ChessPosition
    ) -> MoveResult
}
```

This means you can later replace the chess implementation without changing the alarm system.

---

# 6. Alarm Scheduling Layer

This should be its own abstraction.

```swift
protocol AlarmScheduler {

    func schedule(_ alarm: Alarm) async throws

    func update(_ alarm: Alarm) async throws

    func cancel(alarmID: UUID) async throws

    func alarms() async throws -> [ScheduledAlarm]
}
```

The production implementation:

```text
AlarmScheduler
      │
      └── AlarmKitScheduler
                 │
                 └── AlarmKit
```

Apple's AlarmKit provides an alarm daemon/store and exposes alarm updates, which makes it appropriate as the system-facing scheduling layer. ([Apple Developer][1])

Your own `LocalStore` should still retain the application's source-of-truth configuration because the system's one-shot alarm can disappear after firing. Apple specifically notes that fired one-shot alarms are deleted from the daemon store, so an app should persist its own alarms and reconcile them. ([Apple Developer][1])

---

# 7. Alarm Coordinator

This is the **heart of the application**.

```swift
@MainActor
final class AlarmCoordinator {

    private let scheduler: AlarmScheduler
    private let missionCoordinator: MissionCoordinator
    private let wakeUpCoordinator: WakeUpCoordinator
    private let quoteCoordinator: QuoteCoordinator

    func createAlarm(...)
    func updateAlarm(...)
    func deleteAlarm(...)
    func enableAlarm(...)
    func disableAlarm(...)
}
```

It translates:

```text
User configuration
       ↓
Domain Alarm
       ↓
AlarmScheduler
       ↓
AlarmKit
```

And on alarm events:

```text
AlarmKit
   ↓
AlarmCoordinator
   ↓
MissionCoordinator
   ↓
Mission
```

---

# 8. Alarm Runtime State

Keep configuration and runtime state separate.

### Configuration

```swift
struct Alarm {
    let id: UUID
    ...
}
```

### Runtime

```swift
enum AlarmRuntimeState {
    case scheduled
    case gentleWake
    case ringing
    case snoozed(until: Date)
    case completingMission
    case completed
    case wakeUpCheckPending
    case wakeUpCheckActive
    case finished
}
```

This makes the alarm flow explicit rather than scattering boolean flags throughout the application.

---

# 9. Mission Coordinator

The `MissionCoordinator` manages the lifecycle of missions.

```text
                  MissionCoordinator
                         │
            ┌────────────┼────────────┐
            ▼            ▼            ▼
       StepMission   QRCodeMission  ChessMission
```

Responsibilities:

* Create missions
* Start missions
* Track progress
* Cancel missions
* Determine completion
* Handle failure
* Transition to next state

Example:

```swift
func startTurnOffMission(for alarm: Alarm) async {
    let mission = factory.create(alarm.turnOffMission)

    let result = await mission.run()

    switch result {
    case .completed:
        await alarmCoordinator.alarmMissionCompleted()

    case .failed:
        ...
    }
}
```

---

# 10. Wake-Up Coordinator

Keep wake-up checks separate from the initial alarm.

```swift
protocol WakeUpCoordinator {
    func scheduleCheck(
        for alarm: Alarm,
        configuration: WakeUpCheckConfiguration
    ) async

    func startCheck(...)
    func completeCheck(...)
    func cancelCheck(...)
}
```

Flow:

```text
Alarm dismissed
      ↓
WakeUpCoordinator
      ↓
schedule wake-up check
      ↓
AlarmKit
      ↓
Wake-up check fires
      ↓
MissionCoordinator
      ↓
Mission
```

This also makes it easy later to add multiple checks.

---

# 11. Quote Layer

Don't let the UI directly read quotes from storage.

```swift
protocol QuoteRepository {
    func randomQuote(
        category: QuoteCategory
    ) async -> Quote
}
```

Then:

```swift
final class QuoteCoordinator {

    private let repository: QuoteRepository

    func quoteFor(
        event: QuoteEvent
    ) async -> Quote
}
```

Where:

```swift
enum QuoteEvent {
    case snoozed
    case alarmCompleted
    case wakeUpCheckCompleted
}
```

This allows the quote selection logic to evolve independently.

---

# 12. Gentle Wake Layer

```swift
protocol GentleWakeController {
    func schedule(
        for alarm: Alarm,
        configuration: GentleWakeConfiguration
    ) async throws

    func cancel(for alarmID: UUID) async throws
}
```

Possible implementation:

```text
GentleWakeController
        │
        ├── AlarmKit
        └── Audio subsystem
```

Keep this separate from the main alarm logic because gentle waking is conceptually a **pre-alarm experience**, not a mission.

---

# 13. Audio Abstraction

Don't let `AVAudioPlayer` leak into the rest of the app.

```swift
protocol AlarmAudioPlayer {
    func playAlarmSound(_ sound: AlarmSound)
    func stop()
}
```

Implementation:

```text
AlarmAudioPlayer
      ↓
LocalAudioPlayer
      ↓
AVFoundation
```

All sounds should be bundled/local.

---

# 14. Step Counter Abstraction

```swift
protocol StepCounter {
    func currentSteps() async throws -> Int

    func observeSteps(
        from startDate: Date
    ) -> AsyncStream<StepUpdate>
}
```

Implementation:

```text
StepCounter
    ↓
CoreMotion
    ↓
CMPedometer
```

The anti-cheat logic should **not** live inside the Core Motion wrapper.

Instead:

```text
CMPedometer
    ↓
StepCounter
    ↓
StepValidationEngine
    ↓
StepMission
```

For example:

```swift
protocol StepValidationEngine {
    func accept(
        update: StepUpdate,
        state: StepMissionState
    ) -> StepValidationResult
}
```

This makes the anti-cheat behavior independently testable.

---

# 15. QR Scanner Abstraction

```swift
protocol QRScanner {
    func scan() async throws -> QRCode
}
```

Implementation:

```text
QRScanner
    ↓
VisionKit / AVFoundation
```

The mission doesn't care how the QR code was detected.

---

# 16. Chess Abstraction

Use three separate layers:

```text
PuzzleRepository
       ↓
Puzzle
       ↓
ChessEngine
       ↓
ChessPuzzleMission
```

This avoids coupling your alarm system to the puzzle implementation.

---

# 17. Local Persistence

I would use **SwiftData** as the default local persistence layer.

Architecture:

```text
Repositories
     ↓
LocalStore
     ↓
SwiftData
```

For example:

```swift
protocol AlarmRepository {
    func alarms() async throws -> [Alarm]
    func save(_ alarm: Alarm) async throws
    func delete(id: UUID) async throws
}
```

Implementation:

```text
AlarmRepository
      ↓
SwiftDataAlarmRepository
      ↓
ModelContainer
```

The rest of the application never directly accesses SwiftData.

---

# 18. Repository Layer

I would have these core repositories:

```text
AlarmRepository
QuoteRepository
PuzzleRepository
MissionRepository   (optional)
SettingsRepository
```

You don't necessarily need to persist mission objects separately; mission configuration can live inside the alarm.

---

# 19. External App Launcher

Create a very small abstraction:

```swift
protocol ExternalAppLauncher {
    func open(_ destination: AppDestination) async
}
```

For example:

```swift
enum AppDestination {
    case weather
    case calendar
    case robinhood
    case custom(URL)
}
```

Implementation:

```text
ExternalAppLauncher
        ↓
UIApplication / URL scheme
```

This means the alarm logic doesn't contain things like:

```swift
UIApplication.shared.open(...)
```

---

# 20. Presentation Layer

Use SwiftUI.

I would divide it into:

```text
App
│
├── AlarmList
│
├── AlarmEditor
│
├── MissionConfiguration
│
├── QRSetup
│
├── ChessConfiguration
│
├── QuoteSettings
│
├── GentleWakeSettings
│
├── AlarmExperience
│
├── MissionExperience
│
├── WakeUpCheckExperience
│
└── MorningComplete
```

The views should primarily consume `Observable` application models/coordinators.

They should **not** know about:

* AlarmKit
* CoreMotion
* SwiftData
* AVFoundation
* VisionKit

---

# 21. Alarm Experience

This deserves its own UI layer because it's the most important user experience.

```text
AlarmExperience
│
├── AlarmRingingView
│
├── SnoozeView
│
├── TurnOffMissionView
│
├── SuccessView
│
└── MotivationalQuoteView
```

Example state machine:

```text
RINGING
   │
   ├──── SNOOZE ────→ SNOOZE_MISSION
   │                       │
   │                       ↓
   │                   SNOOZED
   │
   └──── GET UP ─────→ TURN_OFF_MISSION
                            │
                            ↓
                        COMPLETED
                            │
                            ↓
                    WAKE_UP_SCHEDULED
```

---

# 22. System Integration Layer

For iOS 26+, I'd also create a dedicated system-integration layer:

```text
SystemIntegration
│
├── AlarmKit
├── AppIntents
├── WidgetKit
├── ActivityKit
└── DeepLinks
```

This keeps Apple's evolving APIs isolated.

### Why this matters

Apple's system experiences are increasingly centered around App Intents. Apple explicitly recommends making App Intents a core integration point for system features, and they can power widgets, Live Activities, Siri/Shortcuts and other system interactions. ([Apple Developer][2])

---

# 23. Live Activity

I would **not make Live Activity part of the core alarm engine**.

Instead:

```text
AlarmCoordinator
       │
       └── AlarmSystemPresentation
                    │
                    └── ActivityKit
```

Use it for things such as:

> ☀️ Morning routine
> Alarm: 7:00
> Mission: Walk 50 steps
> Progress: 32 / 50

ActivityKit supports Lock Screen/Dynamic Island presentation and interactive Live Activities. ([Apple Developer][3])

The alarm should remain functional if Live Activities are unavailable or disabled.

---

# 24. Widget / Control Layer

Similarly:

```text
WidgetExtension
│
├── NextAlarmWidget
├── MorningStatusWidget
└── Controls
```

WidgetKit supports widgets, Live Activities and controls, with App Intents providing their interactions. ([Apple Developer][4])

Potential widget:

> **Next alarm**
>
> ☀️ 7:00 AM
> Walk 50 steps

Potential control:

> **Enable Morning Alarm**

But these are **secondary conveniences**, not core alarm functionality.

---

# 25. App Intents

Create a dedicated layer:

```text
AppIntents
│
├── CreateAlarmIntent
├── EnableAlarmIntent
├── DisableAlarmIntent
├── SnoozeAlarmIntent
├── ShowNextAlarmIntent
└── StartMorningIntent
```

Apple even provides an alarm schema for App Entities that can integrate with Siri and Shortcuts. ([Apple Developer][5])

This could eventually allow:

> "Hey Siri, enable my morning alarm."

without putting Siri-specific logic into your domain layer.

---

# 26. Recommended Final Project Structure

I would actually organize the Xcode project roughly like this:

```text
MorningAlarm/
│
├── App/
│   ├── MorningAlarmApp.swift
│   └── AppDependencyContainer.swift
│
├── Domain/
│   ├── Alarm/
│   │   ├── Alarm.swift
│   │   ├── AlarmState.swift
│   │   ├── AlarmSound.swift
│   │   └── Recurrence.swift
│   │
│   ├── Mission/
│   │   ├── Mission.swift
│   │   ├── MissionType.swift
│   │   ├── MissionConfiguration.swift
│   │   └── MissionResult.swift
│   │
│   ├── WakeUp/
│   │   └── WakeUpCheck.swift
│   │
│   ├── Quotes/
│   │   └── Quote.swift
│   │
│   └── Chess/
│       └── Puzzle.swift
│
├── Application/
│   ├── AlarmCoordinator.swift
│   ├── MissionCoordinator.swift
│   ├── WakeUpCoordinator.swift
│   ├── QuoteCoordinator.swift
│   └── MorningRoutineCoordinator.swift
│
├── Infrastructure/
│   │
│   ├── Alarm/
│   │   └── AlarmKitScheduler.swift
│   │
│   ├── Motion/
│   │   ├── PedometerStepCounter.swift
│   │   └── StepValidationEngine.swift
│   │
│   ├── QR/
│   │   └── VisionQRScanner.swift
│   │
│   ├── Chess/
│   │   ├── LocalPuzzleRepository.swift
│   │   └── LocalChessEngine.swift
│   │
│   ├── Audio/
│   │   └── LocalAlarmAudioPlayer.swift
│   │
│   ├── Persistence/
│   │   ├── SwiftDataStore.swift
│   │   ├── SwiftDataAlarmRepository.swift
│   │   └── SwiftDataSettingsRepository.swift
│   │
│   └── ExternalApps/
│       └── IOSAppLauncher.swift
│
├── Features/
│   ├── AlarmList/
│   ├── AlarmEditor/
│   ├── MissionSetup/
│   ├── AlarmExperience/
│   ├── WakeUpCheck/
│   └── MorningComplete/
│
├── System/
│   ├── AppIntents/
│   ├── Widget/
│   ├── LiveActivity/
│   └── DeepLinks/
│
└── Resources/
    ├── Sounds/
    ├── Quotes/
    └── Puzzles/
```

# 27. Dependency Direction

The most important architectural rule:

```text
                    UI
                     │
                     ▼
              Application
                     │
                     ▼
                  Domain
                     ▲
                     │
              Infrastructure
                     │
                     ▼
                iOS APIs
```

More precisely, **Domain must not depend on iOS**.

```text
Domain
  ❌ AlarmKit
  ❌ SwiftUI
  ❌ CoreMotion
  ❌ SwiftData
  ❌ VisionKit
```

Infrastructure implements domain/application protocols:

```text
protocol AlarmScheduler
        ↑
AlarmKitScheduler
```

```text
protocol StepCounter
        ↑
PedometerStepCounter
```

```text
protocol QRScanner
        ↑
VisionQRScanner
```

This is particularly valuable for this app because **alarm reliability and mission behavior need extensive testing**. You can test the entire alarm state machine using fake implementations without waiting for actual alarms, walking around, scanning QR codes, or solving chess puzzles.

---

# 28. The Core Abstraction

If I were giving this to Claude Code to implement, I'd emphasize one architectural principle above everything else:

> **The alarm engine should know that it needs a `Mission`; it should never know whether that mission uses steps, QR codes, or chess.**

Likewise:

> **The mission should know that it needs a `StepCounter`; it should never know that the step counter is backed by `CMPedometer`.**

And:

> **The scheduler should know that it needs to schedule an alarm; it should never leak AlarmKit types throughout the application.**

That gives you a clean core:

```text
                 ┌───────────────────┐
                 │  AlarmCoordinator │
                 └─────────┬─────────┘
                           │
                 ┌─────────▼─────────┐
                 │ AlarmStateMachine │
                 └─────────┬─────────┘
                           │
                 ┌─────────▼─────────┐
                 │ MissionCoordinator│
                 └─────────┬─────────┘
                           │
          ┌────────────────┼────────────────┐
          ▼                ▼                ▼
      StepMission      QRMission       ChessMission
          │                │                │
     StepCounter        QRScanner       ChessEngine
          │                │                │
     CoreMotion        VisionKit        Local DB
```

**That's the architecture I'd use for the actual implementation.** It keeps the core morning/wake-up behavior testable and makes iOS 26-specific APIs replaceable at the edges.

[1]: https://developer.apple.com/documentation/alarmkit/alarmmanager/alarms?utm_source=chatgpt.com "alarms | Apple Developer Documentation"
[2]: https://developer.apple.com/documentation/AppIntents/getting-started-with-the-app-intents-framework?changes=l_9%2Cl_9&utm_source=chatgpt.com "Getting started with the App Intents framework | Apple Developer Documentation"
[3]: https://developer.apple.com/documentation/activitykit?utm_source=chatgpt.com "ActivityKit | Apple Developer Documentation"
[4]: https://developer.apple.com/documentation/appintents/widgets-live-activities-and-controls?changes=_3%2C_3&utm_source=chatgpt.com "Widgets, Live Activities, and Controls | Apple Developer Documentation"
[5]: https://developer.apple.com/documentation/appintents/appschema/clockentity/alarm?utm_source=chatgpt.com "alarm | Apple Developer Documentation"

