---
status: accepted
date: 2026-09-05
---

# One shared Clock, synced with last-action-wins

## Context

LSAT Tracker is gaining a Mac counterpart of the iPhone app (see the port map,
[issue #3](https://github.com/IncoherentThoughts/LSAT-Tracker/issues/3)), and
the two need to agree on whether the timer is running. Before this, the timer
was purely local: one device, one `UserDefaults` suite, no notion of another
copy of the app existing.

With two devices there is exactly one Clock per user — not one Clock per
device — and it needs a rule for what happens when both devices act on it
without having seen each other's most recent change (phone paused on the
subway with no signal, Mac resumed a minute later, etc).

## Decision

There is one Clock, represented as `ClockSnapshot` (`Models/ClockSnapshot.swift`).
Every change to it — start, pause, a Manual Edit, a Daily Goal change, Rollover
— is a Clock Action, and every Clock Action is stamped with `lastActionAt` and
`lastActionDevice`. When two Clock Actions arrive without either device having
seen the other, **the later timestamp wins outright**: `ClockSnapshot.merged(local:remote:)`
keeps whichever snapshot has the later `lastActionAt`, full stop — no
half-merge of individual fields.

The rule only works because every Clock Action banks the elapsed run first
(`ClockSnapshot.bank(at:)`): a `pause` or a `setManualDaily` folds the in-flight
seconds into `dailyBase` before it stamps the action. That means a losing
action can never make previously-counted minutes disappear — the most it can
do is lose credit for its own, very recent, decision.

The same last-action-wins rule resolves conflicting Sessions for one Study Day
(`StudySession.updatedAt`, most recent wins) and conflicting Manual Edits (a
Manual Edit is just a Clock Action like any other).

## Considered options

- **Per-device Clocks with merged history.** Rejected: two devices running
  their own Clock at once would double-count the same wall-clock minutes, and
  there is no overlap rule for a study timer that is intuitive to a user who
  just wants "the timer" to be one thing.
- **Prompting the user to resolve a conflict.** Rejected: a conflict prompt is
  a demand for attention, which is the one thing this app's design principles
  rule out (see "Silence is the feature" in `CLAUDE.md`).
- **Longest-run-wins.** Rejected: it rewards a Clock accidentally left running
  overnight on a device nobody is looking at, which is the opposite of what a
  user starting a fresh session on a different device wants.

## Consequences

- Rollover must be idempotent: whichever device first notices a stale Study
  Day performs it and writes the new Study Day back; a second device that
  rolls over independently produces the identical result, so it is safe for
  both to do it (`ClockSnapshot.rollover(now:)` is a pure function of the
  state and the wall clock and deliberately does not stamp `lastActionAt` —
  see the comment at the top of `ClockSnapshot.swift`).
- A reset (daily or total) is a Clock Action like any other and follows the
  same last-action-wins rule once sync lands — see
  [0003](0003-supabase-sync-transport.md) for what "everywhere" means for
  Reset Total.
- This ADR fixes the merge *rule*; it does not by itself say where the two
  snapshots being merged come from. That is [0003](0003-supabase-sync-transport.md).

## Status of the transport

This ADR originally also picked CloudKit as the sync transport. That decision
never shipped: the domain layer (`ClockSnapshot`, `merged(local:remote:)`, the
idempotent Rollover) was always written transport-agnostic, and by the time a
transport was needed, the answer was Supabase from the start — see
[0003](0003-supabase-sync-transport.md) for why. There is no CloudKit code in
this app's history to remove; unlike Russian Tracker, which built CloudKit
sync and later replaced it, this project never grew it. The Clock model and
last-action-wins rule described above are exactly what shipped and what
[0003](0003-supabase-sync-transport.md) transports.
