-- LSAT Tracker sync schema. Runs in the SAME Supabase project as Russian Tracker
-- (https://wnwquybkpmyaufwkjmqw.supabase.co, shared auth.users), but its own
-- tables — the two apps never see each other's data. Modelled on Russian
-- Tracker's docs/supabase/001_sync.sql, minus the Study Type dimension: no
-- `mode` column, no per-type `daily_*` or session columns. Paste into the
-- Supabase SQL editor once; not applied by any migration tooling.

create table public.lsat_clock_state (
  user_id            uuid primary key references auth.users (id) on delete cascade,
  is_running         boolean          not null default false,
  run_started_at     timestamptz,
  study_day          timestamptz      not null default '1970-01-01',
  daily_base         double precision not null default 0,
  daily_goal         double precision not null default 14400,
  last_action_at     timestamptz      not null default '1970-01-01',
  last_action_device text             not null default '',
  updated_at         timestamptz      not null default now()
);

create table public.lsat_sessions (
  user_id        uuid             not null references auth.users (id) on delete cascade,
  date           date             not null,
  duration       double precision not null default 0,
  is_manual_edit boolean          not null default false,
  updated_at     timestamptz      not null default now(),
  primary key (user_id, date)
);

alter table public.lsat_clock_state enable row level security;
alter table public.lsat_sessions    enable row level security;

create policy "own clock" on public.lsat_clock_state
  for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "own sessions" on public.lsat_sessions
  for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Realtime: full old rows so a delete carries the Study Day. Table names are
-- lsat_-prefixed specifically so this does not clash with Russian Tracker's
-- clock_state / sessions already in the same publication.
alter table public.lsat_clock_state replica identity full;
alter table public.lsat_sessions    replica identity full;
alter publication supabase_realtime add table public.lsat_clock_state, public.lsat_sessions;
