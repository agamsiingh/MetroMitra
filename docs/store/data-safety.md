# Play Console: Data safety and content answers

Answers match the app as built (no ads, no analytics SDK, no accounts). Re-check this file before any release that
adds ads, crash reporting or analytics.

## Data safety form
| Question | Answer |
|---|---|
| Does the app collect or share any required user data types? | **Yes, one:** the optional assistant question text (see below). Everything else: No. |
| Is all collected data encrypted in transit? | Yes (https only; cleartext is disabled in the manifest). |
| Can users ask for their data to be deleted? | No data is kept by us. Local data is removed on uninstall. |
| Location (approximate / precise) | **Not collected.** Used on the device only, never sent or stored. |
| Personal info, financial info, health, contacts, photos, audio, files | Not collected. |
| App activity / Messages: assistant question text | Collected **only if** the user asks the optional online assistant; sent to our proxy, purpose "App functionality", **not shared**, **not stored** by the proxy, optional. |
| Device or other IDs | Not collected. |
| Crash logs / diagnostics | Not collected (no crash SDK). |

If you would rather answer "No data collected" you must remove the online assistant from the build, because the
question text does leave the phone. The honest answer with the assistant on is the table above.

## App content
- **Privacy policy:** hosted copy of `privacy-policy.html` (public https URL).
- **Ads:** No ads.
- **App access:** all features available without login.
- **Target audience:** 13+ (general public, not designed for children).
- **Content rating questionnaire:** utility/reference app; no violence, no user-generated content, no gambling,
  no location sharing with others. Expected rating: Everyone.
- **News app / Government app / Health app / Financial features:** No. MetroMitra is **not** a government app and
  is not affiliated with DMRC (state this in the description).
- **Permissions:** `ACCESS_COARSE_LOCATION` / `ACCESS_FINE_LOCATION` (optional, runtime, foreground only),
  `INTERNET`, `ACCESS_NETWORK_STATE`. No background location, so no background-location declaration.
