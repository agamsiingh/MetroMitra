# Manual device check (M5-M7)

Widget tests cannot show real rendering, permission dialogs or performance. Do this once on a phone or emulator
(debug build only; the dataset is **not** bundled).

## Run on a built draft dataset
1. `dart run tools/data_pipeline/bin/build.dart build --offline --out build/pipeline/check.sqlite --report build/pipeline/check-report.json`
2. Put the file where the app can read it (emulator: `adb push build/pipeline/check.sqlite /data/local/tmp/metro.sqlite`
   then pick a path the app can read, e.g. its files directory via `adb shell run-as <app id> ...`; on a desktop/web debug
   run any absolute path works).
3. `flutter run --dart-define=METROMITRA_DATASET=<path> --dart-define=METROMITRA_ALLOW_DRAFT=true`
   (use `METROMITRA_ALLOW_TEST_DATA=true` with `data/fixtures` output).
4. Open a screen directly: add `--dart-define=METROMITRA_START_ROUTE=/map` (also `/go/nearby`, `/station/<id>`,
   `/go/route/map?from=<id>&to=<id>`). Ignored in release builds.

## Checklist
- [ ] Boot: draft banner visible on Home, Picker, Results, Station, Nearby, Map.
- [ ] Picker: type in English and Hindi; rows readable at large font; tapping returns a station.
- [ ] Route results: alternatives, "About N min" + notice, change card at Maujpur-Babarpur explains the split.
- [ ] Station detail: opens from picker (i), Home field (i), results header/stops, Nearby, Map.
- [ ] Nearby: no prompt on Home; prompt only after "Use my location"; try Allow / Deny / Deny forever / location off;
      distances say "in a straight line"; airplane mode still works.
- [ ] Map: all stations and lines visible, line colours match the dataset, pinch/drag smooth (no jank on a mid-range phone),
      zoom buttons >= 48 dp, tap a station -> its detail, interchange markers distinct, labels appear when zooming in.
- [ ] Route map: ridden segments highlighted, other lines faded, changes ringed, walk link only when the route has one.
- [ ] Dark theme and Hindi locale on all of the above; rotate the phone on the map.
- [ ] Airplane mode: everything above except permission dialogs still works.
- [ ] Journey (M8): Start journey from results; every step's primary action; "I'm at…" sheet; "Use my location"
      (prompt only on tap); "Get off at the next stop" + vibration; screen stays on (and turns off when the switch is off
      or the journey ends); back asks "End journey?"; kill the app (`adb shell am kill` / swipe away) mid-ride and reopen:
      Home offers "Continue" at the same step.
Record findings in docs/progress.md (session log).

## Results
- **2026-10-07, emulator** (Android 16, x86_64, swiftshader, profile build, draft dataset): boot + draft banner, picker
  (English/Hindi rows, codes, interchange), route results, Journey mode end to end, process-death resume, GPS snap
  (test location provider), keep-awake flag, End dialog, Map tab: **pass** after the fixes listed in progress.md.
  Not yet checked: Nearby flow, Station detail, map gestures, dark theme, Hindi UI, a physical phone.
- Emulator tips: fresh AVD needs > 500 MB free for install; `adb emu geo fix` did not reach the GPS provider headless; use
  `adb shell appops set com.android.shell android:mock_location allow` + `cmd location providers add-test-provider gps`
  + `set-test-provider-location gps --location <lat>,<lng>`. In Git Bash set `MSYS_NO_PATHCONV=1` for adb paths.
