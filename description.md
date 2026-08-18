# Requirements: Offline Alarm / Wake-Up App

## 1. Overview

Build an **Alarmy-like alarm app** focused on reliability, offline operation, and, most importantly, **motivating the user to get out of bed**.

The app should not feel like a battle between the user and the alarm. Instead, it should create a natural progression:

> **Wake up → get moving → get out of bed → feel motivated → start the day.**

The app must work **entirely without internet access** during normal operation. All alarm scheduling, sounds, missions, motivational messages, wake-up checks, and puzzle data must be available locally.

---

# 2. Goals

### Primary goals

1. **Reliable alarms**

   * Alarms must fire at the configured time without network connectivity.
   * Alarm functionality should continue when the device is offline.
   * Alarms should survive app termination/relaunch and device restart where the platform permits.

2. **Motivate the user to get up**

   * Missions should encourage physical movement.
   * The turn-off mission should generally require the user to get out of bed.
   * The experience should use positive reinforcement rather than punishment.

3. **Low-friction snoozing**

   * Snoozing should require a simple action.
   * The snooze mission should encourage a small amount of movement without making the user fully commit to getting up.

4. **Meaningful alarm dismissal**

   * Turning off the alarm should require a deliberate action that encourages the user to leave the bed.

5. **Wake-up verification**

   * The app should optionally verify that the user is actually awake after dismissing the alarm.

6. **Gentle waking**

   * Gradually transition the user from sleep toward wakefulness before the main alarm.

7. **Positive reinforcement**

   * Show motivational quotes whenever the user:

     * Snoozes
     * Turns off the alarm
     * Completes a wake-up check

8. **A motivating next action**

   * After successfully turning off the alarm, optionally open an app the user is interested in, such as:

     * Weather
     * Calendar
     * Robinhood
     * Fitness
     * Todo
     * News
     * Music

9. **Offline-first**

   * No account should be required.
   * No backend should be required.
   * No network connection should be required for any core feature.

---

# 3. Core Product Philosophy

The primary objective is **not to make the alarm difficult to turn off**.

The objective is:

> **Make getting out of bed the easiest path to having a good morning.**

Every part of the alarm experience should reinforce this.

### Desired behavioral sequence

```text
Wake up
   ↓
Start moving
   ↓
Get out of bed
   ↓
Complete a small action
   ↓
Receive positive reinforcement
   ↓
Stay awake
   ↓
Start the day
```

Missions should therefore be designed around **movement and positive reinforcement**, rather than frustration.

The product should avoid feeling adversarial:

> ❌ "Beat the alarm."

Instead:

> ✅ "Let's get moving."

---

# 4. Platform

### Initial target

**iOS**

The requirements should be designed around iOS alarm/background-execution constraints rather than assuming an Android-style unrestricted background service.

The implementation should use the platform's native notification/alarm mechanisms wherever possible and explicitly account for:

* App being force-quit
* Device locked
* Device offline
* Low Power Mode
* Focus modes
* Notification permissions
* Background execution restrictions
* Device reboot

Reliability of the alarm is a **P0 requirement**.

---

# 5. Alarm Model

Each alarm should contain:

```text
Alarm
├── Time
├── Repeat schedule
├── Enabled/disabled
├── Alarm sound
├── Gentle wake-up
├── Snooze configuration
├── Turn-off mission
├── Wake-up check
├── Motivational quotes
└── Interesting-app trigger
```

### Alarm configuration

Required:

* Time
* Days of week
* Enabled/disabled
* Alarm sound
* Snooze duration
* Snooze mission
* Turn-off mission

Optional:

* Gentle wake-up
* Wake-up check
* Interesting app
* Custom quote collection
* Number of allowed snoozes

---

# 6. Alarm Sound

The app must ship with a **default alarm sound** bundled locally.

The default sound must:

* Work with no internet connection.
* Be available immediately after installation.
* Not depend on streaming.
* Be compatible with the platform's alarm/notification mechanism.

Potential future options:

* Multiple bundled sounds
* User-selected local audio
* Increasing-volume alarm
* Different sounds for different alarms

---

# 7. Snooze

Snoozing should be a **small step toward waking up**, rather than simply dismissing the alarm.

### Example

Alarm:

> **7:00 AM**

User taps **Snooze**.

The app presents:

> **Snooze for 10 minutes**
>
> Let's get moving first.

The user completes a simple mission, such as walking 5–10 steps, and the alarm resumes at 7:10.

### Snooze requirements

* Configurable snooze duration:

  * 5 minutes
  * 10 minutes
  * 15 minutes
  * 20 minutes
  * Custom
* Configurable maximum snoozes:

  * Unlimited
  * 1–10
* Snooze mission should be quick and achievable.
* Snooze mission should encourage some physical movement.
* Display a motivational quote after successful snooze.

Example:

> *"You don't have to conquer the whole morning. Just get moving."*

The purpose is to make even a snooze **slightly reinforce the desired behavior**.

---

# 8. Missions

The app should support missions that encourage:

1. **Physical movement**
2. **Getting out of bed**
3. **Cognitive engagement**
4. **Moving to another location**

Initial mission types:

* QR Code
* Step Count
* Lichess Chess Puzzle

The missions should be configurable independently for:

* Snooze
* Turn off
* Wake-up check

---

# 9. QR Code Mission

The user registers a QR code during alarm configuration.

Example:

> QR code is placed in the bathroom.

To complete the mission, the user must physically get to the bathroom and scan the QR code.

### Requirements

* QR code registration
* Camera-based scanning
* Local validation
* No network access
* Support multiple registered QR codes
* Optional requirement to scan a specific code

The QR code should be represented internally by its locally stored identifier/content hash rather than requiring a server.

### Intended behavior

The QR code should ideally be placed somewhere that naturally encourages the user to start their morning:

* Bathroom
* Kitchen
* Coffee machine
* Front door
* Desk

The product should encourage this during setup:

> **Where should your morning start?**
>
> Put your QR code somewhere you want to go after waking up.

---

# 10. Step Count Mission

The user must walk a specified number of steps.

Example:

> **Walk 50 steps to turn off the alarm.**

### Configuration

Possible values:

* 10
* 25
* 50
* 100
* 250
* Custom

The app should use the device's motion/pedometer APIs where available.

## Anti-cheating requirements

The system should attempt to prevent trivial shaking/handshake cheating.

It should:

* Use actual pedometer/motion data rather than simply counting accelerometer events.
* Require steps to occur over a minimum elapsed time.
* Rate-limit step accumulation.
* Detect implausibly rapid step sequences.
* Reject obviously artificial movement patterns where possible.
* Require reasonable cadence.

### Example

For a 50-step mission:

```text
50 steps
Minimum elapsed time: 30 seconds
Maximum accepted step rate: configurable
```

If the user rapidly shakes the phone:

> Detected movement, but not enough evidence of walking.

Steps should not count.

### Important limitation

The system should not claim to perfectly detect cheating.

The objective is to make **genuine walking the easiest way to complete the mission**.

---

# 11. Lichess Puzzle Mission

The user can configure a chess puzzle difficulty range.

Example:

> Solve a puzzle with difficulty 1200–1400.

or:

> Solve 2 puzzles between 1000–1300.

### Offline requirement

Because the application must have **no internet dependency**, puzzles must be bundled or imported ahead of time.

The app must **not make a network request when the alarm is active**.

Possible architecture:

```text
Bundled Puzzle Database
        ↓
Local Puzzle Selector
        ↓
Puzzle UI
        ↓
Local Chess Validator
```

### Puzzle requirements

Each puzzle contains:

* Board position
* Side to move
* Expected move sequence
* Difficulty/rating metadata
* Puzzle ID

The app should locally validate the user's moves.

### Difficulty

Support difficulty ranges, for example:

```text
600–800
800–1000
1000–1200
1200–1400
1400–1600
1600–1800
1800+
```

The exact rating scale should be determined based on the bundled dataset.

### Mission behavior

Example:

> **Good morning. One quick puzzle.**

The user must correctly complete the puzzle.

On an incorrect move:

> **Not quite. Try again.**

Optionally:

* No hints
* Limited hints
* Puzzle reset after incorrect move
* Require 2 consecutive puzzles

The purpose is not to frustrate the user. It is to create **just enough cognitive engagement to help them transition into being awake**.

---

# 12. Mission Configuration

The user should configure separate missions for snoozing, turning off, and wake-up checks.

Example:

| Action        | Mission  |
| ------------- | -------- |
| Snooze        | 10 steps |
| Turn off      | QR code  |
| Wake-up check | 50 steps |

Or:

| Action        | Mission             |
| ------------- | ------------------- |
| Snooze        | 1 easy chess puzzle |
| Turn off      | 100 steps           |
| Wake-up check | QR code             |

### Recommended UX

The configuration screen should communicate the purpose of each mission.

**Snooze**

> Small movement to help you wake up.

**Turn off**

> Get yourself out of bed and start your morning.

**Wake-up check**

> Make sure you're still up.

---

# 13. Wake-Up Check

The wake-up check is a second-stage verification after the alarm has been turned off.

### Example flow

```text
7:00
Alarm rings

↓

User completes turn-off mission

↓

"You're up!"

↓

Motivational quote

↓

Wake-up check scheduled for 7:15

↓

Wake-up check

↓

User completes movement mission

↓

"You're officially awake."

↓

Optional interesting app
```

### Configuration

Allow:

* Enable/disable
* Delay after alarm dismissal
* Mission type
* Mission difficulty

Possible delays:

* 5 minutes
* 10 minutes
* 15 minutes
* 20 minutes
* 30 minutes

### Wake-up check missions

Initially:

* QR code
* Step count
* Chess puzzle

The wake-up check should generally encourage **continued movement**, rather than simply testing whether the user can operate the phone.

---

# 14. Motivational Quotes

Quotes should be stored locally.

The app should include a reasonably large built-in quote database.

Quotes should be categorized:

```text
Wake up
Exercise
Work
Discipline
Focus
Persistence
Morning
Humor
General motivation
```

### Display events

A quote should be shown after:

1. Snooze
2. Alarm turned off
3. Wake-up check completed

### Example

**After snooze**

> "You don't need to be ready. Just get moving."

**After turn-off**

> "You got up. Now make the morning count."

**After wake-up check**

> "You're up. The day is yours."

### Requirements

* No internet connection
* Random selection
* Avoid immediate repetition
* Optional favorites
* Optional user-added quotes

---

# 15. Gentle Wake-Up

The app should support a configurable gentle-wake period before the main alarm.

Example:

```text
6:50   Gentle wake begins
       ↓
       Gradually increasing sound
       ↓
7:00   Full alarm
```

### Requirements

Configurable:

* Enable/disable
* Duration:

  * 5 min
  * 10 min
  * 15 min
  * 20 min
  * 30 min
* Starting volume
* Ending volume
* Gentle wake sound

The goal is to **start waking the user before they need to get out of bed**, making the transition to the main alarm more natural.

---

# 16. Interesting App Trigger

After successfully turning off the alarm, optionally open an interesting/relevant app.

Examples:

* Weather
* Calendar
* Robinhood
* Fitness app
* News app
* Todo app
* Music
* Podcast app

### Configuration

```text
After alarm:

[ Open Weather ]
```

or:

```text
After alarm:

[ Open Calendar ]
```

### Requirements

* Use iOS deep links / URL schemes where supported.
* The target app must already be installed.
* If the app cannot be opened, fail gracefully.
* Never require internet access from the alarm app itself.
* Do not make opening an external app a prerequisite for dismissing the alarm.

### Product intent

The app should help create a **positive reason to get out of bed**.

For example:

> **You're up! ☀️**
>
> *"A good day starts with a good first step."*
>
> **See today's weather →**

The interesting app should feel like the **reward for getting up**, not another obstacle.

---

# 17. Complete Alarm Flow

### Standard flow

```text
                6:50
                 │
                 ▼
          Gentle Wake-Up
                 │
                 │
                7:00
                 │
                 ▼
          ┌─────────────┐
          │ Alarm rings │
          └──────┬──────┘
                 │
        ┌────────┴────────┐
        │                 │
      Snooze            Turn Off
        │                 │
        ▼                 ▼
   Small movement     Get out of bed
        │                 │
        ▼                 ▼
 Motivational        Mission
   quote                 │
                          ▼
                    Motivational
                       quote
                          │
                          ▼
                    "You're up!"
                          │
                          ▼
                   Wake-up check
                          │
                          ▼
                    Keep moving
                          │
                          ▼
                    Motivational
                       quote
                          │
                          ▼
                 Open interesting app
```

---

# 18. Example User Experience

### 7:00 AM

The alarm begins.

> ☀️ **Good morning**
>
> Let's get moving.

Buttons:

**SNOOZE**
**GET UP**

---

### Snooze

User taps **SNOOZE**.

> **Take 10 seconds to get moving.**
>
> Walk 10 steps.

User walks around the room.

> **Snoozed until 7:10.**
>
> *"You don't have to conquer the whole morning. Just take the first step."*

---

### Turn off

User taps **GET UP**.

> **You're almost there.**
>
> Walk 50 steps.

User gets out of bed and walks.

> 🎉 **You're up!**
>
> *"You don't need motivation to start. Starting creates motivation."*

---

### Wake-up check

At 7:20:

> **Still up?**
>
> Walk 50 steps.

After completion:

> **You're officially awake.**
>
> *"Small victories become big days."*

Then:

> **Open Calendar →**

The user starts looking at their day rather than returning to bed.

---

# 19. Offline Architecture

The application should have **zero backend dependencies** for core functionality.

```text
                 iOS App
                    │
        ┌───────────┼───────────┐
        │           │           │
    Alarm Engine  Missions   Local Data
        │           │           │
        │       ┌───┼───┐       │
        │       │   │   │       │
        │      QR Steps Chess  Quotes
        │                   │
        │             Puzzle DB
        │
   Local Scheduling
```

### Local storage

Store locally:

* Alarm configurations
* QR codes
* Mission settings
* Puzzle database
* Quotes
* User preferences
* Alarm history
* Wake-up-check state

Potential technologies:

* Swift
* SwiftUI
* UserDefaults for simple settings
* Core Data / SwiftData / SQLite for structured data
* Core Motion / CMPedometer for steps
* AVFoundation for local audio
* VisionKit / AVFoundation for QR scanning
* Local notifications / appropriate iOS alarm mechanisms

---

# 20. Privacy

The app should follow a **local-first privacy model**.

Requirements:

* No account required.
* No analytics required.
* No advertising SDK.
* No cloud synchronization required.
* No user data transmitted by default.
* No network connection required.
* Motion data remains on-device.
* QR data remains on-device.
* Alarm history remains on-device.

If analytics are ever introduced, they should be explicitly opt-in.

---

# 21. Reliability Requirements

This is the most important section.

### P0

The alarm must:

* Fire at the configured time.
* Work while the phone is locked.
* Work without internet.
* Work without the app being open.
* Persist across normal app lifecycle events.
* Provide an obvious alarm UI/audio experience permitted by iOS.

The application should have automated tests for:

* Alarm scheduled 1 minute in future
* Alarm scheduled several hours in future
* Repeating alarms
* Multiple alarms
* Device locked
* No network
* App suspended
* App terminated
* Low Power Mode
* Snooze
* Mission completion
* Mission failure
* Wake-up check
* Alarm rescheduling

---

# 22. Behavioral Design / Anti-Cheat Philosophy

The application should optimize for **behavioral effectiveness rather than perfect cheat prevention**.

The goal is not to create an adversarial system that forces the user to fight their alarm.

The goal is to make **genuine waking and movement the easiest way to complete the alarm flow**.

For example:

### Step mission

Bad:

> Count every accelerometer movement as a step.

Better:

> Require pedometer-recognized steps + minimum elapsed time + reasonable cadence.

### QR mission

The user could technically move the phone to the QR code without moving themselves. The QR code should therefore be positioned somewhere that encourages the user to physically go there.

### Chess mission

The user could make repeated attempts, but the puzzle requires enough cognitive engagement to help transition into wakefulness.

### Overall principle

> **Don't punish the user for being sleepy. Help them become awake.**

---

# 23. MVP Scope

### P0 — Required for first release

* Local alarms
* Default alarm sound
* Snooze
* Easy movement-based snooze mission
* Turn-off mission designed to get the user out of bed
* QR mission
* Step-count mission
* Local chess puzzles
* Puzzle difficulty selection
* Wake-up check
* Motivational quotes
* Gentle wake-up
* Open another app after dismissal
* Fully offline operation
* Local persistence

### P1

* Multiple alarm sounds
* Custom quotes
* Quote favorites
* Custom QR missions
* More sophisticated step anti-cheating
* Alarm history
* Statistics
* Multiple missions in sequence
* Difficulty presets
* Personalized morning routines

### P2

* Adaptive difficulty
* Streaks
* Personalized mission difficulty
* Sleep/wake analytics
* More puzzle types
* Custom mission combinations
* Local ML-based motion classification

---

# 24. Suggested Default Configuration

The default experience should optimize for **getting the user out of bed**, not maximizing mission difficulty.

**Alarm:** 7:00 AM
**Gentle wake:** 10 minutes
**Snooze:** 10 minutes
**Snooze mission:** 10 steps
**Turn-off mission:** 50 steps
**Wake-up check:** 15 minutes later
**Wake-up check mission:** 50 steps
**Quote:** Random motivational quote
**Interesting app:** Calendar or Weather

The resulting experience is:

> **Wake gently → start moving → get out of bed → receive positive reinforcement → stay awake → start the day.**

That should be the central product identity.

