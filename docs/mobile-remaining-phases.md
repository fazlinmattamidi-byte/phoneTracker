# PlateQ Mobile Conversion Remaining Phases

This tracker lists what is still required to finish the full conversion from the existing browser ANPR system to one native Flutter mobile application for Android and iPhone.

Browser-to-native function parity is audited in `docs/mobile-browser-parity-audit.md`.

Current state:

- Phase 1 is complete.
- Phase 2 project scaffolding is complete for Flutter source plus official `android/` and `ios/` folders. Android debug build and iOS simulator build are verified.
- Phase 3 is locally complete for the Flutter scaffold with BM/EN localization, language/theme controls, core screen parity, responsive phone/tablet navigation, native CSV import/export/share, analyzer validation, and Flutter tests.
- Phase 4 is locally complete with demo auth/session persistence, backend-ready API config, startup restore, native Android/iOS session channels, and native JSON app storage.
- Phase 5 Android native camera foundation is source-complete and Android build verified with CameraX preview and ImageAnalysis frame acquisition.
- Phase 6 iOS native camera foundation is source-complete with AVFoundation preview/output source and iOS simulator build verification.
- Phases 12-15 have Dart parity logic and scanner-event integration for validation, special-series probability, consensus, local repository matching, selected-camera restore, and local repository persistence.
- Phase 16 alert overlay, sound/haptic feedback, native evidence JPEG files, evidence metadata, persisted runtime special-series prefixes, and history writes are connected to scanner OCR/match events.
- Native per-track best evidence retention is implemented with quality/detector/size/stability scoring and cleanup when tracks are removed or replaced.
- Native evidence now writes raw vehicle/plate JPEGs plus enhanced, binary, top-line, bottom-line, and inner-text plate variants with crop dimensions and preprocessing metadata on Android/iOS OCR events.
- Flutter now verifies packaged required model assets, stages available assets to native filesystem paths before native initialize, and surfaces required/optional model readiness in scanner diagnostics.
- Android now includes ONNX Runtime Mobile with a release keep rule, guarded CPU session loading for staged detector/OCR/environment/quality models, live camera-frame YOLO detector inference from 640 letterboxed CameraX YUV tensors, Android PP-OCR inference from best plate crops, and multi-detection tracker fanout up to `maxTracks`; detector/OCR fallback scanning is disabled so failed model readiness is surfaced instead of producing dummy tracks or plates.
- Shared Dart YOLO output postprocessing is implemented and tested for YOLOv8-style tensors, 640 letterbox reverse mapping, confidence/objectness filtering, Malaysian plate-size/aspect filters, NMS, and multiple non-overlapping plate boxes.
- Shared Dart PP-OCR dictionary loading and greedy CTC decoding are implemented and tested against the packaged dictionary asset.
- Phase 17-18 runtime adaptation basics are implemented with LOW/MEDIUM/HIGH device tiers, adaptive analyzer stride, OCR concurrency caps, memory reporting, and thermal state reporting.
- Phase 20 local release-mode artifacts are buildable: Android release APK, Android release AAB, iOS simulator app, and unsigned iOS release app. Production signing/submission remains pending.
- Native detector/tracker/quality/environment intelligence is implemented for Android and iOS. Android live YOLO detector inference, iOS live YOLO detector inference, Android PP-OCR tensor inference, and iOS PP-OCR tensor inference now require real model output for detector/OCR events. Real-device camera/OCR validation is still required.

## Overall Remaining Phase List

| Phase | Name | Status | Main Dependencies | Done When |
| --- | --- | --- | --- | --- |
| 2 | Flutter project structure | Complete / simulator verified | Physical-device signing for real iPhone run | Flutter source, `android/`, and `ios/` exist; `flutter pub get`, `flutter analyze`, `flutter test`, Android debug APK build, and iOS simulator build pass. |
| 3 | Flutter UI parity | Locally complete / visual signoff pending | Visual QA against web screens | Flutter screen workflows exist with filters, paging, native CSV import/export/share, user drilldown, phone/tablet navigation, and tests passing. External signoff happens when visual parity screenshots pass on target devices. |
| 4 | Authentication/backend | Local/native complete / backend integration external | Production backend details | Local login/session restore/logout, hardened native session storage, native session channels, native JSON app storage, `PLATEQ_API_BASE_URL` backend config, and API client scaffold exist. Production sync completes when endpoint/schema is provided and wired. |
| 5 | Android CameraX layer | Local foundation complete / device signoff pending | Android real-device validation | CameraX preview, permission flow, camera list, lifecycle binding, ImageAnalysis frame acquisition, runtime frame metadata, native file picker, and Android build pass. External signoff requires real-device camera stability validation. |
| 6 | iOS AVFoundation layer | Local foundation complete / device signoff pending | Real iPhone signing and camera validation | AVFoundation preview/output source, permission flow, camera list, lifecycle hooks, runtime events, native file picker, iOS simulator build, and iOS simulator launch pass. External signoff requires real-device camera validation. |
| 7 | Native detector | Implemented locally / real-device validation pending | Real-device validation | Android/iOS now produce native frame-derived plate candidates with thresholds, normalized overlay coordinates, provider status, detector FPS, verified packaged `plate-detector.onnx`, staged native model paths, and tested shared YOLO postprocessing for tensor decode, letterbox reverse mapping, filters, and NMS. Android CameraX and iOS AVFoundation frames are preprocessed into 640 letterboxed tensors, run through CPU ONNX detector sessions, and feed only real model boxes into the native tracker. No synthetic fallback boxes are emitted when YOLO returns no detections. |
| 8 | Native tracker | Functional fallback complete | Detector events, frame timestamps | Android/iOS now keep per-track IDs, visible/lost/removed lifecycle, short prediction, confidence smoothing, track caps, and overlay payloads. Validation against real multi-vehicle clips remains. |
| 9 | Plate quality | Functional fallback complete / ONNX provider optional | Crop pipeline, optional quality ONNX model | Android/iOS now score brightness, contrast, glare, sharpness, size, detector confidence, and emit web-compatible quality classes. Quality ONNX provider remains optional because the browser also supports deterministic heuristic fallback. |
| 10 | Environment intelligence | Functional fallback complete / ONNX provider optional | Full-frame inference/stats | Android/iOS now classify day, good condition, low light, night, fog, glare, and backlight from frame stats and expose environment confidence/provider status without stopping scanning. Environment ONNX provider remains optional for broader class parity. |
| 11 | PP-OCR native recognizer | Implemented locally / real-device validation pending | Real crop/video fixtures | Android/iOS emit typed OCR events from stable tracks with raw/enhanced/binary/top-line/bottom-line/inner-text plate crop evidence, verified/staged PP-OCR model and dictionary assets, and shared Dart dictionary/greedy CTC decoding tests. Android and iOS load the staged OCR dictionary/session, preprocess best plate crops into PaddleOCR `1x3x48x320` tensors, run CPU ONNX inference, greedily decode CTC output, rank enhanced/inner/two-line/recovery/deskew candidates, and emit `CPU_ONNX_PP_OCR` only when OCR returns a real normalized plate. Production parity completes when both platforms pass real crop/video fixtures with benchmark/early-stop parity. |
| 12 | Malaysian validation | Scanner event path connected | OCR output, Dart/native bridge | Scanner OCR events now pass through Dart Malaysian normalization/validation before matching. Broader native fixture validation for all plate categories remains. |
| 13 | Special-series probability | Scanner event path connected | OCR confidence, character evidence | Scanner OCR events now pass through special-series correction with character confidences, and runtime prefixes can be managed in Settings with native persistence. Broader field fixtures remain. |
| 14 | Consensus | Scanner event path connected | Per-track OCR state | Flutter scanner now keeps per-track OCR votes, required vote counts, confidence gates, and alert cooldown state. |
| 15 | Database/API matching | Local repository connected and persisted / backend sync pending | Backend sync or local repository | Stabilized OCR consensus now evaluates exact, possible, no-case, closed/cleared, repeated-character omission, match reason, and cooldown behavior against the local vehicle repository. Vehicles, users, history, settings, selected camera, language/theme, and runtime special-series prefixes persist through native app storage. Production backend sync remains external. |
| 16 | Alerts and history | Local evidence/history path complete / field validation pending | Matching, evidence image files, storage/API | Confirmed exact/possible matches now show alert overlay, include vehicle/evidence metadata, write native vehicle/raw-plate/enhanced/binary/split/inner-text JPEG files, play sound/haptic feedback when enabled, and write persisted detection history notes with evidence paths. Production validation of crop accuracy on real camera footage remains. |
| 17 | Android optimization | Functional basics complete / long-run validation pending | Working Android scanner | Android now reports LOW/MEDIUM/HIGH tier, memory, thermal state, adaptive analyzer stride, and OCR concurrency caps. Long-run thermal/memory stability still needs real-device testing. |
| 18 | iOS optimization | Functional basics complete / long-run validation pending | Working iPhone scanner | iOS now reports LOW/MEDIUM/HIGH tier, memory class, thermal state, adaptive analyzer stride, and OCR concurrency caps. Long-run thermal/interruption stability still needs real iPhone testing. |
| 19 | Real device testing | Pending | Feature-complete scanner builds | Galaxy A52, Galaxy A54, Galaxy S22, iPhone 11, iPhone 13, and iPhone 15 Pro pass the field matrix. |
| 20 | Production testing/release builds | Local release artifacts built / signing pending | Real-device signoff, signing credentials | Android release `.apk`, Android release `.aab`, and unsigned iOS release app build locally. TestFlight/App Store archive and production-signed Android artifacts require signing credentials after real-device testing. |

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
12. History local persistence and backend sync.
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

## iOS ONNX Status

iOS now uses CocoaPods for `onnxruntime-objc` and bridges the official Objective-C runtime into Swift through `Runner-Bridging-Header.h`. The iOS scanner loads staged detector/OCR model paths, runs CPU ONNX YOLO detection, runs CPU ONNX PP-OCR from best evidence crops, emits provider/model status, and keeps the heuristic/fallback OCR safety path if a model or inference call fails.

Local verification completed:

1. `pod install`
2. `flutter build ios --debug --simulator`
3. `flutter run -d F3EB29F9-D625-4AA7-8057-87D999C0FF5B --no-resident`
4. `flutter build ios --release --no-codesign`

Remaining iOS work is external QA/signing: run on a physical iPhone with Apple Developer signing, validate real camera/OCR output, and archive/sign for TestFlight or App Store distribution.

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
