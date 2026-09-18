# LSAT Timer

A minimal, distraction-free timer for tracking daily and cumulative LSAT study time, on iOS and (in progress) macOS. Built for law school applicants self-studying for the LSAT who want a frictionless way to log hours without any gamification or pressure.

The domain concepts (Clock, Study Day, Session, Rollover, Account) are defined in `CONTEXT.md`. The architectural decisions behind the shared Clock, the derived all-time total, and cross-device sync are recorded in `docs/adr/`. The macOS port is tracked end-to-end as [issue #3](https://github.com/IncoherentThoughts/LSAT-Tracker/issues/3) on this repo.

---

## Features

### Timer
- **Daily timer** — large, centered display tracking today's study time. Resets automatically at 4:00 AM in the device's local timezone.
- **All-time total** — cumulative hours across all study sessions, displayed below the daily timer.
- Single tap to start/pause. No reset button on the main screen.
- Timer persists across app kills and background — tracked by start timestamp, not a live counter.
- Timer continues running while backgrounded; elapsed time is computed on return to foreground.

### Statistics
- **Last 7 Days** bar chart — today highlighted in accent color
- **Last 8 Weeks** area/line chart — rolling weekly totals
- **Monthly Heatmap** — GitHub-style grid colored by study intensity
- **All-Time Ring** — donut chart bucketing total hours (0–50h, 50–100h, 100–200h, 200h+)
- **Streak counter** — consecutive days with at least 1 minute of study
- **Daily average** — average per calendar day over the last 30 days
- **Best Day** — highest single-day session ever recorded

### Settings
- **Daily Goal** stepper (1–10 hours) — controls the Live Activity progress bar target
- **Reset Daily Timer** — single confirmation
- **Reset Total Timer** — double confirmation (cannot be undone)
- **Manual Day Edit** — pick any past date and set a custom duration (useful if you forgot to start the timer or left it running overnight)
- **Export Stats** — saves all sessions and timer state to a dated JSON file, shared via the system share sheet (Files, AirDrop, etc.)
- **Import Stats** — restores a previous export, with a preview of what's being restored before overwriting

### iOS Live Activity
- Appears on the Lock Screen and Dynamic Island automatically when the timer starts
- Shows live-counting elapsed time and a progress bar toward the daily goal
- Play/Pause button controls the timer directly from the Lock Screen (no app open required)
- Dynamic Island: compact, expanded (long-press), and minimal presentations
- Pausing ends the Live Activity (with a short grace period) rather than updating it in place, so a paused card is always cleaned up by the system even after a force-quit or reboot

### macOS (in progress)
LSAT Tracker is being ported to run natively on macOS as a menu bar app, sharing the same Clock as the iPhone app rather than being a separate build. As of this writing, the project **builds and runs on macOS**, but the Mac-specific UI is still landing piece by piece — see [issue #3](https://github.com/IncoherentThoughts/LSAT-Tracker/issues/3) for current status of each item below:

- **Menu bar agent** — lives in the menu bar (no Dock icon required); a popover shows today's time, the all-time total, Start/Pause, and the Daily Goal bar
- **Window** — a single 420×780 window reachable from the popover or a Go menu (⌘1/⌘2/⌘3)
- **Global hotkey** — toggle the Clock from anywhere on the Mac without opening the app
- **Notification Center and Control Center widgets** — Start/Pause without opening the app or the popover

### Cross-device sync (in progress)
Today, the iOS and (once shipped) macOS builds each keep their own local history. Sync — one Account, one Clock, shared across every signed-in device over Supabase — is designed in `docs/adr/0003-supabase-sync-transport.md` and tracked as [issue #13](https://github.com/IncoherentThoughts/LSAT-Tracker/issues/13). Once it lands, signing in is a one-time step per device (see Setup below); after that, starting, pausing, or editing a Study Day on one device is reflected on every other signed-in device.

---

## Tech Stack

| Layer | Choice |
|---|---|
| Language | Swift (latest stable) |
| UI | SwiftUI (100%) |
| Persistence | SwiftData (session history) + shared UserDefaults (Clock state) |
| Charts | Swift Charts (native, no third-party libraries) |
| Live Activity | ActivityKit + AppIntents (`ToggleTimerIntent`) — iOS only |
| Sync (in progress) | Supabase (Postgres + Realtime + Auth) — see `docs/adr/0003-supabase-sync-transport.md` |
| Minimum target | iOS 17.6+, macOS 15.0+ |

---

## Project Structure

```
LSAT Tracker/
├── LSAT_TrackerApp.swift          # App entry point, scene lifecycle hooks (macOS scenes land with #10)
├── Theme.swift                    # All color tokens (also in widget target)
├── Models/
│   ├── ClockSnapshot.swift        # The Clock State as a plain value: Clock Actions, Rollover, merge (also in widget target)
│   ├── LSATTimerAttributes.swift  # App-group suite name, TimerKey keys, ActivityKit attributes (also in widget target)
│   ├── ToggleTimerIntent.swift    # AppIntent behind the Live Activity's play/pause button (also in widget target)
│   ├── StudySession.swift         # @Model — one record per Study Day
│   ├── StudyStore.swift           # Business logic: stats, charts, backup/restore, derived totals
│   └── TimerManager.swift         # @Observable Clock state + Live Activity management
└── Views/
    ├── MainTabView.swift           # Root container + custom bottom nav bar
    ├── Timer/
    │   └── TimerView.swift         # Landing screen
    ├── Stats/
    │   ├── StatsView.swift
    │   └── Charts/
    │       ├── DailyBarChart.swift
    │       ├── WeeklyLineChart.swift
    │       ├── MonthlyHeatmap.swift
    │       └── TotalRingChart.swift
    ├── Settings/
    │   ├── SettingsView.swift
    │   └── ManualEditView.swift
    └── Shared/
        └── SharedWidgetViews.swift # Shared with the widget extension and the (in-progress) Mac popover

LSAT Timer Widget/
├── LSATTimerWidget.swift          # ActivityConfiguration + DynamicIsland (the Live Activity)
└── WidgetBundle.swift

docs/
└── adr/                            # Architecture decision records (Clock, derived totals, sync transport)

CONTEXT.md                          # Domain glossary
```

A Mac-specific `Mac/` directory (menu bar item, popover, window, hotkeys) does not exist in the tree yet — see [issue #10](https://github.com/IncoherentThoughts/LSAT-Tracker/issues/10).

---

## Setup

1. Clone the repo and open `LSAT Tracker.xcodeproj` in Xcode.
2. Set your development team in **Signing & Capabilities** for the `LSAT Tracker` and `LSAT Timer Widget` targets (both iOS and, once you're building for Mac, their macOS counterparts).
3. Verify the App Group `group.evan.lsattimer` is configured in **Signing & Capabilities** for all targets. This is a plain, non-team-prefixed App Group id, and it signs correctly on macOS as-is — no per-platform variant needed.
4. Build and run on a physical device for the full iOS experience (iOS 17.6+). The Live Activity cannot be tested in Simulator. The macOS target builds and runs today; its menu bar UI is still in progress (see macOS above).

> `NSSupportsLiveActivities` is already set to `YES` in the main app's `Info.plist`.

### Supabase sign-in (once cross-device sync lands)

Cross-device sync is designed but not yet shipped (see `docs/adr/0003-supabase-sync-transport.md` and [issue #13](https://github.com/IncoherentThoughts/LSAT-Tracker/issues/13)); this section describes the intended one-time setup once it does. There is no server to stand up yourself — the app ships pointed at the project's existing Supabase instance and its publishable key, the same way the rest of the app ships configured. The steps a user will follow:

1. Open **Settings → Account** and choose Sign In.
2. Enter an email and password. The first device to sign in on a given Account uploads all of its existing local history; every device signed in after that merges with what's already there rather than overwriting it.
3. The device stays signed in — the SDK keeps a refresh token in the Keychain and renews it silently, so this is a one-time step per device, not something done at every launch.
4. Once signed in, starting, pausing, or editing on one device is reflected on every other signed-in device the next time that device is in the foreground or has a live connection open.

No password or account details are ever entered anywhere except this one sign-in screen; there's no separate credential setup for macOS versus iOS.

---

## Key Implementation Notes

See `CONTEXT.md` for the vocabulary used below (Clock, Clock Action, Study Day, Rollover, Session) and `docs/adr/` for the reasoning behind each decision.

**Clock persistence** — The Clock is modeled as `ClockSnapshot`, a plain value stamped with a start timestamp (`timerStartedAt`) rather than elapsed seconds. On every app foreground, today's time is computed as banked time plus `(now − timerStartedAt)` for any in-flight run. This means the timer is accurate even after hours in the background, and — once sync lands — the same snapshot is what's compared across devices.

**4 AM Rollover** — On each foreground, `TimerManager` checks whether the current Study Day has passed its 4 AM boundary. If it has, the departing day's elapsed time becomes a Session, today's counter resets to 0, and (if the Clock was running across the boundary) the run is re-anchored to the boundary so the new day starts clean. Rollover is idempotent, so it's safe for more than one device to perform it independently.

**All-time total is derived, not stored** — There is no running "total" counter. The All-Time Total is always `(sum of every Session) + today's Clock time`, recomputed as Sessions change. See `docs/adr/0002-derived-all-time-totals.md`.

**Shared state (app ↔ widget)** — Both targets read/write the same `UserDefaults(suiteName: "group.evan.lsattimer")` suite. The `appGroupSuite` constant and the full `TimerKey` catalogue are defined in `LSATTimerAttributes.swift`, which is included in both Xcode targets.

**Live Activity toggle** — `ToggleTimerIntent` runs entirely in the widget extension process. It reads and writes directly to the shared UserDefaults suite and pushes an updated `ActivityContent` to the Live Activity, so the lock screen reflects the new state immediately without opening the app. Pausing from the Lock Screen ends the Live Activity (with a short grace period) rather than updating it in place, matching how pausing from inside the app behaves.

**Backup format** — Exports are plain JSON files containing all `StudySession` records plus `dailyElapsed`, `totalElapsed`, and `lastResetDate`. `totalElapsed` here is a *file field name*, not a live app setting — it's populated from the derived All-Time Total at export time, and the field keeps its old name so older exports keep decoding. Importing restores all sessions to SwiftData and writes the timer values back to UserDefaults, then calls `onForeground()` to rehydrate in-memory state (including re-running the Rollover check for cross-day restores).

---

## Color Palette

| Token | Hex | Usage |
|---|---|---|
| `eggshell` | `#F8F2DC` | App background |
| `toffeeBrown` | `#9E6240` | Primary text, icons, nav bar |
| `lightBronze` | `#DEA47E` | Secondary/muted labels, inactive elements |
| `rosyCopper` | `#CD4631` | Active states, progress bars, accent buttons |
| `skyReflection` | `#81ADC8` | Streak, best-day, achievement callouts |

All colors are defined in `Theme.swift` and referenced by name. No hardcoded hex values in view code.

---

## Stretch Goals

- [ ] Apple Watch complication mirroring the Live Activity
- [ ] Daily reminder notification
- [ ] Export study data as CSV
- [ ] Siri Shortcut: "Start my LSAT timer" — tracked as part of [issue #11](https://github.com/IncoherentThoughts/LSAT-Tracker/issues/11)

Cross-device sync and the macOS menu bar timer, formerly listed here, are no longer stretch goals — they're an active port. See [issue #3](https://github.com/IncoherentThoughts/LSAT-Tracker/issues/3) and the macOS / Cross-device sync sections above. iCloud/CloudKit sync was considered and rejected in favor of Supabase; see `docs/adr/0003-supabase-sync-transport.md`.
