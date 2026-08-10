# PlateQ Mobile Conversion Remaining Phases

This tracker lists what is still required to finish the full conversion from the existing browser ANPR system to one native Flutter mobile application for Android and iPhone.

Current state:

- Phase 1 is complete.
- Phase 2 project scaffolding is complete for Flutter source plus official `android/` and `ios/` folders. Android debug build and iOS simulator build are verified.
- Phase 3 is locally complete for the Flutter scaffold with BM/EN localization, language/theme controls, core screen parity, responsive phone/tablet navigation, native CSV import/export/share, analyzer validation, and Flutter tests.
- Phase 4 is locally complete with demo auth/session persistence, backend-ready API config, startup restore, and native Android/iOS session channels.
- Phase 5 Android native camera foundation is source-complete and Android build verified with CameraX preview and ImageAnalysis frame acquisition.
- Phase 6 iOS native camera foundation is source-complete with AVFoundation preview/output source and iOS simulator build verification.
- Phases 12-15 have Dart parity logic started for validation, special-series probability, consensus, and matching.
- Native detector/tracker/quality/environment fallback intelligence is implemented for Android and iOS. Native ONNX Runtime model-provider parity and real-device camera validation are not complete.

## Overall Remaining Phase List

| Phase | Name | Status | Main Dependencies | Done When |
| --- | --- | --- | --- | --- |
| 2 | Flutter project structure | Complete / simulator verified | Physical-device signing for real iPhone run | Flutter source, `android/`, and `ios/` exist; `flutter pub get`, `flutter analyze`, `flutter test`, Android debug APK build, and iOS simulator build pass. |
| 3 | Flutter UI parity | Locally complete / visual signoff pending | Visual QA against web screens | Flutter screen workflows exist with filters, paging, native CSV import/export/share, user drilldown, phone/tablet navigation, and tests passing. External signoff happens when visual parity screenshots pass on target devices. |
| 4 | Authentication/backend | Local/native complete / backend integration external | Production backend details | Local login/session restore/logout, hardened native session storage, native session channels, `PLATEQ_API_BASE_URL` backend config, and API client scaffold exist. Production sync completes when endpoint/schema is provided and wired. |
| 5 | Android CameraX layer | Local foundation complete / device signoff pending | Android real-device validation | CameraX preview, permission flow, camera list, lifecycle binding, ImageAnalysis frame acquisition, runtime frame metadata, native file picker, and Android build pass. External signoff requires real-device camera stability validation. |
| 6 | iOS AVFoundation layer | Local foundation complete / device signoff pending | Real iPhone signing and camera validation | AVFoundation preview/output source, permission flow, camera list, lifecycle hooks, runtime events, native file picker, iOS simulator build, and iOS simulator launch pass. External signoff requires real-device camera validation. |
| 7 | Native detector | Functional fallback complete / ONNX provider pending | ONNX Runtime Mobile for model parity | Android/iOS now produce native frame-derived plate candidates with thresholds, normalized overlay coordinates, provider status, detector FPS, and fallback behavior. Full YOLOv8 parity completes when `plate-detector.onnx` runs through ONNX Runtime Mobile with NMS/preprocessing parity. |
| 8 | Native tracker | Functional fallback complete | Detector events, frame timestamps | Android/iOS now keep per-track IDs, visible/lost/removed lifecycle, short prediction, confidence smoothing, track caps, and overlay payloads. Validation against real multi-vehicle clips remains. |
| 9 | Plate quality | Functional fallback complete / ONNX provider optional | Crop pipeline, optional quality ONNX model | Android/iOS now score brightness, contrast, glare, sharpness, size, detector confidence, and emit web-compatible quality classes. Quality ONNX provider remains optional because the browser also supports deterministic heuristic fallback. |
| 10 | Environment intelligence | Functional fallback complete / ONNX provider optional | Full-frame inference/stats | Android/iOS now classify day, good condition, low light, night, fog, glare, and backlight from frame stats and expose environment confidence/provider status without stopping scanning. Environment ONNX provider remains optional for broader class parity. |
| 11 | PP-OCR native recognizer | Pending | ONNX Runtime Mobile, crop preprocessing | `ppocr-rec.onnx` and `ppocr-dict.txt` run locally with CTC decoding, two-line handling, preprocessing variants, confidence, and early stop behavior. |
| 12 | Malaysian validation | Started | OCR output, Dart/native bridge | Dart parity tests pass and native scanner uses the same validation for standard, Sabah, Sarawak, Putrajaya, Langkawi, EV, diplomatic, government, institutional, special, square, and two-line plates. |
| 13 | Special-series probability | Started | OCR confidence, character evidence | Runtime prefixes, edit distance, OCR confusion, numeric suffix scoring, protected standard plates, and examples like MALAYSIA/MADANI/GOLD/WWW/VIP/FF/QV work in scanner results. |
| 14 | Consensus | Started | Per-track OCR state | Per-track temporal votes, corrected vote promotion, confidence gates, and early exit match web behavior. |
| 15 | Database/API matching | Started | Backend sync or local repository | Exact, possible, no-case, closed/cleared, repeated-character omission, match reason, and cooldown behavior match existing business rules. |
| 16 | Alerts and history | Pending | Matching, evidence image files, storage/API | Every confirmed match shows plate, confidence, captured vehicle/plate image, vehicle info, timestamp, camera/device, match reason, sound/vibration, and writes history. |
| 17 | Android optimization | Pending | Working Android scanner | LOW/MEDIUM/HIGH tiers, CPU/hardware acceleration fallback, FPS adaptation, OCR concurrency, memory limits, thermal response, and long-run stability pass on Android. |
| 18 | iOS optimization | Pending | Working iPhone scanner | LOW/MEDIUM/HIGH tiers, CPU/hardware acceleration fallback, FPS adaptation, OCR concurrency, memory limits, thermal/interruption response, and long-run stability pass on iPhone. |
| 19 | Real device testing | Pending | Feature-complete scanner builds | Galaxy A52, Galaxy A54, Galaxy S22, iPhone 11, iPhone 13, and iPhone 15 Pro pass the field matrix. |
| 20 | Production testing/release builds | Pending | Real-device signoff, signing credentials | Internal `.apk`, Play `.aab`, TestFlight build, and App Store archive are produced after production testing. |

## Phase 2 Remaining Tasks

Completed:

- Installed Flutter 3.44.9 / Dart 3.12.2 with Homebrew.
- Generated official `android/` and `ios/` Flutter folders with `flutter create --platforms=android,ios .`.
- Verified `flutter pub get`.
- Verified `flutter analyze`.
- Verified `flutter test`.
- Installed Android command-line tools, accepted Android SDK licenses, and verified `flutter doctor` Android status.
- Verified Android debug build: `build/app/outputs/flutter-apk/app-debug.apk`.
- Installed and selected full Xcode.
- Installed iOS 26.5 simulator runtime and booted an iPhone 17 simulator.
- Verified `flutter doctor -v` reports no issues.
- Verified iOS simulator build: `build/ios/iphonesimulator/Runner.app`.
- Verified iOS simulator launch on iPhone 17 simulator.

Remaining:

1. Run a physical iPhone launch/camera smoke test after Apple signing/provisioning is configured.

## Phase 3 Remaining Tasks

Local code tasks are complete for the Phase 3 scaffold. External/manual signoff remains:

1. Compare Flutter login screen against `src/app/login/page.tsx`.
2. Compare dashboard against `src/app/page.tsx`.
3. Compare scanner controls and alert layout against `src/app/scanner/page.tsx`.
4. Review Android/iOS screenshots on target devices before retiring browser UI.

## Native Scanner Implementation Order

Implement native scanner work in this order to reduce risk:

1. Camera preview only.
2. Frame acquisition and orientation metadata.
3. Static-image YOLO inference.
4. Live YOLO inference without tracking.
5. Tracker and overlay rendering.
6. Evidence buffers and best frame.
7. Plate quality gate.
8. PP-OCR on captured best crops.
9. Malaysian validation and special-series correction.
10. Consensus and database matching.
11. Alert with evidence image.
12. History persistence/sync.
13. Thermal, memory, and device-tier adaptation.

## Real-World Test Matrix Still Required

| Scenario | Required Result |
| --- | --- |
| Parked cars | Stable detection, evidence, OCR, match/history. |
| Slow cars | Stable track, no duplicate alerts beyond cooldown. |
| Fast cars | Evidence captured even if vehicle disappears. |
| Multiple cars | Independent tracks, buffers, OCR, consensus, matching, alerts. |
| Motorcycles | Small/two-line/square handling preserved. |
| Night/low light | Environment adaptation and OCR variants activate. |
| Rain/fog/tunnel | Adaptive thresholds and preprocessing preserve scanning. |
| Glare/headlights/backlight | Quality gate and preprocessing avoid unnecessary rejection. |
| Special/fancy plates | Special-series probability handles OCR confusion safely. |
| Partially blocked plates | Low-confidence handling does not create false exact matches. |
| Camera interruption | Safe stop/reconnect/resume without crash. |
| 30/60/120 minute scans | No memory leak or thermal crash. |

## Browser Code Removal Rule

The browser implementation can only be removed after all of these are true:

1. Flutter UI parity has been reviewed.
2. Android scanner pipeline is complete.
3. iOS scanner pipeline is complete.
4. Native detector/OCR outputs pass validation against shared test fixtures.
5. Alerts always include evidence images.
6. History and database sync are verified.
7. Requested Android and iPhone devices pass real-world tests.
8. Release artifacts are generated successfully.
