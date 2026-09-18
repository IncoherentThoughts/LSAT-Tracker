---
status: accepted
date: 2026-09-05
---

# The All-Time Total is derived from Sessions, never stored

## Context

Before [issue #9](https://github.com/IncoherentThoughts/LSAT-Tracker/issues/9),
the app kept a running counter, `totalElapsed`, in the shared `UserDefaults`
suite: every 4am Rollover added the departing day's seconds onto it. That
works when there is exactly one writer. It does not work once a Mac and an
iPhone can both roll over the same Clock without having seen each other's
Sessions yet — two devices each adding their own view of "today's seconds"
onto the same counter, then reconciling later, has no correct answer. The
counter cannot be merged the way `ClockSnapshot` can; it can only be
overwritten or double-counted.

## Decision

The All-Time Total is never stored as its own number. It is always computed
as `pastTotal + today's Clock time` (`TimerManager.computedTotal`, `Models/TimerManager.swift`):

- `pastTotal` is the sum of every persisted Session's `duration` — every
  Study Day that has already rolled over — recomputed by `StudyStore.refreshPastTotals()`
  after every write and cached in the app-group suite under `TimerKey.pastTotal`
  purely so the widgets and intents can show a total without opening SwiftData.
- Today's contribution comes straight from the live `ClockSnapshot`
  (`dailyBase` plus the in-flight run), the same value the daily timer shows.

Because the total is a sum over the Session history rather than a
tallied-as-you-go counter, two devices can each add or edit Sessions and the
total simply re-sums correctly the next time either one recomputes it. There
is nothing to merge and nothing that can drift out of sync with the history
it claims to summarize.

## Consequences

- `totalElapsed` is retired as a live suite key. It is deliberately not
  reused for anything: `TimerKey.retired` (`Models/LSATTimerAttributes.swift`)
  lists it alongside other pre-refactor keys, and the app clears it once on
  launch so a stale value under that name can never be mistaken for the
  derived total by anything that might still read it directly.
- `totalElapsed` **does** survive as a field name in `StatsBackup`
  (`Models/StudyStore.swift`) — the JSON export/import file format. That is
  deliberate and is a different thing from the suite key: the field still
  means "the All-Time Total at export time," it is just computed
  (`timer.computedTotal`) rather than read from a stored counter when the
  backup is written. Renaming that field would silently break every backup
  file a user has already exported, so the name stays even though the suite
  key it used to mirror is gone.
- Reset Total is "delete every Session and zero today's Clock" — it already
  meant roughly that before this change (it also cleared the counter), so the
  user-facing behavior is unchanged.
- A Manual Edit of a past day moves the total by exactly the size of the
  edit, because the edited Session is what gets summed — no separate
  adjustment step is needed.
- The Live Activity, the Mac menu bar popover (once built — see
  [issue #10](https://github.com/IncoherentThoughts/LSAT-Tracker/issues/10)),
  and the widgets (see [issue #12](https://github.com/IncoherentThoughts/LSAT-Tracker/issues/12))
  all read today's time from the Clock State and the total from the cached
  `pastTotal` sum; none of them need to touch a total counter directly.
