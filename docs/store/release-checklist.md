# Release checklist (Google Play)

## Why there is no upload-ready AAB yet
Release builds are **strict by design**: they load only a dataset whose stage is `release` (validated, not test data).
The current dataset is `draft` (unverified fares, gates, timings; 72 stations without Hindi names; Pink Line 46 vs 45
official; see `docs/known-issues.md`), and release builds ignore the draft switch. An AAB built today would open to
"Draft data not allowed" and could not be used. The "Draft data - not verified" banner is also deliberately kept: it is
the honest label for unverified data and is only shown while the data is a draft. It disappears by itself when a
`release` dataset is built from verified data. Removing it while the data is unverified would mislead riders.

## One-time set-up (done)
- Upload key created: `app/android/upload-keystore.jks` + `app/android/key.properties` (both git-ignored).
  **Back both up outside the repo now.** Losing them means you cannot update the app unless Play App Signing resets
  the upload key. Never commit or share them.
- Enrol the app in **Play App Signing** when creating it in Play Console (recommended; Google keeps the app key).

## Before the first upload
1. Verify the data and build a `release` dataset (`docs/metro-data-sources.md`, `docs/known-issues.md`).
2. Bundle it into `app/assets/data/` (the pipeline writes `metro.sqlite` + manifest).
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
