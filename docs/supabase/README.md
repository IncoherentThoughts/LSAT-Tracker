# Supabase migrations

These SQL files run against the shared Supabase project at
`https://wnwquybkpmyaufwkjmqw.supabase.co` — the **same** project and
`auth.users` account as Russian Tracker, but LSAT Tracker's own tables
(`lsat_clock_state`, `lsat_sessions`), so the two apps never see each other's
data.

There is no migration tooling wired up for this project. Files here are
applied **by hand**, once, by pasting them into the Supabase dashboard's SQL
editor (Project → SQL Editor → New query → paste → Run) and are numbered in
the order they were written, not run automatically by CI or the app.

The Supabase MCP connection available in this workspace reaches a different
organization and cannot see this project — do not attempt to apply these
migrations with MCP tools.

| File | Purpose |
|---|---|
| `001_lsat_sync.sql` | Creates `public.lsat_clock_state` and `public.lsat_sessions`, enables RLS with a single `auth.uid() = user_id` policy per table, and adds both to the `supabase_realtime` publication with `replica identity full`. |
