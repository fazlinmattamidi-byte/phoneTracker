# PlateQ Native Mobile Migration Map

Status: Phase 1 is complete, Phase 2 is scaffolded and Android/iOS-simulator verified, and Phase 3-6 are locally complete for their current scaffold/native-foundation scope. The existing Next.js browser ANPR application remains the source of truth until each native replacement is field-verified on Android and iPhone.

Detailed remaining conversion work is tracked in `docs/mobile-remaining-phases.md`.

The current Phase 1-3 focus checklist is tracked in `docs/mobile-phase-1-3-checklist.md`.

The current Phase 4-6 focus checklist is tracked in `docs/mobile-phase-4-6-checklist.md`.

## Migration Rule

This repository is being converted from the existing browser ANPR implementation into one Flutter native mobile application. The web implementation is not a second product; it is the reference implementation that must be retired only after native equivalents are working.

Do not remove browser-specific code until the corresponding Flutter, Kotlin, and Swift behavior has been implemented and validated.

## Current Web Source Of Truth

| Product Area | Web Implementation | Mobile Implementation Target | Migration Status |
| --- | --- | --- | --- |
| App shell and layout | `src/app/layout.tsx`, `src/app/providers.tsx`, `src/components/layout/Sidebar.tsx`, `src/components/layout/BottomNav.tsx`, `src/components/layout/TopHeader.tsx` | Flutter `MaterialApp` shell with the same dashboard, scanner, search, history, vehicles, users, settings, and profile navigation. Mobile bottom nav remains primary on phones. | Scaffolded in Flutter source. Needs visual parity pass. |
| Login and authentication | `src/app/login/page.tsx`, `src/context/AuthContext.tsx` | Flutter auth state with the same demo role workflow until backend auth is wired. Preserve `SUPER_ADMIN`, `ADMIN`, `USER`. | Local/native complete with startup restore, login/logout audit, secure native session storage, and backend-ready API config. Production endpoint details pending. |
| Role permissions | `src/lib/permissions.ts`, `src/__tests__/permissions.test.ts` | Shared Dart permission helpers with the same rules: admin roles can edit/manage users/manage vehicles; only super admin can manage system. | Scaffolded with Flutter tests passing. |
| Dashboard | `src/app/page.tsx`, `src/components/dashboard/StatCard.tsx` | Flutter dashboard using same metric groups and quick navigation semantics. | Scaffolded. Needs full visual parity. |
| Scanner UI | `src/app/scanner/page.tsx`, `src/components/scanner/ModelStatusBanner.tsx` | Flutter scanner screen preserving current visual hierarchy: camera surface, start/stop, camera chooser, runtime health, latest alert, seen plates, developer/dataset controls where permission-gated. | Scaffolded around native bridge. Full pipeline pending. |
| Browser camera | `src/lib/anpr/cameraManager.ts`, scanner page media streams | Android CameraX in Kotlin and iOS AVFoundation in Swift, surfaced through Flutter platform views and event channels. | Android CameraX preview/ImageAnalysis source builds. iOS AVFoundation preview/output source builds for simulator. Real-device camera validation pending. |
| YOLOv8 detector | `src/lib/anpr/yoloDetector.ts`, `public/models/plate-detector.onnx` | ONNX Runtime Mobile detector using the same model, preprocessing, NMS, confidence thresholds, coordinate transforms, orientation fallback, and Malaysian plate box behavior. | Android/iOS native heuristic detector fallback implemented with normalized candidate boxes and thresholds. ONNX Runtime provider parity remains. |
| ONNX runtime setup | `src/lib/anpr/onnxRuntime.ts`, `public/ort-wasm/*` | Android `onnxruntime-android`; iOS `onnxruntime-objc`/mobile package. Hardware acceleration must be capability-gated with CPU fallback. | Pending. |
| PP-OCR | `src/lib/anpr/ppOcrEngine.ts`, `src/lib/anpr/ocrEngine.ts`, `public/models/ppocr-rec.onnx`, `public/models/ppocr-dict.txt` | Native PP-OCR recognizer preserving CTC decoding, dictionary, two-line handling, candidate generation, confidence, and preprocessing variants. | Contract defined. Native implementation pending. |
| Tracker | `src/lib/anpr/tracker.ts`, `src/__tests__/tracker.fat.test.ts` | Native Kotlin/Swift equivalent of ByteTrack-inspired lifecycle: visible/lost/removed, short prediction, no ghost boxes, independent tracks. | Android/iOS native track lifecycle implemented for detector fallback events. Existing TS remains reference for clip-level parity. |
| Evidence buffer | `src/lib/anpr/vehicleEvidenceBuffer.ts` | Native per-track evidence buffers for vehicle context and plate crops, with best sample retained even after a vehicle disappears. | Contract defined. Native implementation pending. |
| Best frame selector | `src/lib/anpr/bestFrameSelector.ts` | Native best-frame scoring using quality, sharpness, detector confidence, track stability, perspective, and recency. | Pending. |
| Image processing | `src/lib/anpr/imageProcessor.ts` | Native pixel-buffer processing, crop/deskew/perspective correction, adaptive variants, two-line split, inner text crop. | Pending. |
| Plate quality | `src/lib/anpr/plateQualityService.ts`, `src/lib/anpr/plateQualityScoring.ts`, `src/lib/anpr/qualityAssessor.ts`, `src/lib/anpr/plateQualityModel.ts` | Native quality scoring/model preserving accepted and marginal classes, sharpness, blur, size, contrast, glare, brightness, perspective, and fallback heuristics. | Android/iOS native quality heuristic implemented with web-compatible classes. Optional ONNX provider remains. |
| Environment intelligence | `src/lib/anpr/environmentIntelligence.ts`, `src/lib/anpr/adaptiveConfig.ts`, `public/models/environment-classifier.onnx` | Native scene classifier/fallback heuristics that adapt detector cadence, buffers, OCR variants, quality gates, and track timeouts. | Android/iOS native frame-stat environment heuristic implemented and exposed in runtime events. Optional ONNX provider remains. |
| Malaysian validation | `src/lib/anpr/patterns.ts`, `src/lib/anpr/normaliser.ts`, `src/__tests__/anpr.test.ts` | Dart or native shared validation preserving standard, Sabah, Sarawak, Putrajaya, Langkawi, EV, motorcycle, commercial, government, institutional, diplomatic, square, two-line, and unusual layouts. | Dart parity port started in `lib/src/anpr/normaliser.dart` and `lib/src/anpr/malaysian_patterns.dart`. Native integration pending. |
| Special-series probability | `src/lib/anpr/specialSeries.ts` | Dart/native equivalent preserving default prefixes, runtime prefixes, edit distance, OCR confusion maps, suffix quality, and protected standard plate behavior. | Dart parity port started in `lib/src/anpr/special_series.dart`. Native integration pending. |
| Consensus | `src/lib/anpr/consensus.ts` | Per-track temporal consensus preserving votes, promotion, corrected OCR votes, confidence thresholds, and early exit. | Dart parity port started in `lib/src/anpr/consensus.dart`. Native integration pending. |
| Matching engine | `src/lib/anpr/matchingEngine.ts`, `src/lib/db/repository.ts` | Flutter repository/API client using exact, possible, repeated-character omission, closed-case, and confidence behavior unchanged. | Dart parity port started in `lib/src/anpr/matching_engine.dart` and wired into search. Backend/API sync pending. |
| Alerts | Scanner page alert card, `src/lib/utils/audio.ts`, `StorageContext.addHistoryLog` | Flutter native alert with plate, confidence, evidence image, vehicle data, timestamp, camera/device, match reason, sound/vibration settings. | UI scaffold pending final native events. |
| History | `src/app/history/page.tsx`, `src/context/StorageContext.tsx` | Flutter history list/table equivalent with persisted detection/search/vehicle/user logs and CSV/export equivalent where needed. | Local scaffold complete with filters, pagination, native CSV export/share, and audit entries. Backend sync pending. |
| Vehicle CRUD | `src/app/vehicles/page.tsx`, `src/context/StorageContext.tsx`, `src/lib/utils/csv.ts` | Flutter vehicle repository, search, import/export, pagination/filter/sort/form behavior matching web. | Local scaffold complete with filters, add/edit/delete, pagination, native CSV import/export/share, and import tests. Backend sync pending. |
| User CRUD | `src/app/users/page.tsx`, `src/context/StorageContext.tsx` | Flutter user management permission-gated for admin roles. | Local scaffold complete with filters, add/edit, enable/disable, reset-password, delete, and user history drilldown. Backend sync pending. |
| Settings | `src/app/settings/page.tsx`, `src/lib/db/settingsDefaults.ts`, scanner settings in `src/lib/db/types.ts` | Flutter settings preserving detection confidence, OCR confidence, sound, refresh rate, scanner controls, special-series flags, and debug/dataset permissions. | Local scaffold complete for current native scanner parameters. |
| Search | `src/app/search/page.tsx`, `StorageContext.searchVehicles`, `matchingEngine.ts` | Flutter search preserving exact/possible/no-match results and audit log behavior. | Scaffolded. |
| Profile | `src/app/profile/page.tsx` | Flutter profile editing equivalent tied to current user. | Scaffolded. |
| Language | `src/context/LanguageContext.tsx`, `src/lib/dictionary.ts` | Flutter BM/EN localization using the same keys and text intent. | BM/EN layer started and wired to header/settings controls. |
| Data storage | `localStorage` keys in `AuthContext.tsx`, `StorageContext.tsx`, `specialSeries.ts` | Mobile persistent storage/API sync. Local offline cache must preserve vehicle, user, history, settings, selected camera, and runtime special-series prefixes. | Auth session persistence uses Android Keystore-backed encryption and iOS Keychain. Repository/API sync pending production backend details. |
| Tests | `src/__tests__/*.test.ts` | Keep TypeScript tests as reference during migration. Add Flutter unit tests and native integration tests for detector, OCR, tracker, validation, matching, and evidence. | Flutter parity/unit tests started and passing; native integration tests pending. |
| Model assets | `public/models/*` | Flutter assets plus native asset extraction for ONNX Runtime Mobile. | Flutter asset entries added. Native loading pending. |

## Native Scanner Target Pipeline

```text
CameraX / AVFoundation
  -> Environment classification
  -> Adaptive runtime config
  -> YOLOv8 plate detection
  -> Multi-object tracker
  -> Plate crop and vehicle context evidence buffers
  -> Motion and quality gates
  -> Best frame selection
  -> Perspective correction and OCR preprocessing variants
  -> PP-OCR
  -> Malaysian validation
  -> Special-series probability
  -> Temporal consensus
  -> Database/API matching
  -> Alert with evidence
  -> History
```

## Device Tiers

| Tier | Native Behavior |
| --- | --- |
| LOW | Lower resolution/FPS, slower detector cadence, one OCR worker, smaller evidence buffers, CPU-first ONNX. |
| MEDIUM | Balanced resolution/FPS, moderate detector cadence, limited OCR concurrency, adaptive preprocessing. |
| HIGH | Higher resolution/FPS, faster detector cadence, more OCR concurrency, larger evidence buffers, hardware acceleration when stable. |

## Phase Checklist

| Phase | Deliverable | Status |
| --- | --- | --- |
| 1 | Audit existing project and create migration map. | Complete in this document. |
| 2 | Create Flutter project structure without removing browser reference. | Complete for local structure. `android/` and `ios/` generated; `flutter pub get`, `flutter analyze`, `flutter test`, Android debug APK build, and iOS simulator build pass. |
| 3 | Recreate UI in Flutter. | Locally complete for scaffold workflows with paging, native CSV import/export/share, user drilldown, responsive phone/tablet navigation, BM/EN major labels, and passing Flutter tests. Visual QA pending before browser removal. |
| 4 | Connect authentication/backend. | Local/native foundation complete with auth/session repository, hardened native session storage, native session channel, API client scaffold, startup restore, expired/corrupt session cleanup, and login/logout audit events. Production backend details pending. |
| 5 | Implement Android CameraX/Kotlin native layer. | Local foundation complete with CameraX preview, lifecycle binding, ImageAnalysis frame acquisition, runtime metadata, native channels, native file picker, and Android build verification. Real-device validation pending. |
| 6 | Implement iOS AVFoundation/Swift native layer. | Local foundation complete with AVFoundation preview/output, lifecycle hooks, native channels, Keychain session storage, native file picker, iOS simulator build, and simulator launch verification. Real-device validation pending. |
| 7 | Integrate native detector. | Functional heuristic provider implemented; YOLOv8 ONNX provider parity remains. |
| 8 | Integrate tracker. | Functional native tracker implemented for detector fallback events. |
| 9 | Integrate plate quality. | Functional native heuristic provider implemented; quality ONNX provider optional. |
| 10 | Integrate environment intelligence. | Functional native heuristic provider implemented; environment ONNX provider optional. |
| 11 | Integrate OCR. | Pending. |
| 12 | Integrate Malaysian validation. | Dart parity layer started; native scanner integration pending. |
| 13 | Integrate special-series probability. | Dart parity layer started; native scanner integration pending. |
| 14 | Integrate consensus. | Dart parity layer started; native scanner integration pending. |
| 15 | Integrate database matching. | Dart parity layer started; backend/API sync pending. |
| 16 | Integrate alerts/history. | Pending. |
| 17 | Optimize Android. | Pending. |
| 18 | Optimize iOS. | Pending. |
| 19 | Real device testing. | Pending. |
| 20 | Production testing and release builds. | Pending. |

## Verification Gates Before Removing Browser Code

1. Flutter UI parity is reviewed screen-by-screen against the existing routes.
2. Android CameraX scanner runs continuously without crashes, ghost boxes, or evidence loss.
3. iOS AVFoundation scanner runs continuously without crashes, ghost boxes, or evidence loss.
4. Native YOLO detections match web detector output on a shared validation set.
5. Native PP-OCR output matches web PP-OCR output on plate crops, including two-line, square, EV, Sabah, Sarawak, Putrajaya, and special-series plates.
6. Tracker, evidence, consensus, matching, alerts, and history pass migrated tests.
7. Real devices pass the requested field matrix: Galaxy A52, Galaxy A54, Galaxy S22, iPhone 11, iPhone 13, iPhone 15 Pro.
8. Internal Android `.apk`, Android `.aab`, TestFlight build, and App Store archive are produced after real-device validation.
