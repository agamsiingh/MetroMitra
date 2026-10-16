# Sync & remote data updates

V1 has **no accounts and no user-data sync**. "Sync" means: pulling newer metro datasets
(including the map) without an app release, and verifying purchases with Play.

## Hosting (static, no server logic needed)
- Dataset releases on a CDN-backed static bucket (recommendation: Cloudflare R2 + Workers,
  which also hosts the AI proxy; alternative: GitHub Releases for data + Supabase Edge Function for AI).
- `https://<host>/v1/android/manifest.json` → latest dataset per channel (`stable`, `beta`).

## Manifest
```json
{
  "dataset_version": "2026.10.1",
  "schema_version": 1,
  "min_app_version": "1.0.0",
  "released_at": "2026-10-05T00:00:00Z",
  "url": "https://<host>/v1/datasets/2026.10.1/metro.sqlite.gz",
  "size": 1450000,
  "sha256": "<hex of decompressed file>",
  "signature": "<base64 Ed25519 over canonical manifest without signature>",
  "changelog": { "en": "2 new stations on ...", "hi": "..." }
}
```

## Update flow (app/shared/data/updater)
1. Foreground, ≤ 1/24 h, not during journey, respects Data Saver (skip on metered if size > 2 MB).
2. GET manifest (ETag/If-None-Match). Verify signature with the **public key embedded in app**.
3. Skip if version ≤ current, schema out of range, or `min_app_version` > app.
4. Download to temp → gunzip → sha256 check → open read-only → `metro_core` validation.
5. Move into `datasets/<version>/`, atomically rewrite `current.json`, keep previous one.
6. Invalidate `metroSnapshotProvider` (new snapshot loaded in isolate); recents keep working (IDs stable).
7. Show non-blocking "Metro data updated: <changelog>" once.
Rollback: on any load/validation failure → previous → bundled (offline.md).

## Signing
Ed25519 private key only in CI secret store; `tools/data_pipeline sign` runs in CI.
Key rotation: app embeds current + next public key.

## Live service updates (V2, not V1)
No official machine-readable feed found. If added: curated `notices.json` on the same CDN
(signed, short TTL), shown as a dismissible banner — never blocks routing.

## Purchases
Google Play Billing via `in_app_purchase`; entitlement cached locally; restore via Play.
Server-side receipt verification deferred (low fraud impact for a one-time ad-free unlock).

## Implemented in M10 (ADR-062)
- Core (pure Dart): `metro_core/src/update/update_manifest.dart` - strict `UpdateManifest.parse`, `ManifestVerifier` (Ed25519, keys embedded in the app, key_id match), `decideUpdate` (install / upToDate / older / schemaTooNew / schemaTooOld / needsNewerApp / notRelease), `Sha256Accumulator`, numeric `compareDottedVersions`. The pipeline's `sign` output verifies with it (cross test in `signing_test.dart`).
- App: `shared/data/updater/{update_transport,dataset_store,dataset_updater}.dart`, `bootstrap/update_providers.dart`.
  Flow: manifest (5 s connect / 15 s idle timeouts, https only, redirects checked by hand) -> parse -> **signature** -> decide (no download unless newer + compatible) -> download into `datasets/.staging/dl-<sha>.part` (resumes with `Range`, kept after a cut connection) -> gunzip + size + **sha256** against the signed manifest (a mismatch deletes the part) -> **validate** with the normal loader/policy and check the file's own `dataset_version`/`schema_version`/stage equal the manifest -> **install**: rename into `datasets/<version>/`, write `current.json` via temp + rename; any failure removes the new folder and keeps the old pointer. Active + previous are kept, the rest pruned.
- Launch order: dev override, active, previous, bundled. An installed dataset that fails to load is marked bad (never retried) and the pointer falls back.
- The new dataset is used from the **next launch** (not hot-swapped under a running route/journey). Check runs after the first frame, at most once per 24 h, not during a journey.
- Disabled by default: `METROMITRA_UPDATE_URL` is empty and `trustedPublicKeys` is empty, so a build can install nothing until the owner adds the production public key and host. Not done: data-saver/metered rule (no connectivity plugin), the "Metro data updated" notice and the "Update app" Settings line (M12 Settings), ETag.
