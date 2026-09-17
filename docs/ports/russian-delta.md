# Russian Tracker → LSAT Tracker: the port surface

Research for [#4](https://github.com/IncoherentThoughts/LSAT-Tracker/issues/4), part of the map [#3](https://github.com/IncoherentThoughts/LSAT-Tracker/issues/3).
This is the shared brief every execution ticket reads first.

Reference tree (read-only): `~/Desktop/Misc./Projects/Russian/Russian-Tracker`, commit-state as of 2026-09-17.
Its plan of record is `docs/plans/2026-09-05-mac-app-and-sync.md`; its decisions are `docs/adr/0001`–`0003`.
Every claim below was checked against the files themselves, not against the plan's prose.

Paths written `Russian: X` are relative to the Russian Tracker repo root; paths written bare are relative to this repo's root.
Inside each repo the app sources live under `Russian Tracker/` and `LSAT Tracker/` respectively, and the widget sources under `Russian Timer Widget/` and `LSAT Timer Widget/`.

Renames on the way across (map standing rule): `Russian`→`LSAT`, `russiantimer`→`lsattimer`, `russiantracker`→`lsattracker`. App group stays `group.evan.lsattimer`; bundle ids stay `com.evan.lsattracker(.widget)`.

## How to read the tables

- **Job** — one line, what the file is for.
- **Lands as** — the LSAT file it becomes. *(new)* = does not exist here yet; *(rewrite)* = an existing file is replaced or heavily edited; *(no change)* = our copy already matches after renaming.
- **Study-Type code to drop** — the exact declarations that disappear because this app tracks one undifferentiated stream.
- **Needs first** — what the file depends on that this repo does not have yet.
- **Widget-shared** — if the widget extension needs this code, which of the five `membershipExceptions` files it has to live in. The five are `Models/LSATTimerAttributes.swift`, `Models/ToggleTimerIntent.swift`, `Models/ClockSnapshot.swift`, `Theme.swift`, `Views/Shared/SharedWidgetViews.swift`. **Today this repo's pbxproj lists only three** (`Models/LSATTimerAttributes.swift`, `Models/ToggleTimerIntent.swift`, `Theme.swift`) — #6 adds the other two as stubs, and nothing outside those five may be referenced from widget code.

---

## 1. Models

| Russian file | Job | Lands as | Study-Type code to drop | Needs first | Widget-shared | Ticket |
|---|---|---|---|---|---|---|
| `Models/ClockSnapshot.swift` (265 ln) | The Clock State as a plain `Codable` value: derived figures, the Clock Actions (`start`/`pause`/`resetDaily`/`setManualDaily`/`setDailyGoal`/`bank`), idempotent `rollover(now:)`, `merged(local:remote:)`, suite read/write, `deviceID`, the `pendingSessions` queue | `Models/ClockSnapshot.swift` **(new)** | `var mode: StudyType`, `var dailyByType`, `daily(for:at:)`, `breakdown(at:)`, `setMode(_:at:device:)`, the `dailyByType` line in `bank`, the clamp loop in `setManualDaily`, the per-type fields of `DepartingDay`, the `StudyType.allCases` loops in `init(suite:)`/`write(to:)` | nothing (pure Foundation) — but it is the base of everything else | **itself** (one of the five) | #9 |
| `Models/StudySession.swift` (100 ln) | The `@Model` per-Study-Day record | `Models/StudySession.swift` **(rewrite)** — ours is 27 ln with no defaults, no `updatedAt`, no `needsUpload` | `grammarDuration`, `immersionDuration`, `outputDuration`/`ankiDuration` (and its rename comment), `duration(for:)`, `setDuration(_:for:)`, `breakdown`, `dominantType`, the per-type `init` parameters | SwiftData only. `needsUpload` is used by #13; add it in #9 so the schema settles once | no (SwiftData never enters the extension) | #9, `needsUpload` consumed by #13 |
| `Models/RussianTimerAttributes.swift` (132 ln) | App-group suite name, Live Activity idle timeout, the Darwin notification name, the `TimerKey` key catalogue, the `ActivityAttributes` + its `ContentState`, `ClockSnapshot.liveActivityState` | `Models/LSATTimerAttributes.swift` **(rewrite)** — ours is 30 ln and has no `TimerKey` at all | the whole `enum StudyType` block, `TimerKey.currentMode`, `TimerKey.daily(_:)`, `TimerKey.pastTotal(_:)`, `UserDefaults.studyMode`, `ContentState.mode`, the `mode:` argument in `liveActivityState` | `ClockSnapshot` (for the `liveActivityState` extension) | **itself** | #9 |
| `Models/ToggleTimerIntent.swift` (149 ln) | The intent the Live Activity / widget button fires: rollover → toggle → write suite → refresh Live Activity → Darwin-notify. Also the `ClockIntent` typealias and the shared `presentLiveActivity` / `notifyApp` helpers | `Models/ToggleTimerIntent.swift` **(rewrite)** — ours is 110 ln and still mutates raw suite keys | the whole `extension StudyType: AppEnum` and the whole `struct SetStudyModeIntent` (≈60 ln, the bottom half of the file) | `ClockSnapshot`; `#if os(iOS)` fencing of ActivityKit so it compiles for macOS | **itself** | #9 (rewrite), helpers made `internal` in #11 |
| `Models/AppShortcuts.swift` (102 ln) | `StartTimerIntent`, `PauseTimerIntent`, and the `AppShortcutsProvider` (Siri / Spotlight / Shortcuts) | `Models/AppShortcuts.swift` **(new)** | the fourth `AppShortcut` entry (`SetStudyModeIntent`, "Switch … to \(\.$mode)") — three actions remain, not four | `ClockSnapshot`; `presentLiveActivity`/`notifyApp` must be `internal`, not `private`, in `ToggleTimerIntent.swift` | **no** — app target only, deliberately outside the five | #11 |
| `Models/TimerManager.swift` (457 ln) | `@Observable` owner of the in-memory snapshot: display tick, foreground/background, Darwin-notification observer, `adopt(_:notify:)`, the Clock Actions the views call, past-total cache, widget/control reloads, macOS `appHeartbeat`, the whole Live Activity pipeline | `Models/TimerManager.swift` **(rewrite)** — ours is 460 ln built on `dailyElapsed`/`totalElapsed` suite keys and a `lastResetDate` boundary check; 485 diff lines after renaming, i.e. a replacement rather than an edit | `var mode`, `setMode(_:)`, `pastByType`, `computedDaily(for:)`, `computedTotal(for:)`, `currentDayBreakdown()`, `allTimeBreakdown()`, the `[StudyType: TimeInterval]` third argument of the `persistSession` closure, the per-type half of `setPastTotals` | `ClockSnapshot`, the rewritten `LSATTimerAttributes` (`TimerKey`), `StudyStore.refreshPastTotals`. `WidgetCenter`/`ControlCenter` reload calls land with #12; `onStateChanged` → `SyncClient` with #13 | no | #9 (core), #12 (heartbeat + reloads), #13 (`onStateChanged`) |
| `Models/StudyStore.swift` (466 ln) | SwiftData gateway: `upsertSession`, dedupe by `updatedAt`, derived past totals (ADR 0002), the sync hooks (`applyRemote`, `sessionsNeedingUpload`, `markUploaded`, `deleteSession`, `resetAllSessionsEverywhere`), backup export/import, and the stats helpers (streak, best day, daily average, heatmap data) | `Models/StudyStore.swift` **(rewrite)** — ours is 258 ln, still has `recalibrateTotalIfNeeded` and `deleteAllSessions` | the `breakdown:` parameter and `apply(_:to:total:)` on `upsertSession`; `grammar/immersion/ankiDuration` in `SessionBackup`; `dailyByType`/`totalByType` in `StatsBackup`; the per-type loop in `refreshPastTotals`; `rawKeyed`; the `"output"`-vs-`"anki"` legacy key fix-up in `applyBackup`; `dominantType` in the heatmap tuple | `ClockSnapshot` (`applyBackup` builds one); `SessionRow` for `applyRemote` arrives with #13 | no | #9 (core + ADR 0002), sync methods in #13 |
| `Models/SupabaseConfig.swift` (9 ln) | Project URL + publishable key | `Models/SupabaseConfig.swift` **(new)** — copy verbatim, same project `wnwquybkpmyaufwkjmqw` | none | nothing | no | #13 |
| `Models/SyncClient.swift` (507 ln) | `ClockRow`/`SessionRow` wire types, Supabase auth, `pull()`, `flush()` + retry, Realtime subscription on both tables, `statusText` | `Models/SyncClient.swift` **(new)** | `ClockRow.mode`, `daily_grammar`, `daily_immersion`, `daily_anki` and their mapping in `init(_:userID:)` / `snapshot`; `SessionRow.grammar/immersion/anki` and `SessionRow.breakdown` | `supabase-swift` SPM product (#6); tables `lsat_clock_state` / `lsat_sessions` (#8); `TimerKey.sync*` keys; `SessionSyncPlan` | no | #13 |
| `Models/SessionSyncPlan.swift` (115 ln) | Pure reconcile decision (`adoptRemote` / `deleteLocal` / `upload`) plus the `SyncDate` wire formatters | `Models/SessionSyncPlan.swift` **(new)** — portable verbatim | **none** — this file is already Study-Type-free | nothing (pure Foundation) | no | #13 |

**Table names.** Russian's tables are `public.clock_state` / `public.sessions`; ours are `lsat_clock_state` / `lsat_sessions` in the *same* project, so every `client.from("…")` string and every `postgresChange(table:)` string in `SyncClient.swift` changes.

## 2. App shell, Theme, Mac

| Russian file | Job | Lands as | Study-Type code to drop | Needs first | Widget-shared | Ticket |
|---|---|---|---|---|---|---|
| `Russian_TrackerApp.swift` (168 ln) | `@main`. Builds `AppServices` (container + timer + store + sync + the `persistSession`/`onStateChanged` wiring), the iOS `WindowGroup`, and — under `#if os(macOS)` — the `MenuBarExtra`, the single `Window` id `main`, `.defaultSize(420, 780)`, the Go menu (⌘1/⌘2/⌘3) and `CommandGroup(replacing: .newItem)` | `LSAT_TrackerApp.swift` **(rewrite)** — ours is 44 ln, wires the store inside `.modelContainer(for:)` | the `[StudyType:TimeInterval]` argument of the `persistSession` closure | `AppServices` needs `SyncClient` (#13); mac scenes need `AppDelegate`, `WindowNavigation`, `MenuBarPopoverView`, `MacRolloverScheduler` (#10); `Hotkeys.install(timer:)` (#11) | no | #9 → #10 → #11 → #13 (each adds a slice) |
| `Theme.swift` (89 ln) | Palette + `Color(hex:)` + typography helpers | `Theme.swift` — **no change needed**. Diffed after renaming: the *only* differences are `static let skyDeep` and the trailing `extension StudyType { var color }`, both of which are Study-Type artifacts | `skyDeep`, `extension StudyType { var color }` | nothing | **itself** (already in our `membershipExceptions`) | — |
| `Mac/AppDelegate.swift` (91 ln) | Menu-bar-agent behaviour: `.accessory` ↔ `.regular` activation policy, never quit on last window close, `applicationShouldHandleReopen`, `mainWindow` lookup by scene id `main` | `Mac/AppDelegate.swift` **(new)** | none | `LSUIElement` in the Info.plist for macOS (#6) | no | #10 |
| `Mac/MenuBarPopoverView.swift` (303 ln) | `MenuBarLabel` + `MenuBarLabelImage` (icon + ticking time drawn into one `NSImage`), and the popover: today's digits, all-time row, Start/Pause, goal bar, Open / Quit footer | `Mac/MenuBarPopoverView.swift` **(new)** | line 99: `StudyTypeDots(selected: timer.mode) { timer.setMode($0) }` — the popover's three-dot row | `MenuBarIcon` image set (#7); `GoalProgressBar` from the shared views file (#12 extracts it, or #10 extracts it early) | no (app target only — but it *reads* `GoalProgressBar`, which is widget-shared) | #10 |
| `Mac/MacRolloverScheduler.swift` (86 ln) | Keeps the Study Day current on a Mac that never foregrounds: 4am `Timer`, `NSWorkspace.didWakeNotification`, window-became-key, clock/time-zone change — all → `TimerManager.onForeground()` | `Mac/MacRolloverScheduler.swift` **(new)** | none | `ClockSnapshot.studyDayStart` / `boundary(after:)` (#9) | no | #10 |
| `Mac/WindowNavigation.swift` (30 ln) | `@Observable` selected tab shared between the Go menu and `MainTabView`; `Tab.menuTitle` | `Mac/WindowNavigation.swift` **(new)** | none | our `Tab` enum — identical in both repos | no | #10 |
| `Mac/Hotkeys.swift` (48 ln) | The `KeyboardShortcuts.Name`s and `Hotkeys.install(timer:)` | `Mac/Hotkeys.swift` **(new)** | `setGrammar` (⌥1), `setImmersion` (⌥2), `setAnki` (⌥3) and their three `onKeyDown` handlers. **One name survives**: `toggleClock`, default ⌥0, on `onKeyUp` | `KeyboardShortcuts` SPM product, macOS-only (#6) | no | #11 |

## 3. Views

| Russian file | Job | Lands as | Study-Type code to drop | Needs first | Widget-shared | Ticket |
|---|---|---|---|---|---|---|
| `Views/MainTabView.swift` (143 ln) | `Tab` enum, the three pages, the floating capsule tab bar | `Views/MainTabView.swift` **(rewrite, small)** — 53 diff lines, all of them the macOS branch | none | `WindowNavigation` (macOS) | no | #6 does the `.tabViewStyle(.page)` `#if os(iOS)` fix + the macOS `ZStack`; #10 adds the `WindowNavigation` binding |
| `Views/Timer/TimerView.swift` (235 ln) | The landing screen | `Views/Timer/TimerView.swift` **(rewrite, small)** — 14 diff lines | lines 104–110: the `StudyTypeDots(...)` block and its `.sensoryFeedback(.selection, trigger: timer.mode)`; restore the `.padding(.top, 22)` we already use | `timer.dailyGoal` (ours still reads the raw `"dailyGoal"` suite key) | no | #9 (goal via `TimerManager`) |
| `Views/Timer/StudyTypeDots.swift` (87 ln) | The three-dot switcher on the Timer screen | **does not port — delete the concept** | the entire file | — | — | — |
| `Views/Stats/StatsView.swift` (283 ln) | The stats screen | `Views/Stats/StatsView.swift` — **no change needed** for the port itself | `byType:` on `TotalRingChart`, `breakdown:` on `upsertSession`, and the whole `todayOverridden(_:)` heatmap patch — **our copy already lacks all three** | — | no | — (touched only if #13 changes `upsertSession`) |
| `Views/Stats/Charts/DailyBarChart.swift` (77 ln) | Last 7 days | **byte-identical after renaming** — no change | none | — | no | — |
| `Views/Stats/Charts/WeeklyLineChart.swift` (82 ln) | Rolling 8 weeks | **byte-identical after renaming** — no change | none | — | no | — |
| `Views/Stats/Charts/MonthlyHeatmap.swift` (125 ln) | Month grid | **do not port.** Russian's version tints by `dominantType`; ours is the intensity-only original, which is exactly the post-strip form | `dominantType` in the data tuple, `HeatmapCell.dominantType`, `tint`, the `tint:` parameter on `color(for:)` | — | no | — |
| `Views/Stats/Charts/TotalRingChart.swift` (126 ln) | All-time ring | **do not port.** Russian's version slices by study type; ours is the 0–50/50–100/100–200/200h+ bucket ring the spec asks for | `byType`, `Bucket.type`, the typed legend, `typedHours` | — | no | — |
| `Views/Settings/SettingsView.swift` (517 ln) | Settings page, goal stepper, the reset alerts (single + double), Advanced sheet, backup export/import | `Views/Settings/SettingsView.swift` **(rewrite)** — 243 diff lines, **none of them Study-Type**: the delta is the sync status row, `SyncSection()`, `#if os(macOS) KeyboardShortcutsSection()`, goal through `timer.setDailyGoal(hours:)` instead of the raw suite key, `store.resetAllSessionsEverywhere()` instead of `deleteAllSessions()`, the "every session on all your devices" second-confirmation copy, and the `withResetAlerts`/`withSheets`/`withBackupFlows` view decomposition | `TimerManager.setDailyGoal` + `studyDay` (#9); `SyncClient` (#13); `KeyboardShortcutsSection` (#11) | no | #9, #11, #13 |
| `Views/Settings/ManualEditView.swift` (82 ln) | Date picker + duration entry | `Views/Settings/ManualEditView.swift` **(rewrite, 3 lines)** — Russian dropped our `previousDuration:` argument because the snapshot handles the delta | none | `TimerManager.applyManualEdit(date:duration:)` losing its `previousDuration` parameter (#9) | no | #9 |
| `Views/Settings/SyncSection.swift` (111 ln) | The Account group: email, password, Sign in / Signed in / Sign out, error line | `Views/Settings/SyncSection.swift` **(new)** — portable verbatim | none | `SyncClient`; `SettingsGroupView`, `SettingsRow`, `SettingsDivider` already exist in our `SettingsView.swift` | no | #13 |
| `Views/Settings/KeyboardShortcutsSection.swift` (72 ln) | `KeyboardShortcuts.Recorder` rows, macOS only | `Views/Settings/KeyboardShortcutsSection.swift` **(new)** | three of the four rows (`Grammar` / `Immersion` / `Anki`); only the `Start / Pause` → `.toggleClock` row survives | `KeyboardShortcuts` SPM product (#6); `Mac/Hotkeys.swift` names | no | #11 |
| `Views/Shared/SharedWidgetViews.swift` (259 ln) | The views the Live Activity, the Mac popover and the timeline widget all use: `liveAnchor`, `fmtElapsed`, `AppIconView`, `WidgetPlayPauseButton`, `WidgetStudyTypeDots`, `TimerDigitsView`, `RussianProgressBarStyle`, `GoalProgressBar` | `Views/Shared/SharedWidgetViews.swift` **(new file, existing code)** — every one of these except the dots already lives inside our `LSAT Timer Widget/LSATTimerWidget.swift` (lines 11–224); the port is an *extraction*, not a rewrite | the whole `struct WidgetStudyTypeDots` | the file must be in the widget's `membershipExceptions` (#6 creates the stub) and `AppIconView` references image set `LSATAppIcon` (we have it) | **itself** | #12 (#10 needs `GoalProgressBar` from it) |

## 4. Widget extension

| Russian file | Job | Lands as | Study-Type code to drop | Needs first | Widget-shared | Ticket |
|---|---|---|---|---|---|---|
| `Russian Timer Widget/RussianTimerWidget.swift` (221 ln) | The Live Activity only: Lock Screen view + Dynamic Island (compact / expanded / minimal) | `LSAT Timer Widget/LSATTimerWidget.swift` **(rewrite)** — ours is 419 ln because it still contains the shared views; after the extraction it should be Live-Activity-only and wrapped in `#if os(iOS)` | the two `WidgetStudyTypeDots(selected: context.state.mode)` call sites (Lock Screen line 55, expanded line 171) | `Views/Shared/SharedWidgetViews.swift` in the extension target | consumes four of the five | #12 |
| `Russian Timer Widget/TimerWidget.swift` (369 ln) | The Notification Center / Home Screen timeline widget: `TimerEntry`, `TimerWidgetProvider` (suite-only, `.policy(.never)`, macOS stale-hint second entry keyed on `appHeartbeat`), small and medium layouts | `LSAT Timer Widget/TimerWidget.swift` **(new)** | `s.mode = …` in the two preview/placeholder entries; `WidgetStudyTypeDots(selected: entry.snapshot.mode)` in the medium layout (line 306) | `ClockSnapshot` + `TimerKey.pastTotal`/`appHeartbeat` in the extension target; widget extension must build for `macosx` (#6) | consumes `ClockSnapshot`, `Theme`, `SharedWidgetViews`, `ToggleTimerIntent` | #12 |
| `Russian Timer Widget/ControlWidget.swift` (120 ln) | Control Center tile: `ControlWidgetToggle` + its own `SetClockRunningIntent: SetValueIntent` (a control cannot use `ToggleTimerIntent`, which is not a `SetValueIntent`), gated `iOS 18.0, macOS 26.0` | `LSAT Timer Widget/ControlWidget.swift` **(new)** — portable nearly verbatim | none | `ClockSnapshot` in the extension target | consumes `ClockSnapshot`, `LSATTimerAttributes`, `Theme` | #12 |
| `Russian Timer Widget/WidgetBundle.swift` (15 ln) | `@main` bundle: timeline widget + `#if os(iOS)` Live Activity + availability-gated control | `LSAT Timer Widget/WidgetBundle.swift` **(rewrite)** — ours lists only `LSATTimerLiveActivity()` | none | the two new widgets | no | #12 |

## 5. Tests

| Russian file | Job | Lands as | Study-Type code to drop | Ticket |
|---|---|---|---|---|
| `Russian TrackerTests/ClockSnapshotTests.swift` (156 ln, 11 `@Test`) | Pure Clock State tests: 4am study-day start, pause banks the run, **mode switch splits a run**, later-action-wins, tie-breaks toward the rolled-forward state, rollover splits a running clock / is idempotent / keeps a post-boundary run, fresh install, manual-edit clamp, resetDaily keeps running | `LSAT TrackerTests/ClockSnapshotTests.swift` **(new)** | drop `modeSwitchSplitsARunWithoutJumpingTheDisplay`; `pauseBanksTheRunIntoTheActiveType` becomes "pause banks the run"; `manualEditClampsTypedBuckets` becomes a plain total assertion. 9 of 11 survive | #9 |
| `Russian TrackerTests/ClockSnapshotSuiteTests.swift` (47 ln, 3 `@Test`) | Suite round-trip, `lastResetDate` → `studyDay` migration, departing-day enqueue/drain | `LSAT TrackerTests/ClockSnapshotSuiteTests.swift` **(new)** — all three survive; the round-trip loses its `mode` assertion | #9 |
| `Russian TrackerTests/SessionSyncPlanTests.swift` (67 ln, 5 `@Test`) | The reconcile rules and the wire-date round trip | `LSAT TrackerTests/SessionSyncPlanTests.swift` **(new)** — verbatim, already Study-Type-free | #13 |
| `Russian TrackerTests/Russian_TrackerTests.swift` (16 ln) | Xcode's stub | ours already exists | — | — |

The migration test matters here: this app's installed data still uses `lastResetDate` (see §7), so `migratesLegacyLastResetDateIntoStudyDay` is the test that protects the real device history.

## 6. Non-Swift port surface

| Russian file | Job | Lands as | Notes | Ticket |
|---|---|---|---|---|
| `Russian Tracker/Russian Tracker.entitlements` | iOS app group | ours matches already (`group.evan.lsattimer`) | — | — |
| `Russian Tracker/Russian Tracker.macOS.entitlements` | sandbox + `files.user-selected.read-only` + `network.client` + app group | `LSAT Tracker/LSAT Tracker.macOS.entitlements` **(new)** | `network.client` is what lets Supabase reach the network; `user-selected.read-only` is what `fileImporter` needs | #6 |
| `Russian Timer WidgetExtension.entitlements` | widget app group | ours matches already | — | — |
| `Russian Timer WidgetExtension.macOS.entitlements` | sandbox + app group | `LSAT Timer WidgetExtension.macOS.entitlements` **(new)** | — | #6 |
| `Russian-Tracker-Info.plist` | `LSUIElement`, `NSSupportsLiveActivities`, widget extension point | `LSAT-Tracker-Info.plist` **(edit)** — ours has everything except `LSUIElement` | `LSUIElement` must apply on macOS only | #6 |
| `Russian Tracker.xcodeproj/project.pbxproj` | platforms, SDKROOT, deployment targets, entitlements paths, SPM refs (`sindresorhus/KeyboardShortcuts` with `platformFilters = (macos)`, `supabase/supabase-swift`), `membershipExceptions`, widget embed `platformFilters`, scheme test action | `LSAT Tracker.xcodeproj/project.pbxproj` | **only #6 may edit this file.** The change list is #5's deliverable, `docs/ports/pbxproj-delta.md` | #5 → #6 |
| `Russian Tracker/Assets.xcassets/MenuBarIcon.imageset` | menu bar glyph | `LSAT Tracker/Assets.xcassets/MenuBarIcon.imageset` **(new)** — we have no such image set | asset catalogs are already in the target, so no pbxproj edit | #7 |
| `Russian Tracker/Assets.xcassets/AppIcon.appiconset` | app icon incl. the ten `mac-*` renditions | extend ours | we already have `LSAT Timer Widget/Assets.xcassets/LSATAppIcon.imageset`, so `AppIconView` resolves today | #7 |
| `docs/supabase/001_sync.sql` | `clock_state` + `sessions`, RLS, `replica identity full`, realtime publication | `docs/supabase/001_lsat_sync.sql` **(new)** | drop `mode`, `daily_grammar`, `daily_immersion`, `daily_anki` from the clock table and `grammar`, `immersion`, `anki` from sessions; rename both tables `lsat_*` | #8 |
| `docs/supabase/002_rename_output_to_anki.sql` | one-off column rename | **does not port** | pure Study-Type history | — |
| `docs/adr/0001`–`0003` | shared clock / derived totals / Supabase transport | `docs/adr/0001`–`0003` **(new, rewritten)** | #14's instruction is to rewrite, not copy: the CloudKit detour is Russian Tracker's history, not ours | #14 |
| `docs/plans/2026-09-05-mac-app-and-sync.md` | Russian's plan of record | **does not port** — map #3 is our plan of record | — | #14 |
| `CONTEXT.md` | glossary | `CONTEXT.md` **(new)** | minus Study Type | #14 |

## 7. The storage-key delta (what actually changes under the app)

Russian's `TimerKey` catalogue, minus the Study-Type keys, is what this repo's suite has to become:

| Key | Status here today | After #9 |
|---|---|---|
| `dailyElapsed` | in use | kept (`ClockSnapshot.dailyBase`) |
| `timerRunning`, `timerStartedAt`, `dailyGoal` | in use | kept |
| `totalElapsed` | **in use** | **deleted** — all-time is derived (ADR 0002) |
| `lastResetDate` | **in use** | read once for migration, then superseded by `studyDay` |
| `studyDay`, `lastActionAt`, `lastActionDevice`, `deviceID`, `pendingSessions`, `pastTotal` (map calls it `pastSessionsTotal`), `appHeartbeat` | absent | added |
| `syncClockDirty`, `syncPendingDeleteAll`, `syncUploadedFor`, `syncLastPulledAt` | absent | added by #13 |
| `currentMode`, `daily_<type>`, `pastTotal_<type>` | absent | never added |

`TimerKey` lives in `Models/LSATTimerAttributes.swift`, which is widget-shared — the intents and the widget provider read these names too.

---

## Phase-by-phase ownership

Russian Tracker's phases map onto this map's tickets as follows. Phase 2 (CloudKit) is out of scope; Phase 6 was Russian's own verification/docs pass and splits across #14 and #15.

### Phase 0 — Project setup → **#6**, with **#5** as its input and **#7** alongside

Russian's five items were: the `.tabViewStyle(.page)` macOS compile fix, deployment targets and `SUPPORTED_PLATFORMS`, entitlements, the App Group question, and the `KeyboardShortcuts` SPM dependency. All five are #6's checklist, plus two things Russian did later and #6 does up front: the `supabase-swift` package and all five `membershipExceptions` entries pre-stubbed. **#5** produces the mechanical change list first; **#7** is the artwork half (mac icon renditions + `MenuBarIcon`) and is independent of everything.

The open question Russian also hit — whether a plain `group.evan.lsattimer` signs on a sandboxed Mac app or whether `3LYN963K9A.group.…` is required — is #6's to answer and the map's to record.

### Phase 1 — Domain refactor → **#9**

`ClockSnapshot`, defaulted `StudySession` with `updatedAt`, derived all-time totals (ADR 0002), `TimerManager` rebuilt around the snapshot with `adopt(_:notify:)`, the idempotent rollover, the intent rewrite, and the unit tests. Russian's Phase 1 also included `setMode` as a Clock Action and the CloudKit-driven "every field defaulted, no `@Attribute(.unique)`" constraints — the defaults are still worth keeping (they cost nothing and the sync merge relies on them), the `setMode` half is dropped.

This is the ticket that blocks everything behavioural: #10's popover, #12's widget provider and #13's wire rows all read `ClockSnapshot`.

### Phase 3 — Mac app shell → **#10**

`LSUIElement` + `AppDelegate` activation policy, `MenuBarExtra` with the popover, the single `Window` at 420×780 with the Go menu, `MacRolloverScheduler`, and the `fileExporter`/`fileImporter` swap. Note that Russian's Phase 3 item 5 (the exporter swap) was **left undone** there — our #10 explicitly picks it up. Russian's popover carried `StudyTypeDots`; ours does not.

### Phase 4 — Hotkeys and App Shortcuts → **#11**

`Mac/Hotkeys.swift`, `KeyboardShortcutsSection`, `AppShortcuts.swift`. Four shortcut names become one (⌥0 `toggleClock`); four App Shortcuts become three. Russian left `Hotkeys.install(timer:)` unwired — ours is wired in `LSAT_TrackerApp.init()` under `#if os(macOS)`, and `presentLiveActivity`/`notifyApp` must be `internal` for the new intents to share them.

### Phase 5 — Notification Center widget + Control Center → **#12**

The shared-views extraction, `TimerWidget.swift`, `ControlWidget.swift`, the `WidgetBundle` update, `#if os(iOS)` around the Live Activity, and `TimerManager`'s `appHeartbeat` + `reloadAllTimelines()`/`reloadAllControls()` calls. The `macosx` platform for the extension and its macOS entitlements come from #6, not from here.

### Phase 7 — Supabase transport → **#13**, with the schema in **#8**

`SupabaseConfig`, `SyncClient`, `SessionSyncPlan`, `StudySession.needsUpload`, the `StudyStore` sync methods, `SyncSection`, global-reset semantics and the backup-import `lastActionAt` stamp. **#8** owns the SQL and the by-hand application (the workspace's Supabase MCP connection reaches a different organization and cannot see project `wnwquybkpmyaufwkjmqw`). Phase 7 item 1 — "remove CloudKit" — has no counterpart here: this port never grows it.

### Phase 6 → **#14** (docs, ADRs, `CONTEXT.md`) and **#15** (the device checklist)

Russian's scenario checklist is reproduced almost line for line in #15, plus the Live Activity items from this repo's `CLAUDE.md` and the `activitykit-lifecycle-facts` memory.

---

## What this inventory changes about the plan

1. **Four files need no port at all.** `Theme.swift`, `DailyBarChart.swift`, `WeeklyLineChart.swift` and `StatsView.swift` are either byte-identical after renaming or differ only in Study-Type code. `TotalRingChart.swift` and `MonthlyHeatmap.swift` are the reverse case — **our** versions are the correct post-strip form and Russian's must *not* be copied over them.
2. **`Views/Shared/SharedWidgetViews.swift` is an extraction, not new code.** Lines 11–224 of our `LSAT Timer Widget/LSATTimerWidget.swift` already contain `liveAnchor`, `fmtElapsed`, `AppIconView`, `WidgetPlayPauseButton`, `TimerDigitsView`, the progress-bar style and `GoalProgressBar`. Moving them into the app target under `Views/Shared/` is what makes them reachable from the Mac popover.
3. **`GoalProgressBar` is needed by #10 but lives in #12's file.** Whoever lands first should create `Views/Shared/SharedWidgetViews.swift` for real; the other consumes it.
4. **Our `membershipExceptions` currently lists three files, not five.** #6 must add `Models/ClockSnapshot.swift` and `Views/Shared/SharedWidgetViews.swift` as stubs, or #9 and #12 will not compile for the extension.
5. **`SessionSyncPlan.swift` and `SupabaseConfig.swift` port verbatim** — no Study-Type content, no LSAT-specific logic beyond the table names in the client.
