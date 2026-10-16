# Known issues

Open items only; history is in progress.md. Updated 2026-10-07 (after M11).

| Area | Issue | Owner / next step |
|---|---|---|
| Licensing | OPEN-2 (ODbL for the dataset) and OTD/DMRC permission unresolved | Owner decision; release blocker |
| Data | Dataset is `release` (2026-10-16) but still has no gates, platforms, timings, facilities, parking, fares; 72 Hindi names come from hi.wikipedia.org (not yet checked against signage); 14 name conflicts; travel-time parameters not approved (ADR-035) | Owner curation (`data/curated/`) |
| Updates | No update host and no production public key: `trustedPublicKeys` empty, `METROMITRA_UPDATE_URL` empty, so updates are off | Owner: host + `keygen` (private key in CI secrets only) |
| Online AI | No proxy deployed, no model key, `METROMITRA_AI_URL` empty | Owner: deploy `server/ai-proxy` behind TLS, set `AI_API_KEY` |
| Data | Pink Line: one station of Majlis Park - Maujpur is under construction per DMRC but unidentified; dataset shows all 8 as open | Owner: confirm which station, then curate |
| Data | Dhaula Kuan - Durgabai Deshmukh walkway interchange missing (no walk time source) | Owner: walk time from an official source |
| Data | Edge distances are straight-line (80-96 % of official line lengths); shown as estimates | Licensed inter-station distances |
| Licensing | `map/personal-dmrc-based/MetroMitra_Map.pdf` re-uses DMRC artwork under a MetroMitra title; must not ship in the app, store listing or marketing without DMRC permission | Owner |
| Licensing / UX | `assets/brand/dmrc_map.pdf` (DMRC artwork + MetroMitra title bar, bundled by the owner) is shown by the Map tab PDF button as "Official DMRC Map": needs DMRC permission before release; remove or replace before any Play build; label not localized; page takes ~1 min to render on the emulator; APK +~20 MB | Owner decision |
| Admin | `0001_admin.sql` not yet run on the Supabase project; no admin user; email sign-up is still open there; the owner shared the publishable key in chat (public by design, fine) - never share a secret/service-role key | Owner: follow docs/admin.md set-up |
| Admin | Edited gates/platforms/facilities/fares/timings cannot reach the app yet: the pipeline overlay loader rejects those sections (ADR-029) and the schema has no parking table | Pipeline + schema milestone |
| Admin | The admin web app is not hosted anywhere and has no browser end-to-end test (needs a real admin account) | Owner hosting; e2e after set-up |
| Station detail | Last row sits under the gesture bar (no bottom safe-area padding) | Layout fix |
| Stability | One ANR on an overloaded emulator, not reproduced | Investigate only if reproduced |
| Devices | No physical-device testing yet | Owner device |
| Hindi | Journey/assistant/AI strings are first drafts | Native review (M13) |
| Search | `search_perf_test` (p50 < 4 ms) is load-sensitive on this machine | Profile only if reproducible on a quiet machine |
| Branding | Logo resembles transport-authority roundels; app name/trademark unchecked (OPEN-4) | Owner decision, before store listing |
| Tooling | Stray 0-byte files appear in the repo, probably from the hook wrapper (`cmd /c` hook-handler) | Check the global Claude hook config |
