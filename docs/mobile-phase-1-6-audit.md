# Phase 1-6 Completion Audit

This audit separates locally completed work from items that cannot be truthfully marked complete without an external install, production backend details, or real-device validation.

## Phase 1: Audit Existing Project

Status: Complete.

Completed:

- Existing browser source-of-truth areas are mapped in `docs/mobile-migration-map.md`.
- Native bridge contract is defined in `docs/mobile-native-contract.md`.
- Remaining migration phases are tracked in `docs/mobile-remaining-phases.md`.
- Phase checklists exist for Phase 1-3 and Phase 4-6.

Still not required for code completion, but useful before field release:

- Capture visual comparison screenshots once the old browser UI and Flutter app are both running on the target review machine.
- Export real scanner fixtures after camera/ONNX phases are implemented.

## Phase 2: Flutter Project Structure

Status: Complete for Android, Flutter source, and iOS simulator build.

Completed:

- Flutter SDK installed and project scaffolded.
- Official `android/` and `ios/` folders generated.
- `flutter pub get`, `flutter analyze`, `flutter test`, Android debug build, and iOS simulator build pass.
- Android toolchain and licenses are healthy in `flutter doctor`.
- Xcode is selected, the iOS simulator runtime is installed, and `flutter doctor -v` reports no issues.
- iOS simulator launch on iPhone 17 simulator is verified.

Remaining:

- Physical iPhone launch/camera validation after Apple signing/provisioning.

## Phase 3: Flutter UI Parity

Status: Locally complete for the migrated Flutter scaffold; external visual/device QA remains.

Completed:

- Login, shell/navigation, dashboard, scanner, search, vehicles, users, history, settings, profile, and more menu exist in Flutter.
- BM/EN localization layer is wired to the major UI.
- Vehicle/user/history/search/profile/settings flows are interactive.
- Vehicle, user, and history lists have filtering and pagination.
- Vehicle/history CSV export uses native share sheet with clipboard fallback.
- Vehicle CSV import uses native Android/iOS file pickers, parses CSV in Dart, updates existing plates, inserts new plates, skips invalid rows, and records audit history.
- User history drilldown exists.
- Phone layout uses bottom navigation; wide layout uses navigation rail.
- Flutter analyzer/tests pass.

Local code remaining:

- None for Phase 3 scaffold scope.

External/manual QA remaining:

- Visual parity screenshots still need target-device review before removing browser code.

## Phase 4: Authentication, Session, Backend Contract

Status: Complete for local/native foundation; blocked for production backend.

Completed:

- Auth/session repository, async login, logout, startup restore, and audit logging exist.
- Startup shows login unless a valid native session restores.
- Expired/corrupt sessions are cleared.
- Android session storage uses Android Keystore-backed AES/GCM encryption where supported.
- iOS session storage uses Keychain.
- Production API client scaffold exists with `PLATEQ_API_BASE_URL` / `PLATEQ_API_ENV`, timeout, retry, auth header, JSON parsing, and error mapping.

External integration remaining:

- Production backend login/sync cannot be completed until API base URL, endpoint schema, auth policy, and credentials are provided.
- Real account revocation/refresh-token behavior requires backend support.

## Phase 5: Android Native Camera Foundation

Status: Source complete and Android build verified.

Completed:

- Android camera permissions and optional camera features are declared.
- Native ANPR method/event channels are registered.
- Native auth and share channels are registered.
- Native CSV import picker channel is registered.
- Camera enumeration uses Android camera services.
- Platform camera preview uses CameraX `PreviewView`.
- Frame acquisition foundation uses CameraX `ImageAnalysis`.
- Runtime events include frame metadata counters.
- Android debug APK builds successfully.

Local code remaining:

- None for Phase 5 foundation scope.

External validation remaining:

- Real-device camera validation is still required.
- Detector/OCR integration begins in Phase 7 and later.

## Phase 6: iOS Native Camera Foundation

Status: Source complete and iOS simulator-build verified.

Completed in source:

- iOS camera permission description is declared.
- Native ANPR method/event channels are registered.
- Native auth and share channels are registered.
- Native CSV import picker channel is registered.
- Camera enumeration uses AVFoundation.
- Platform preview source uses `AVCaptureVideoPreviewLayer`.
- Frame acquisition source uses `AVCaptureVideoDataOutput`.
- Session storage uses Keychain.
- Flutter 3.44 optional registrar handling is fixed.
- Xcode/codesign extended-attribute workaround is wired for this macOS/Xcode setup.
- iOS simulator app builds at `build/ios/iphonesimulator/Runner.app`.
- iOS simulator launch on iPhone 17 simulator is verified.

Local code remaining:

- None for Phase 6 foundation scope.

External validation remaining:

- Real iPhone camera validation after Apple signing/provisioning.

## Manual Items Required For 100% Signoff

1. Provide the production backend API base URL and endpoint/auth schema.
2. Configure Apple Developer signing/provisioning for physical iPhone, TestFlight, and App Store archives.
3. Run real-device camera validation on Android and iPhone.
4. Provide/confirm production model assets and backend sync rules for release.
