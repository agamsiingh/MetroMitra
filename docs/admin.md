# Admin panel (Supabase)

Two parts, both small: a **web admin** (`admin/`, Next.js) and a **read-only settings fetch** in the app.
Backend = one Supabase project. SQL: `supabase/migrations/0001_admin.sql`.

## What the admin can change
| Area | Where | Reaches the phone |
|---|---|---|
| UI settings: announcement banner, feature switches (online AI, overview map, DMRC PDF, live location, map search), brand colour | `ui_config` | next app start with a connection; last good copy is kept offline |
| Text overrides (`homeHeading`, `askIntro`; en + hi) | `ui_strings` | same |
| Metro facts: station names/aliases/coordinates, gates, platforms, facilities/parking, fares, first/last train | `curated_*` | **only through the signed dataset**: approve -> export -> pipeline -> sign -> app update (M10) |

What it deliberately cannot do: change layouts or add screens (needs an app release; stores forbid downloading code),
or push a metro fact straight to phones. A fare typed into a text override is ignored (key allow-list in the app).

## Safety model
- **Sign-up is open on Supabase by default, so "logged in" means nothing.** Every write needs a row in `admin_users`
  (`is_admin()` in row-level security). Turn off "Allow new users to sign up" after creating your admin.
- The app and the admin use the **publishable key only** (public by design). A secret / service-role key is never used by the
  browser or the app: both refuse it, the secrets scan fails on `sb_secret_` and JWTs, and `npm run export` reads it from the
  environment of the machine running it (CI).
- Public (anon) role can **read** `ui_config` and `ui_strings` only. `curated_*`, `admin_users` and `audit_log` are admin-only.
- Facts need **provenance**: a row can be approved only with source, verified-on date and confidence; official/verified
  rows must name a source; unknown stays empty (a yes/no field has a third state "unknown", never stored as "no").
- Edits save as **draft**; export includes only approved rows with provenance and lists anything skipped.
- Every insert/update/delete on these tables is written to `audit_log` by a database trigger (who, when, before/after).
- The app validates what it reads (types, lengths, allowed keys, `#RRGGBB`), ignores the rest, uses HTTPS only,
  short timeouts and a size cap, saves only validated values, and keeps working offline with the last good copy.

## Set-up (once)
1. Supabase dashboard -> SQL editor: run `supabase/migrations/0001_admin.sql`.
2. Authentication -> Users: create your user. SQL editor:
   `insert into public.admin_users(user_id, role) select id, 'admin' from auth.users where email = 'YOUR-EMAIL';`
3. Authentication -> Providers -> Email: turn **off** "Allow new users to sign up".
4. `cd admin && npm install && npm run dev` (http://localhost:3100); `.env.local` holds the URL + publishable key
   (see `.env.example`; not committed).
5. App build: `--dart-define=METROMITRA_SUPABASE_URL=https://<project>.supabase.co --dart-define=METROMITRA_SUPABASE_KEY=sb_publishable_...`
   (empty = the app uses its built-in settings and never contacts Supabase).
6. Hosting the admin (Vercel, Netlify, own server): set the two `NEXT_PUBLIC_` variables there; put it behind HTTPS.

## Publishing facts
1. Admin: enter the fact, fill source + verified-on + confidence, set **approved**.
2. `cd admin && npm run export` (service key in the environment) writes `data/curated/admin-approved.json`
   (`metromitra-curated/1`, deterministic order).
3. `dart run tools/data_pipeline/bin/build.dart build --offline` picks that file up automatically
   (`--admin-export <file>` for another path). Station names, Hindi names, aliases and coordinates are applied
   after `overlays.yaml` (admin wins on the same field), listed in the build report's `overrides`, and change the
   curated provenance hash. A row without source/verified-on/confidence or with a bad value fails the build.
4. Phones get it with the next app release, or through a signed dataset update once an update host exists (M10).

Gates, platforms, facilities, fares and timings are exported but **not imported yet**: the build report lists them
under `inputs.admin-export.not_imported_yet`. They need the dataset/pipeline work reserved in ADR-029.

## Tests
`admin/tests` (14: validation, provenance rules, export filtering/determinism, UI-config validation), app
`remote_config_client_test` (client against a loopback server, parsing, secret refusal) and `remote_config_ui_test`
(banner, flags, text overrides, colour, fallback), `boundary_test` (network confined to the client).
