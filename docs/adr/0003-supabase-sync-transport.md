---
status: accepted
date: 2026-09-05
---

# Supabase as the sync transport

## Context

[0001](0001-shared-clock-with-last-action-wins.md) settled the merge rule for
a Clock shared across devices; it does not say how one device learns about
another device's Clock Actions. This app needed to pick a transport when the
Mac port ([issue #3](https://github.com/IncoherentThoughts/LSAT-Tracker/issues/3))
made "two devices, one Clock" a real requirement for the first time.

Apple's own answer to this — CloudKit — needs the iCloud entitlement, and
Apple only signs that entitlement for a paid Apple Developer Program
membership. This project is signed by a personal team, and paying Apple for a
program membership was never on the table. That rules out every Apple-hosted
sync path at once: CloudKit, iCloud Drive, the iCloud key-value store, and
silent push, since all four sit behind the same entitlement.

**This is not a reversal of an earlier CloudKit decision.** Unlike Russian
Tracker — which built a working CloudKit sync layer and then removed it once
it hit this same signing-team wall — this app never had CloudKit code. The
domain layer (`ClockSnapshot`, `merged(local:remote:)`, the idempotent
Rollover, Session dedupe by `updatedAt`) was designed transport-agnostic from
the start specifically so the transport could be decided independently, and
by the time a transport was needed, the signing constraint was already known.
This port went straight to Supabase.

## Decision

- Transport is a Supabase project (Postgres + Realtime + Auth): the existing
  free-tier project `wnwquybkpmyaufwkjmqw`, shared with Russian Tracker but
  with this app's own tables, `lsat_clock_state` and `lsat_sessions`
  ([issue #8](https://github.com/IncoherentThoughts/LSAT-Tracker/issues/8)).
- Identity is an Account: an email and password, signed in once per device.
  The SDK keeps the refresh token in the Keychain and renews it silently, so
  signing in is a one-time setup step, not something the user repeats.
- `lsat_clock_state` holds one row per Account — the Clock State columns plus
  `last_action_at` / `last_action_device` — and `lsat_sessions` is keyed by
  (`user_id`, `date`) with an `updated_at` column, matching the Study Day: no
  separate session id, because there is at most one Session per Study Day per
  Account. Both tables sit behind row-level security keyed to the signed-in
  user and both are in the Realtime publication.
- Writes are optimistic and local-first: the app marks the Clock dirty and a
  Session `needsUpload`, then flushes; failures retry. On sign-in, foreground,
  wake, and reconnect, the app pulls and reconciles — later `updated_at` wins
  per Session, a Session missing remotely is deleted locally unless it is
  still waiting to upload, and the Clock goes through the [0001](0001-shared-clock-with-last-action-wins.md)
  merge.
- The first device to sign in uploads everything it has; a second device
  signing in later merges rather than overwrites.
- Reset Total, once sync lands, deletes the Account's Sessions server-side;
  other signed-in devices receive the deletions live (if connected) or on
  their next pull.

**Implementation status:** this is the accepted design for the sync layer.
The tables are specified in [issue #8](https://github.com/IncoherentThoughts/LSAT-Tracker/issues/8)
and the client (`SupabaseConfig`, `SyncClient`, `SessionSyncPlan`, the
`StudyStore` sync methods, the Settings sign-in UI) in
[issue #13](https://github.com/IncoherentThoughts/LSAT-Tracker/issues/13).
As of this writing neither has merged: there is no Supabase code in the repo
yet, `StudyStore.deleteAllSessions()` is still purely local, and Reset Total
only clears the signed-in device. Treat every sync-dependent claim in this
document as the plan, not the shipped behavior, until #13 lands.

## Considered and rejected

- **Firebase.** Equivalent shape to Supabase, a heavier SDK, no advantage for
  a single-user-per-Account app.
- **Local-network sync (Multipeer or similar).** No server to pay for or
  depend on, but both devices must be awake and on the same network at the
  same moment; a locked phone would simply miss a Mac action.
- **A shared secret instead of real accounts.** Avoids asking for an email,
  but a leaked shared secret is a leaked, unrotatable Clock — there is no way
  to revoke access to just one device.
- **CloudKit.** Ruled out before any code was written, for the signing-team
  reason above — see Context.

## Consequences

- No Apple entitlement is involved, so a personal-team build can sync.
- No push notification path: a device learns about another device's action
  either while its Realtime socket is open (app in the foreground) or on its
  next foreground pull. This is the same practical limit the Live Activity
  already accepts — see the Live Activity design note in `CLAUDE.md`.
- A free-tier Supabase project pauses after roughly a week of no traffic;
  daily use keeps it alive, and resuming it is one click in the dashboard.
  Accepted as a known limitation.
- The publishable key ships inside the app binary. That is what a publishable
  key is for; row-level security, not secrecy of the key, is what protects
  the data.
- Both devices are assumed to share a time zone for a Session's `date`
  column, matching the existing assumption that the 4am Study Day boundary is
  computed in local time.
- `com.apple.security.network.client` in the macOS entitlements is Supabase's
  outbound HTTPS, not a CloudKit leftover — dropping it would silently break
  macOS sync inside the sandbox.
