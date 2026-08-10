# Phase 1-3 Conversion Checklist

This document tracks the current requested focus: continue Phase 1 through Phase 3 before moving into native Android/iOS scanner implementation.

## Phase 1: Audit Existing Project

Status: Complete enough to guide migration. Keep expanding if new web behavior is discovered.

Completed:

- Inspected app structure, routes, contexts, ANPR services, model assets, tests, and seed data.
- Created `docs/mobile-migration-map.md`.
- Created `docs/mobile-native-contract.md`.
- Created `docs/mobile-remaining-phases.md`.
- Identified browser source-of-truth files for scanner, tracker, OCR, quality, environment, matching, roles, storage, alerts, history, vehicle CRUD, user CRUD, settings, and UI navigation.

Still useful before native work:

- Capture screenshots of every current web screen for visual parity review.
- Export representative scanner validation fixtures: full frames, plate crops, OCR expected output, match expected output.
- Freeze a formal API/backend contract if production backend differs from the current local/demo repository.

## Phase 2: Flutter Project Structure

Status: Complete for Flutter, Android, and iOS simulator project structure.

Completed:

- Installed Flutter 3.44.9 / Dart 3.12.2.
- Added root `pubspec.yaml` for one Flutter project.
- Added `lib/main.dart`.
- Added Flutter app shell in `lib/src/mobile_app.dart`.
- Added core app state and seed data in `lib/src/core/`.
- Added native ANPR bridge contract code in `lib/src/anpr/native_anpr_bridge.dart`.
- Declared existing model/logo assets for Flutter.
- Updated `.gitignore` with Flutter/Dart generated artifacts.
- Generated official `android/` and `ios/` platform folders with `flutter create --platforms=android,ios .`.
- Verified `flutter pub get`.
- Verified `flutter analyze`.
- Verified `flutter test`.
- Installed Android command-line tools and accepted Android SDK licenses.
- Verified Android debug build at `build/app/outputs/flutter-apk/app-debug.apk`.
- Installed and selected full Xcode.
- Installed the iOS 26.5 simulator runtime.
- Verified `flutter doctor -v` reports no issues.
- Verified iOS simulator build at `build/ios/iphonesimulator/Runner.app`.
- Verified iOS simulator launch on iPhone 17 simulator.
- Added project-local codesign extended-attribute workaround for this macOS/Xcode setup.

Phase 2 remaining:

1. Run a physical iPhone smoke test once Apple signing/provisioning is available.

## Phase 3: Flutter UI Parity

Status: Locally complete for the Flutter scaffold. External visual parity review remains before retiring the browser reference.

Completed:

- Login screen scaffold with demo role workflow.
- Main app shell with top header, role badge, language toggle, theme toggle, profile/logout controls.
- Bottom navigation matching the web mobile navigation structure.
- Dashboard metrics, quick navigation, recent audit stream.
- Scanner screen scaffold with native preview slot, camera selector, start/stop controls, runtime metrics, seen plates, alert overlay, and native event handling.
- Search screen wired to Dart ANPR/matching logic.
- Vehicle list screen using migrated seed repository data.
- User list screen with role permission gating.
- History screen.
- Settings screen with BM/EN language, dark/light theme, detection confidence, OCR confidence, and sound alerts.
- Profile screen.
- BM/EN localization layer started from the web dictionary.
- Dart parity logic/tests started for Malaysian validation, special-series correction, consensus, matching, permissions, and evidence scoring.
- Manual search filters by plate, customer, finance company, case reference, and vehicle details.
- Vehicle repository filters plus add/edit/delete dialogs, pagination, and native CSV export/share.
- Vehicle repository native CSV import picker on Android and iOS, with Dart CSV parsing, add/update/skip summary, audit logging, and import tests.
- User management filters plus add/edit, enable/disable, reset-password, and delete actions.
- User history drilldown.
- History search/type/sort filters plus pagination and native CSV export/share.
- Profile edit and password-change demo workflow.
- Expanded scanner settings for refresh rate, consensus votes, max tracks, OCR concurrency, special-series recognition, developer mode, and dataset mode.
- Responsive phone/tablet shell with bottom navigation on phones and navigation rail on wide layouts.
- Flutter analyzer and tests pass.

Phase 3 local code remaining:

- None for the current scaffold scope.

External Phase 3 signoff:

1. Compare Flutter UI against web screenshots screen-by-screen.
2. Add visual regression screenshots from Android and iOS simulator/device runs.

## Stop Point Before Phase 4

Do not move into backend auth as "complete" until:

- Flutter SDK is available.
- Phase 2 generated platform shells are present and simulator builds pass.
- Phase 3 local UI scaffold is complete and manually reviewable against the existing web UI.
- Flutter tests can run locally.
