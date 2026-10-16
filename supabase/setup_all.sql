-- MetroMitra admin backend (run once in the Supabase SQL editor).
-- Principles:
--  * Anyone can SIGN UP (an Auth setting), so being logged in means nothing:
--    every write requires a row in admin_users, checked by is_admin().
--  * The public app can only READ the published UI config and strings.
--  * Metro facts live in curated_* tables as DRAFT until an admin approves them;
--    only approved rows are exported to the data pipeline (signed dataset).
--  * Every change is written to audit_log by a trigger.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------- admins
create table if not exists public.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'editor' check (role in ('admin', 'editor')),
  created_at timestamptz not null default now()
);
alter table public.admin_users enable row level security;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admin_users where user_id = auth.uid());
$$;

create or replace function public.is_super_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admin_users
                 where user_id = auth.uid() and role = 'admin');
$$;

-- an admin sees their own row; only the 'admin' role manages the list
drop policy if exists admin_users_self on public.admin_users;
create policy admin_users_self on public.admin_users
  for select using (user_id = auth.uid() or public.is_super_admin());
drop policy if exists admin_users_manage on public.admin_users;
create policy admin_users_manage on public.admin_users
  for all using (public.is_super_admin()) with check (public.is_super_admin());

-- ---------------------------------------------------------------- UI config
-- key -> json value. The app reads ONLY keys it knows (allow-list in the app).
create table if not exists public.ui_config (
  key text primary key,
  value jsonb not null,
  note text,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);
create table if not exists public.ui_strings (
  key text not null,
  lang text not null check (lang in ('en', 'hi')),
  text text not null check (char_length(text) <= 500),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id),
  primary key (key, lang)
);

-- ---------------------------------------------------------------- curated data
-- Common provenance columns on every curated table:
--   source (where the fact comes from), verified_on (date), confidence,
--   status (draft -> approved), note. Unknown stays NULL; nothing is guessed.
create table if not exists public.curated_stations (
  id uuid primary key default gen_random_uuid(),
  station_id text not null unique,
  name_en text, name_hi text,
  aliases jsonb not null default '[]'::jsonb,   -- [{text, lang, kind}]
  lat double precision check (lat between -90 and 90),
  lng double precision check (lng between -180 and 180),
  source text, verified_on date,
  confidence text check (confidence in ('official','verified','derived','community')),
  status text not null default 'draft' check (status in ('draft','approved')),
  note text, updated_at timestamptz not null default now()
);
create table if not exists public.curated_gates (
  id uuid primary key default gen_random_uuid(),
  station_id text not null, gate_no text not null,
  name_en text, name_hi text, lat double precision, lng double precision,
  landmarks jsonb not null default '[]'::jsonb,  -- [{name_en,name_hi,walk_m}]
  step_free boolean,
  source text, verified_on date,
  confidence text check (confidence in ('official','verified','derived','community')),
  status text not null default 'draft' check (status in ('draft','approved')),
  note text, updated_at timestamptz not null default now(),
  unique (station_id, gate_no)
);
create table if not exists public.curated_platforms (
  id uuid primary key default gen_random_uuid(),
  station_id text not null, line_id text not null, platform_no text not null,
  towards_station_id text, service_id text,
  source text, verified_on date,
  confidence text check (confidence in ('official','verified','derived','community')),
  status text not null default 'draft' check (status in ('draft','approved')),
  note text, updated_at timestamptz not null default now()
);
create table if not exists public.curated_facilities (
  id uuid primary key default gen_random_uuid(),
  station_id text not null,
  facility_type text not null,  -- toilet, atm, lift, escalator, parking, ...
  present boolean,              -- NULL = unknown (never "no" by default)
  details jsonb not null default '{}'::jsonb,
  source text, verified_on date,
  confidence text check (confidence in ('official','verified','derived','community')),
  status text not null default 'draft' check (status in ('draft','approved')),
  note text, updated_at timestamptz not null default now()
);
create table if not exists public.curated_fares (
  id uuid primary key default gen_random_uuid(),
  fare_system text not null, from_km numeric, to_km numeric,
  fare_paise integer check (fare_paise >= 0),
  media text, day_type text, effective_from date, effective_to date,
  source text, verified_on date,
  confidence text check (confidence in ('official','verified','derived','community')),
  status text not null default 'draft' check (status in ('draft','approved')),
  note text, updated_at timestamptz not null default now()
);
create table if not exists public.curated_timings (
  id uuid primary key default gen_random_uuid(),
  station_id text not null, line_id text, towards_station_id text,
  day_type text, first_train time, last_train time, headway_s integer,
  source text, verified_on date,
  confidence text check (confidence in ('official','verified','derived','community')),
  status text not null default 'draft' check (status in ('draft','approved')),
  note text, updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------- audit
create table if not exists public.audit_log (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  by_user uuid default auth.uid(),
  table_name text not null, op text not null,
  row_pk text, old_row jsonb, new_row jsonb
);

create or replace function public.audit_trigger() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.audit_log(table_name, op, row_pk, old_row, new_row)
  values (tg_table_name, tg_op,
          coalesce((to_jsonb(new)->>'id'), (to_jsonb(new)->>'key'),
                   (to_jsonb(old)->>'id'), (to_jsonb(old)->>'key'),
                   (to_jsonb(new)->>'user_id'), (to_jsonb(old)->>'user_id')),
          case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) end,
          case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) end);
  return coalesce(new, old);
end $$;

create or replace function public.touch_row() returns trigger
language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['ui_config','ui_strings','curated_stations','curated_gates',
    'curated_platforms','curated_facilities','curated_fares','curated_timings','admin_users']
  loop
    execute format('drop trigger if exists audit_%1$s on public.%1$s', t);
    execute format('create trigger audit_%1$s after insert or update or delete on public.%1$s
                    for each row execute function public.audit_trigger()', t);
  end loop;
  foreach t in array array['ui_config','ui_strings','curated_stations','curated_gates',
    'curated_platforms','curated_facilities','curated_fares','curated_timings']
  loop
    execute format('drop trigger if exists touch_%1$s on public.%1$s', t);
    execute format('create trigger touch_%1$s before insert or update on public.%1$s
                    for each row execute function public.touch_row()', t);
  end loop;
end $$;

-- ---------------------------------------------------------------- RLS
alter table public.ui_config enable row level security;
alter table public.ui_strings enable row level security;
alter table public.audit_log enable row level security;
alter table public.curated_stations enable row level security;
alter table public.curated_gates enable row level security;
alter table public.curated_platforms enable row level security;
alter table public.curated_facilities enable row level security;
alter table public.curated_fares enable row level security;
alter table public.curated_timings enable row level security;

-- the app (anon) reads UI config and strings; only admins write
drop policy if exists ui_config_read on public.ui_config;
create policy ui_config_read on public.ui_config for select using (true);
drop policy if exists ui_config_write on public.ui_config;
create policy ui_config_write on public.ui_config for all
  using (public.is_admin()) with check (public.is_admin());
drop policy if exists ui_strings_read on public.ui_strings;
create policy ui_strings_read on public.ui_strings for select using (true);
drop policy if exists ui_strings_write on public.ui_strings;
create policy ui_strings_write on public.ui_strings for all
  using (public.is_admin()) with check (public.is_admin());

-- curated data and the audit log: admins only, read and write
do $$
declare t text;
begin
  foreach t in array array['curated_stations','curated_gates','curated_platforms',
    'curated_facilities','curated_fares','curated_timings']
  loop
    execute format('drop policy if exists %1$s_admin on public.%1$s', t);
    execute format('create policy %1$s_admin on public.%1$s for all
                    using (public.is_admin()) with check (public.is_admin())', t);
  end loop;
end $$;
drop policy if exists audit_read on public.audit_log;
create policy audit_read on public.audit_log for select using (public.is_admin());

-- ---------------------------------------------------------------- seed (built-in defaults, safe to re-run)
insert into public.ui_config(key, value, note)
select v.key, v.value::jsonb, v.note from (values
 ('announcement','{"enabled":false,"text_en":"","text_hi":"","severity":"info"}','Banner on Home'),
 ('flags','{"online_ai":true,"show_overview_map":true,"show_dmrc_map":true,"show_live_tracking":true,"show_map_search":true}','Feature switches'),
 ('theme','{"seed_color":""}','Brand colour, empty = built-in')
) as v(key, value, note) where not exists (select 1 from public.ui_config c where c.key = v.key);


-- ---------------------------------------------------------------- first admin (EDIT THE E-MAIL, then run the whole file)
-- The user must already exist: Authentication -> Users. Re-running is safe.
insert into public.admin_users(user_id, role)
select id, 'admin' from auth.users where email = 'agamcoder@gmail.com'
  and not exists (select 1 from public.admin_users a where a.user_id = auth.users.id);
update public.admin_users set role = 'admin'
 where user_id in (select id from auth.users where email = 'agamcoder@gmail.com');

-- check: should list your e-mail with role admin
select u.email, a.role from public.admin_users a join auth.users u on u.id = a.user_id;
