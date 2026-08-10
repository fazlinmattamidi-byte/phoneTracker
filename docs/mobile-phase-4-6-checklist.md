# Phase 4-6 Conversion Checklist

This document tracks the current implementation pass after Phase 3 UI parity work.

## Phase 4: Authentication, Session, Backend Contract

Status: Complete for local/native foundation. Production backend integration is blocked until API details are provided.

Completed:

- Added Flutter `AuthSession` and `AuthRepository` in `lib/src/core/auth_repository.dart`.
- Wired async login validation into the Flutter login screen.
- Preserved the current demo role login flow while validating active/disabled user status.
- Added native session MethodChannel `plateq.auth/session`.
- Added Android session persistence with Android Keystore-backed AES/GCM encryption where supported.
- Added iOS session persistence with Keychain.
- Added session restore on app startup.
- Added startup loading state so the app shows login unless a valid native session restores.
- Added expired/corrupt native session cleanup.
- Added login/logout audit history entries.
- Added production API client scaffold with `PLATEQ_API_BASE_URL` / `PLATEQ_API_ENV` Dart defines, timeout, retry, auth header, JSON parsing, and error mapping.
- Added backend-returned user fallback so a valid backend session can create a local mobile user shell instead of crashing.

Local Phase 4 code remaining:

- None without production backend details.

External Phase 4 integration remaining:

1. Provide production API base URL and endpoint/schema.
2. Add refresh-token/session-expiry handling if the backend policy requires refresh tokens.
3. Add account revocation/disabled-user polling once a backend status endpoint exists.
4. Add backend sync for profile updates, vehicle repository, users, settings, and history.

## Phase 5: Android Native Camera Foundation

Status: Source complete for Android native camera foundation and compile-verified.

Completed:

- Added Android camera permissions and optional camera feature declarations.
- Registered MethodChannel `plateq.anpr/methods`.
- Registered EventChannel `plateq.anpr/events`.
- Registered platform view `plateq.anpr_camera_preview`.
- Added Android camera enumeration through `CameraManager`.
- Added native camera permission request/check flow.
- Added start/stop/update/dispose scanner lifecycle handlers.
- Added runtime and empty track-update events for the Flutter scanner UI.
- Replaced preview placeholder with CameraX `PreviewView`.
- Bound CameraX preview and analysis to the Flutter activity lifecycle.
- Added CameraX `ImageAnalysis` frame acquisition foundation.
- Runtime events include frame dimensions, rotation, and frame counters.
- Native file channel includes Android CSV document picker for Phase 3 imports.
- Verified Android debug APK build.

Local Phase 5 code remaining:

- None for the CameraX foundation scope.

External Phase 5 signoff:

1. Real-device Android camera validation.
2. Long-run Android camera stability tests.
3. Detector/OCR integration in Phase 7 and later.

## Phase 6: iOS Native Camera Foundation

Status: Source complete for iOS native camera foundation and simulator-build verified.

Completed:

- Added iOS camera usage description in `Info.plist`.
- Registered MethodChannel `plateq.anpr/methods`.
- Registered EventChannel `plateq.anpr/events`.
- Registered platform view `plateq.anpr_camera_preview`.
- Added AVFoundation camera enumeration through `AVCaptureDevice.DiscoverySession`.
- Added native camera permission request/check flow.
- Added start/stop/update/dispose scanner lifecycle handlers.
- Added runtime and empty track-update events for the Flutter scanner UI.
- Replaced preview placeholder source with `AVCaptureVideoPreviewLayer`.
- Added `AVCaptureVideoDataOutput` frame acquisition source.
- Added foreground/background session start-stop hooks.
- Added iOS session persistence with Keychain.
- Native file channel includes iOS CSV document picker for Phase 3 imports.
- Fixed Flutter 3.44 optional registrar handling in `AppDelegate.swift`.
- Added Xcode/codesign extended-attribute workaround for this macOS/Xcode setup.
- Verified iOS simulator build at `build/ios/iphonesimulator/Runner.app`.
- Verified iOS simulator launch on iPhone 17 simulator.

Local Phase 6 code remaining:

- None for the AVFoundation foundation scope.

External Phase 6 signoff:

1. Run real iPhone camera validation after Apple signing/provisioning is available.
2. Detector/OCR integration in Phase 7 and later.
