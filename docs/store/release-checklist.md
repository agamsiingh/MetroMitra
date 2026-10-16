# Release checklist (Google Play)

## Dataset status (2026-10-16)
The dataset now builds as stage `release`: the only release blocker was 72 stations + the operator without a Hindi
name; those were filled from Hindi Wikipedia article titles (cited per station in `data/curated/overlays.yaml`,
community-level source, not DMRC signage). Release builds bundle `app/assets/data/metro.sqlite`; `tools/check.dart`
refuses a bundled file that is not stage `release` or is test data. The "Draft data" banner is gone because the data
is no longer a draft. Gates, platforms, timings, facilities and fares are still absent from the dataset; the app
reports them as unknown rather than guessing.

Refresh the bundle before every release:
`dart run tools/data_pipeline/bin/build.dart build --offline --require-release` then copy
`build/pipeline/metro.sqlite` to `app/assets/data/metro.sqlite`.

## One-time set-up (done)
- Upload key created: `app/android/upload-keystore.jks` + `app/android/key.properties` (both git-ignored).
  **Back both up outside the repo now.** Losing them means you cannot update the app unless Play App Signing resets
  the upload key. Never commit or share them.
- Enrol the app in **Play App Signing** when creating it in Play Console (recommended; Google keeps the app key).

## Before the first upload
1. Rebuild and bundle the release dataset (above). Open items in `docs/known-issues.md` (Pink Line 46 vs 45, Dhaula
   Kuan walkway, DMRC map licence) are worth fixing first.
2. Spot-check Hindi names against station signage when possible (they come from Wikipedia).
3. Fill the placeholders in `privacy-policy.html` and host it (for example GitHub Pages) at a public https URL.
4. Create the app in Play Console; fill Data safety and App content from `data-safety.md`; paste `listing.md`.
5. Make the graphics listed in `listing.md`.
6. Decide Supabase: leave the app without `METROMITRA_SUPABASE_*` for a fully offline app, or pass the URL and
   publishable key at build time.
7. Bump `version:` in `app/pubspec.yaml` (build number must increase on every upload).
8. Build: `cd app && flutter build appbundle --release [--dart-define=...]`
   Output: `app/build/app/outputs/bundle/release/app-release.aab`.
9. Upload to **Internal testing** first, install from the Play link on a real phone, then promote.

## Personal accounts
New personal developer accounts must run a closed test with 12+ testers for 14 days before production access.
