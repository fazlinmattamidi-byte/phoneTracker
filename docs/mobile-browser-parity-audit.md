# PlateQ Browser To Native Parity Audit

This audit tracks whether the existing browser ANPR functions have been fully transferred to the Flutter/native mobile app.

Status terms:

- Complete: implemented locally and validated by tests/builds.
- Partial: usable local implementation exists, but browser parity, model parity, or field validation is not complete.
- Pending: not implemented natively yet.
- External: requires backend details, signing credentials, real devices, or store accounts.

| Browser Function | Native Status | Evidence | Remaining |
| --- | --- | --- | --- |
| App shell, login, dashboard, search, vehicles, users, history, settings, profile | Complete locally | Flutter screens, BM/EN localization, theme/language controls, local persistence, analyzer/tests passing | Visual signoff against browser screens on target devices |
| Local storage/local repository | Complete locally | Native JSON app storage persists vehicles, users, history, scanner settings, selected camera, language/theme, and runtime special prefixes | Backend sync remains external |
| CSV import/export/share | Complete locally | Native file/share channels on Android/iOS and Flutter import/export UI | Device UX validation |
| Android camera preview/frame acquisition | Partial | CameraX preview and ImageAnalysis build; Android APK builds | Real-device camera stability and long-run tests |
| iOS camera preview/frame acquisition | Partial | AVFoundation preview/output build; iOS simulator/release builds; simulator install/launch verified | Real iPhone camera validation and signing |
| YOLO detector | Partial | Android includes ONNX Runtime Mobile and iOS includes `onnxruntime-objc`; both stage `plate-detector.onnx`, create guarded CPU sessions, preprocess live camera frames into 640 letterboxed tensors, decode YOLO output, apply filters/NMS, and feed real detections into tracking. Synthetic fallback boxes are disabled. Shared tests cover tensor decode, letterbox reverse mapping, filters/NMS, and multiple non-overlapping plate boxes. | Orientation/perspective fixture parity, hardware acceleration, real-device performance |
| Multi-vehicle scanning | Partial | Android/iOS tracker now receives multiple YOLO detections per analyzed frame and can create/update multiple native tracks up to `maxTracks`; Flutter overlay can render multiple tracks; shared decoder tests keep multiple non-overlapping detections after NMS | Clip validation with real multi-vehicle scenes, ByteTrack parity |
| Tracker lifecycle | Partial | Android/iOS native tracks have visible/lost/removed lifecycle, confidence smoothing, caps, evidence retention, and OCR candidate selection | Full browser ByteTrack two-stage high/low confidence association, velocity prediction parity, multi-clip tests |
| Plate quality | Partial | Android/iOS native heuristic scoring emits web-compatible classes; evidence selection uses quality/detector/size/stability | Optional ONNX quality provider and perspective/recency parity |
| Environment intelligence/speed adaptation | Partial | Android/iOS report tier, memory, thermal state, analyzer stride, OCR concurrency caps, frame stats environment label/provider | Browser runtime benchmarking/adaptive config parity, long-run thermal tests |
| Evidence buffers and best frame | Partial | Native retains per-track best analyzed frame and writes raw/enhanced/binary/top/bottom/inner-text JPEG evidence paths. Android OCR preprocessing now evaluates enhanced, inner-text, two-line split, 180-degree recovery, and mild deskew candidates. | Full perspective scoring parity and real footage crop accuracy |
| PP-OCR recognizer | Partial | Flutter has dictionary loading and greedy CTC decoder tests; Android and iOS load the staged PP-OCR dictionary/session, preprocess best crops into `1x3x48x320` PaddleOCR tensors, run ONNX Runtime CPU inference, greedily decode CTC output, rank adaptive crop candidates, and emit `CPU_ONNX_PP_OCR` events only from real OCR output. Hardcoded fallback plate text is disabled. | Real-device OCR validation, early-stop/benchmark parity |
| Malaysian validation | Complete locally | Dart validation/normalization/special-series logic connected to scanner OCR events and tests | Broader native fixture validation |
| Special-series probability | Complete locally | Runtime prefixes can be edited in Settings and persist natively; scanner OCR uses correction path | Field fixtures |
| Consensus | Complete locally | Flutter scanner maintains per-track OCR votes, confidence gates, promotion, and cooldown | Real OCR validation |
| Database matching | Complete locally | Stabilized OCR events match local repository for exact/possible/no-case/closed/cleared/repeated-character omission | Production backend sync |
| Alerts/history | Complete locally for event flow | Alerts show vehicle/evidence metadata, sound/haptic feedback, and persisted history writes | Real camera/OCR evidence validation and backend history sync |
| Production builds | Partial | Android debug APK, release APK, release AAB, iOS simulator app, and unsigned iOS release app build | Android production signing, Apple signing, TestFlight/App Store archive |

## Not Fully Native Yet

The native app is not yet a signed production replacement for the browser scanner because these items still require external validation:

1. Full browser tracker parity across real multi-vehicle video clips.
2. Full perspective-corrected OCR preprocessing parity.
3. Browser runtime benchmarking/adaptive performance policy parity.
4. Production backend sync.
5. Real-device field matrix validation.
6. Android and Apple production signing/TestFlight/App Store release.
