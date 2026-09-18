# LSAT Study Timer — Project Intelligence File

> This file is the authoritative reference for all AI-assisted development on this project.
> Read it in full before writing any code, generating any UI, or making architectural decisions.

---

## Project Overview

**App Name:** LSAT Timer
**Platforms:** iOS (primary) + macOS (native SwiftUI, feature-identical twin — see [Mac App](#mac-app))
**Purpose:** A minimal, distraction-free timer for tracking daily and cumulative LSAT study time, synced across a user's devices.
**Target User:** Law school applicants self-studying for the LSAT who want a frictionless way to track study hours.

**Plan of record:** the macOS port is tracked as a wayfinder map, [issue #3](https://github.com/IncoherentThoughts/LSAT-Tracker/issues/3), on `IncoherentThoughts/LSAT-Tracker`. It carries the up-to-date ticket-by-ticket status and the "Decisions so far" log; this file documents the architecture as it stands and is corrected as tickets land, but the map is the source of truth for what is done versus in flight. See also `docs/adr/` for the design decisions behind the Clock, derived totals, and sync, and `CONTEXT.md` for the domain glossary.

---

## External Skills & References

Before generating any Swift/SwiftUI code or UI design, read and apply the following skill sets:

- **iOS Swift Development:** https://skills.sh/aj-geddes/useful-ai-prompts/ios-swift-development
- **Mobile iOS Design:** https://skills.sh/wshobson/agents/mobile-ios-design

Also consult:
- `Examples/` folder — all image files in this folder represent the target UI aesthetic. Match the visual language precisely.

---

## Architecture & Tech Stack

- **Language:** Swift (latest stable)
- **UI Framework:** SwiftUI (100% — no UIKit unless absolutely required for system APIs)
- **Persistence:** SwiftData (preferred) or UserDefaults for simple key-value; Core Data as fallback
- **Live Activity:** ActivityKit (iOS Live Activity on Lock Screen + Dynamic Island)
- **Minimum Deployment Target:** iOS 17+, macOS 14+
- **Package Manager:** Swift Package Manager only

### File Structure (as it stands)
```
LSAT Tracker/
├── LSAT_TrackerApp.swift          # @main. iOS WindowGroup; macOS scenes (MenuBarExtra, Window, Go menu) land with #10
├── Theme.swift                    # Palette + typography helpers — also in the widget extension target
├── Models/
│   ├── ClockSnapshot.swift        # The Clock State as a plain value: Clock Actions, Rollover, merge, suite read/write — widget-shared
│   ├── LSATTimerAttributes.swift  # App-group suite name, TimerKey key catalogue, ActivityKit attributes (#if os(iOS)) — widget-shared
│   ├── ToggleTimerIntent.swift    # AppIntent behind the Live Activity's play/pause button — widget-shared
│   ├── StudySession.swift         # @Model — one record per Study Day
│   ├── StudyStore.swift           # SwiftData gateway: upsert/dedupe, derived past totals, backup export/import, chart stats
│   └── TimerManager.swift         # @Observable owner of the in-memory ClockSnapshot, Live Activity pipeline, foreground/background hooks
├── Views/
│   ├── MainTabView.swift          # Root tab container + floating capsule tab bar
│   ├── Timer/
│   │   └── TimerView.swift        # Landing page
│   ├── Stats/
│   │   ├── StatsView.swift
│   │   └── Charts/
│   │       ├── DailyBarChart.swift
│   │       ├── WeeklyLineChart.swift
│   │       ├── MonthlyHeatmap.swift
│   │       └── TotalRingChart.swift
│   ├── Settings/
│   │   ├── SettingsView.swift
│   │   └── ManualEditView.swift
│   └── Shared/
│       └── SharedWidgetViews.swift # Views the Live Activity, (planned) Mac popover, and (planned) timeline widget all use — widget-shared
├── LSAT Tracker.entitlements / .macOS.entitlements
└── Mac/                            # Not yet present — menu bar shell lands with #10 (see Mac App)

LSAT Timer Widget/                  # Widget extension target
├── LSATTimerWidget.swift           # ActivityConfiguration + DynamicIsland (the Live Activity)
└── WidgetBundle.swift              # @main bundle

Examples/                           # Reference images — do not ship in app bundle
```

Widget-target membership is the `membershipExceptions` list in the
`.xcodeproj`. Only the five files above marked "widget-shared" may be
referenced from the widget extension's code
(`Models/LSATTimerAttributes.swift`, `Models/ToggleTimerIntent.swift`,
`Models/ClockSnapshot.swift`, `Theme.swift`, `Views/Shared/SharedWidgetViews.swift`).

---

## Core Features

### 1. Timer (Landing Page)
- **Daily Timer** — large, centered, prominent. Tracks study time for the current day only.
  - Resets at **4:00 AM in the user's local timezone** (use device time zone settings).
  - Cannot be reset from this screen — only from Settings.
  - Persists across app kills/restarts (store start timestamps, not elapsed seconds).
- **Total Timer** — displayed below the daily timer in smaller, muted font.
  - Shows cumulative all-time study time.
  - Never resets automatically — only via Settings with confirmation.
- **Controls:**
  - Single large **Start** button when paused → transitions to **Pause** button when running.
  - No reset button on this screen whatsoever.
- **Animations:**
  - Smooth fade/scale on start/pause state transitions.
  - Timer digits use a monospaced font to prevent layout jitter.
  - Subtle pulse animation on the timer ring or background when actively running.

### 2. Statistics Page (Right Panel)
Charts and insights the user should see (implement all of these):

| Chart | Description |
|---|---|
| **Daily Bar Chart** | Last 7 days of study time as vertical bars. Highlight today. |
| **Weekly Line Chart** | Rolling 8-week view of total hours per week. |
| **Monthly Heatmap** | GitHub-style grid — each day of the current month colored by intensity of study time. |
| **All-Time Ring / Donut** | Total hours broken into buckets (e.g., 0–50h, 50–100h, 100–200h+) or by month. |
| **Streak Counter** | Number of consecutive days with at least 1 minute of study time. Show current streak prominently at top of stats page. |
| **Daily Average** | Average daily study time over the last 30 days, displayed as a stat card. |
| **Best Day** | Highlight the single best study day ever with date and duration. |

Use Swift Charts (native) for all chart components.

### 3. Settings Page (Left Panel)
- **Daily Goal** — stepper (1–10 hours, default 4h) that sets the Live Activity progress bar target. Stored in shared UserDefaults key `"dailyGoal"`.
- **Reset Daily Timer** — resets today's timer to 0:00:00. Confirm once with an action sheet or alert.
- **Reset Total Timer** — deletes every Session and zeroes today's Clock, which is what "all-time total" derives from (see `docs/adr/0002-derived-all-time-totals.md`). Confirm **twice** (two sequential confirmation dialogs) before executing. Today this resets only the signed-in device's own history; once sync ([issue #13](https://github.com/IncoherentThoughts/LSAT-Tracker/issues/13)) lands, this becomes a global reset of the Account's Sessions everywhere, and the second confirmation's copy must say so.
- **Advanced Options** (collapsible section):
  - **Manual Day Edit** — user selects a date from a date picker, then inputs a custom study duration for that day (hours + minutes). This overwrites whatever was recorded for that date. Useful if they forgot to start the timer or left it running overnight.
  - Input validation: duration must be between 0 and 23h 59m.
  - Warn user if they are editing a future date.
- **App Version** — shown at bottom of settings, non-interactive.

### 4. iOS Live Activity
- Appears automatically on the Lock Screen and Dynamic Island when the timer starts.
- Started by the main app via `ActivityKit`; does **not** require user setup like a widget.
- Shows:
  - Today's elapsed study time (live-counting large text via `Text(_:style: .timer)`)
  - A sleek horizontal progress bar (progress toward the daily goal from Settings)
  - **Play / Pause** button that controls the main app timer from the lock screen
- Uses `AppIntent` (`ToggleTimerIntent`) for interactive controls (iOS 17+)
- Shares state with main app via **App Groups** + shared `UserDefaults` suite
- Dynamic Island support: compact, expanded, and minimal presentations
- Live Activity ends automatically when the daily timer is reset; starts again when the timer starts
- **Pause = end with grace, never update-in-place:** pausing (in-app or via the Lock Screen intent) ends the activity with the paused state as final content and `dismissalPolicy: .after(now + 30 min)`, so the SYSTEM removes the card with no app wakeup (survives force-quit/reboot). A `staleDate` never removes a card — it only marks it `.stale` — and an un-ended activity otherwise sits on the Lock Screen for up to 12 h. The ended card is a frozen snapshot: render it without the play/pause button (`ContentState.isEnded`). All activity mutations in `TimerManager` are serialized through one FIFO task pipeline; enumerate `Activity.activities` inside the queued op, not at enqueue time.

---

## Navigation Structure

```
MainTabView (TabView with .tabViewStyle(.page) or custom bottom nav)
├── [Left]   Settings
├── [Center] Timer (default tab on launch)
└── [Right]  Statistics
```

Bottom navigation bar with three icons — see `Examples/` for icon placement and style. Use SF Symbols. No tab labels, just icons (minimalist).

---

## UI & Design System

### Color Palette
All colors must be defined as `Color` extensions in a `Theme.swift` file and referenced by name everywhere. Never use hardcoded hex values in view code.

```swift
extension Color {
    static let toffeeBrown   = Color(hex: "#9E6240")  // primary text, icons
    static let lightBronze   = Color(hex: "#DEA47E")  // secondary — muted labels, inactive elements
    static let rosyCopper    = Color(hex: "#CD4631")  // active states, progress bars, accents
    static let eggshell      = Color(hex: "#F8F2DC")  // app background
    static let skyReflection = Color(hex: "#81ADC8")  // achievement callouts, streaks, highlights
}
```

**Usage guidelines:**
- Background: `eggshell`
- Primary text / icons: `toffeeBrown`
- Running timer accent / progress / buttons: `rosyCopper`
- Secondary/muted text: `lightBronze`
- Achievement callouts, streaks, best-day: `skyReflection`
- Card backgrounds: `Color.toffeeBrown.opacity(0.08)` — subtle warm elevation against eggshell
- Nav bar background: `toffeeBrown` — creates contrast between content area and navigation
- Never use hardcoded hex values in view code — always reference palette names
- `Theme.swift` must be in **both** the main app target and the widget extension target

### Typography
- Timer display: SF Pro Rounded, monospaced digits, large weight
- Section headers: SF Pro Display, semibold
- Body / labels: SF Pro Text, regular
- Stat numbers: SF Pro Rounded, bold

### Motion & Animation
- All transitions: `.easeInOut` with duration 0.25–0.35s
- Tab switches: `.slide` or custom matched geometry — smooth, no snapping
- Start/Pause button: subtle scale spring animation on tap (`.spring(response: 0.3, dampingFraction: 0.6)`)
- Timer digits: `.contentTransition(.numericText())` for smooth number rolling
- No excessive animations — restraint is the rule

### Spacing & Layout
- Base unit: 8pt grid
- Corner radii: 16pt for cards, 12pt for buttons
- Safe area awareness: always respect device safe areas
- Card-based layout for stats — soft shadows with low opacity

---

## Timer Logic (Critical Implementation Notes)

The Clock is modeled as `ClockSnapshot` (`Models/ClockSnapshot.swift`), a
plain `Codable` value shared by the app, the widget extension, and the Lock
Screen intents. See `CONTEXT.md` for the vocabulary (Clock, Clock Action,
Study Day, Rollover, Session) and `docs/adr/0001-shared-clock-with-last-action-wins.md`
for why it works this way. This replaces the pre-#9 design that stored raw
`dailyElapsed` / `totalElapsed` counters and checked a `lastResetDate`
boundary by hand in `TimerManager`.

**Shared app-group suite keys** (`TimerKey` in `Models/LSATTimerAttributes.swift`):

- `dailyElapsed` — Double (seconds), the current Study Day's banked time excluding any in-flight run (`ClockSnapshot.dailyBase`)
- `timerRunning` — Bool
- `timerStartedAt` — Date?, when the current run began
- `dailyGoal` — Double (seconds), default 14400 (4 hours)
- `studyDay` — Date, start-of-day of the Study Day the counters belong to (4am-anchored, not midnight)
- `lastActionAt` / `lastActionDevice` — the last Clock Action's timestamp and origin device, used for last-action-wins merges
- `deviceID` — this device's stable id
- `pendingSessions` — departing Study Days an intent rolled over but couldn't persist as a Session itself (no SwiftData in the intent process); the app drains this queue on next launch
- `pastTotal` — cached sum of every persisted Session, so the All-Time Total (`pastTotal + today's Clock time`) can be shown without opening SwiftData — see `docs/adr/0002-derived-all-time-totals.md`
- `appHeartbeat` — written by a running Mac app every minute and on every Clock Action, so a widget can tell a quit Mac app from one that's just idle

**There is deliberately no `totalElapsed` key.** The All-Time Total is always
derived, never stored as a running counter — see
`docs/adr/0002-derived-all-time-totals.md`. `totalElapsed` still appears in
two places on purpose and neither is a live suite key:
- `TimerKey.retired`, a list of keys a pre-refactor build wrote that nothing
  reads any more; the app clears them once on launch so a stale value can't
  be mistaken for truth.
- The `StatsBackup` JSON export/import **file field name** — renaming that
  would break every backup a user has already exported, so the field keeps
  its old name even though it is now populated from the derived total.

**On every app foreground** (`TimerManager.onForeground()`):
1. Reload the Clock State from the suite (another device may have changed it).
2. Roll over if the Study Day has passed its 4am boundary (`ClockSnapshot.rollover(now:)`, idempotent — safe even if another device already did it).
3. Reconcile against any pending Session a Lock Screen intent rolled over on the app's behalf while it wasn't running.

**On pause / background:** the run is always banked into `dailyBase` before
the snapshot is written — see `ClockSnapshot.bank(at:)` — so there is never a
window where the persisted state and the displayed time disagree.

**Background running:** the Clock is tracked by `runStartedAt`, not a live
`Timer`; elapsed time is computed from that timestamp whenever anything needs
to show or persist it.

---

## Live Activity Implementation Notes

- App Group identifier: `group.evan.lsattimer`
- Live Activity reads/writes shared `UserDefaults(suiteName: "group.evan.lsattimer")`
- `LSATTimerAttributes: ActivityAttributes` struct in `LSATTimerAttributes.swift` — must be in **both** the main app target and the widget extension target (use Xcode Target Membership)
- `ToggleTimerIntent: AppIntent` lives in the widget extension target (`LSATTimerWidget.swift`)
- Main app starts Live Activity via `Activity<LSATTimerAttributes>.request(...)` on timer start
- Main app updates state via `activity.update(...)` on resume/foreground; pause ends the activity with a 30-min grace dismissal (see above)
- Main app ends Live Activity via `activity.end(...)` on daily reset
- Progress bar = `dailyElapsed / dailyGoal` (clamped to 1.0)
- Default daily goal: 4 hours (14400 seconds), configurable via Settings stepper
- `NSSupportsLiveActivities` must be `YES` in the main app's `Info.plist`
- Live Activities **cannot be tested in Simulator** — require a physical device
- Dynamic Island support: compact (leading book icon + trailing timer), expanded (full view + progress bar + play/pause), minimal (book icon)

---

## Mac App

LSAT Tracker on macOS is a feature-identical twin of the iOS app minus the
Live Activity (macOS has no Lock Screen), built as a menu bar agent rather
than a Dock-first app. It shares the same Clock, the same `ClockSnapshot`
domain model, and the same App Group with iOS — see `docs/adr/0003-supabase-sync-transport.md`
for how the two devices agree on Clock state.

**Current status:** the project builds and runs on macOS today — the app,
iOS target, and widget extension all target `iphoneos iphonesimulator macosx`
(`MACOSX_DEPLOYMENT_TARGET = 15.0`+), and the plain App Group id
`group.evan.lsattimer` signs correctly on a sandboxed Mac build with no
team-prefixed form and no platform-keyed suite name needed (verified by
inspecting the signed `.app`/`.appex` entitlements, not just the source
files). What does **not** exist yet is Mac-specific UI or behavior: there is
no `Mac/` directory, no menu bar item, no dedicated window chrome, no
hotkeys, and no Notification Center or Control Center widget. Those are
in-flight tickets, not shipped features:

- **Menu bar agent + window** ([issue #10](https://github.com/IncoherentThoughts/LSAT-Tracker/issues/10)) — planned: `LSUIElement` activation-policy behavior (menu bar only, no Dock icon by default), a `MenuBarExtra` popover showing today's time, the all-time total, Start/Pause, and the Daily Goal bar, plus a single `Window` (420×780) reachable from the popover's "Open" link and from a Go menu (⌘1/⌘2/⌘3). A Mac-only rollover scheduler keeps the Study Day current while the app is never foregrounded (4am timer, wake-from-sleep, clock/time-zone change).
- **Global hotkeys + App Shortcuts** ([issue #11](https://github.com/IncoherentThoughts/LSAT-Tracker/issues/11)) — planned: one system-wide hotkey (⌥0 by default) to toggle the Clock without opening the app, plus Siri/Spotlight/Shortcuts actions for Start and Pause.
- **Notification Center + Control Center widgets** ([issue #12](https://github.com/IncoherentThoughts/LSAT-Tracker/issues/12)) — planned: a timeline widget (small/medium) reading the shared suite directly (no live `Timer` in a widget process), and a Control Center toggle. Both need `appHeartbeat` to detect a quit Mac app versus an idle one.
- **Cross-device sync** ([issue #13](https://github.com/IncoherentThoughts/LSAT-Tracker/issues/13)) — planned, see `docs/adr/0003-supabase-sync-transport.md`. Without it, the Mac and iPhone builds each track their own local Clock and Session history; they do not yet share state.

Until those land, treat any description of a running menu bar item, a Mac
window, a hotkey, or a Mac widget as the design, not the current build. Use
SwiftUI `#if os(macOS)` / `#if os(iOS)` conditionals for platform-specific
code, and keep all ActivityKit code behind `#if os(iOS)` — there is no Live
Activity equivalent on macOS.

---

## Data Model

```swift
// StudySession.swift
@Model
final class StudySession {
    var date: Date               // normalized to start of day (midnight)
    var duration: TimeInterval   // total seconds for that Study Day
    var isManualEdit: Bool       // true if the user manually edited this entry
    var updatedAt: Date          // last-write timestamp; resolves duplicates after a sync merge
    var needsUpload: Bool        // true until this row has reached the Account's server copy
}
```

- One `StudySession` per Study Day (see `CONTEXT.md`), not strictly a calendar day — the day boundary is 4am, not midnight.
- Every property is defaulted and there is no unique constraint on `date`: a merge can legitimately produce two records for the same day for a moment, and `StudyStore.dedupeSessions()` resolves them by `updatedAt` (later wins) rather than the write failing.
- Manual edits overwrite the day's entry and flag `isManualEdit = true`.
- `needsUpload` exists for the sync layer ([issue #13](https://github.com/IncoherentThoughts/LSAT-Tracker/issues/13)); today it is set on every local write and nothing yet clears it.
- Query by date range for all chart data.

---

## What NOT to Do

- Do not add a reset button to the main timer screen
- Do not use UIKit unless required for a specific system API
- Do not use third-party charting libraries — Swift Charts only
- Do not use pure white (`#FFFFFF`) as a flat background — use `eggshell` instead
- Do not use hardcoded hex values in view code — always reference `Theme.swift` palette names
- Do not add unnecessary onboarding screens, splash screens, or tooltips
- Do not make animations feel "app-store demo" flashy — subtle and purposeful only
- Do not store absolute file paths — use relative references
- Do not skip the double-confirmation on total timer reset under any circumstances
- Do not ship the `Examples/` folder in the app bundle
- Do not use WidgetKit `accessoryRectangular` — the correct feature is a Live Activity via ActivityKit

---

## Stretch Goals (Post-MVP)

- [ ] Apple Watch complication (mirrors Live Activity display)
- [x] Cross-device sync — decided as Supabase, not CloudKit; see `docs/adr/0003-supabase-sync-transport.md` and [issue #13](https://github.com/IncoherentThoughts/LSAT-Tracker/issues/13) (in flight)
- [ ] Daily study goal setting with notification reminder
- [ ] Export study data as CSV
- [x] macOS menu bar mini-timer — in flight, see [issue #10](https://github.com/IncoherentThoughts/LSAT-Tracker/issues/10)
- [ ] Siri Shortcut: "Start my LSAT timer" — tracked as part of [issue #11](https://github.com/IncoherentThoughts/LSAT-Tracker/issues/11)

---

## Development Checklist

- [ ] `Theme.swift` with all colors defined before any view work — added to **both** targets
- [ ] `TimerManager.swift` with full background-safe timer logic
- [ ] `LSATTimerAttributes.swift` added to both app and widget extension targets in Xcode
- [ ] `NSSupportsLiveActivities` = YES in main app Info.plist
- [ ] App Group `group.evan.lsattimer` configured in both targets (Signing & Capabilities)
- [ ] 4am reset logic tested across midnight boundary
- [ ] Live Activity appears on lock screen when timer starts (physical device required)
- [ ] Dynamic Island shows compact and expanded views correctly (iPhone 14 Pro+)
- [ ] Play/Pause from lock screen (ToggleTimerIntent) correctly toggles timer
- [ ] Double-confirmation flow for total reset tested
- [ ] Manual edit validation (future date warning, 0–23:59 range)
- [ ] Daily goal stepper in Settings updates Live Activity progress bar
- [ ] All animations reviewed on real hardware for smoothness
- [ ] Dark mode: verify color palette still works (adjust if needed)
- [ ] Accessibility: VoiceOver labels on timer and buttons

---

*Last updated: 2026-09-17 — documented the macOS port status, the ClockSnapshot-based storage keys and derived totals from #9, and linked the ADRs and glossary added for #14.*

---

## Design Context

### Users
Law school applicants self-studying for the LSAT — typically alone, often at a desk or library, in long focused sessions. The app is opened briefly to start or pause the timer, then set aside. The primary job-to-be-done is accurate passive tracking, not active engagement. Users return to the stats screen occasionally to feel a sense of progress over weeks of preparation.

### Brand Personality
**Three words: Minimal · Warm · Trustworthy**

The app should feel like a trusted, quiet companion — not a coach, not a game, not a dashboard. It does one job with total reliability and gets out of the way. The warm palette (eggshell, toffee brown, rosy copper) signals a human, academic quality rather than a cold productivity tool.

### Emotional Goals
The app should feel **invisible and frictionless** when in use. A user mid-session should barely register they opened it — tap, timer running, phone down. Nothing should demand attention or interrupt focus. Satisfaction comes from the numbers being there when you look, not from the app asking you to look.

### Aesthetic Direction
- **Light only** — always the warm eggshell background. Never adapts to system dark mode.
- Reference aesthetic (the Flow app in `Examples/`) shows a clean dark timer UI — this app takes the same structural minimalism but applies a warm, parchment-toned palette instead of cold black.
- Anti-reference: **Duolingo / gamified apps** — no streaks used as pressure, no badges, no reward animations, no level-ups. The streak stat exists as neutral data, not motivation infrastructure.
- No corporate SaaS feel (Toggl, Notion) — this is personal and quiet, not a productivity dashboard.

### Design Principles

1. **Silence is the feature.** When the timer is running, the interface should have nothing competing for attention. Animations are subtle and purposeful; nothing pulses, glows, or demands a glance.

2. **Warmth, never urgency.** Color, copy, and layout should never make a user feel behind, pressured, or guilty. Empty states are neutral. Progress bars fill quietly. No red warnings for low study time.

3. **Data as reflection, not motivation.** The Stats screen is a rearview mirror — it lets users see where they've been. Charts should feel calm and informative, not goal-pressure widgets.

4. **Trust through consistency.** The app never loses data, never resets unexpectedly, never surprises the user. Destructive actions require deliberate confirmation. This reliability is the core value proposition.

5. **One job per screen.** The Timer screen does one thing: track. Settings does one thing: configure. Stats does one thing: reflect. Nothing bleeds across. No upsells, tips, or cross-screen nudges.

*Last updated: 2026-03-14 — design context added via /teach-impeccable.*
