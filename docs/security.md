# Security & privacy

## Secrets
- **No secrets in the app.** Nothing in Dart source, `--dart-define`, assets or Gradle that grants
  paid/privileged access. LLM keys live only in the proxy.
- Public, non-secret identifiers allowed in config: AdMob app/unit IDs, proxy base URL,
  dataset signing **public** keys.
- `tools/check.dart` runs a secrets scan (adapted from Briskit `check_secrets.dart`):
  vendor key patterns (`sk-ant-`, `AIza`, `sk-`, private key PEM headers) fail the build.
- Release signing keystore and dataset signing key: CI secret store only; never committed.

## Data integrity
Datasets: Ed25519 signature + sha256 + schema check + validation before activation.
HTTPS only (`usesCleartextTraffic=false`). No dynamic code loading.

## Permissions (Android)
| Permission | Why | When |
|---|---|---|
| INTERNET, ACCESS_NETWORK_STATE | updates, AI, ads | install |
| ACCESS_COARSE_LOCATION + ACCESS_FINE_LOCATION | nearest station, journey snap | runtime, only on Nearby / "Use my location" / journey; approximate grant supported (shows "approximate") |
| WAKE_LOCK (via wakelock_plus) | keep screen on in journey | install |
| AD_ID | only if ads enabled; declared in Data safety | install |
Not requested: background location, storage, contacts, phone (station phone numbers use `tel:` intent, no CALL_PHONE), camera, notifications (V1).

## Location
Optional everywhere; on-device only; never logged or sent (AI exception requires explicit
per-question confirmation). Time out after 10 s → fallback UI. No background tracking.

## Privacy & Play Store
- No account, no personal data stored server-side.
- Data safety form: Location (approximate/precise) — collected? **No** (processed on device only);
  Crash logs/diagnostics — if Crashlytics enabled (OPEN-3); Device IDs — AdMob (ads, if not premium);
  AI questions — sent to our proxy, not stored beyond rate-limit counters (document retention).
- Google UMP consent form for ads; "Ads privacy" entry in Settings.
- Privacy policy URL hosted on the same static site; in-app link.
- Not designed for children (avoid Families policy obligations; set target audience 13+ / 18+ per ads).

## AI-specific
Prompt injection can only affect the text of an AI answer (no tool execution, no actions from
AI output, no links auto-opened). Input capped (500 chars). Answers rendered as plain text.
Proxy: rate limit, request size limit, no logging of question text by default.

## Supply chain
Pin dependency versions (lockfile committed); new packages need an ADR; `flutter pub outdated`
reviewed per release; R8/obfuscation on with symbol upload for crash de-obfuscation.

## Implemented in M6
Location is requested only from Nearby after a rationale screen (ADR-054); permissions are declared in the manifest, the position is memory-only. Verified by tests with a fake `LocationSource`; not yet exercised on a device.

## Implemented in M10-M11
Dataset updates verify Ed25519 + sha256 + schema + validation before activation, https only, public keys only in the app (none embedded yet; sync.md). Online AI goes only through our proxy (ai.md); the app sends no position, id or account, the proxy holds the model key in its environment, rate-limits, validates and does not log question text; generated text is post-checked on device and shown as plain text.
