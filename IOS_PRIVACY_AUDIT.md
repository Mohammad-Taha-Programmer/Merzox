# iOS Privacy / Required Reason API Audit

## Scope

This audit covers the Merzox iOS Runner and the Flutter dependency graph that can contribute native code to the iOS application.

Required Reason API declarations belong to the bundle that uses the API. Merzox must not add an app-level declaration merely to compensate for a third-party SDK whose own privacy manifest is incomplete.

## Repository findings

- App-owned native iOS Runner sources do not currently use the audited Required Reason API categories: File Timestamp, System Boot Time, Disk Space, Active Keyboards, or User Defaults.
- `firebase_messaging`, `permission_handler_apple`, and `shared_preferences_foundation` provide matching User Defaults declarations in their own privacy manifests.
- The `flutter_secure_storage_darwin` `creationDate` source signal is a local Swift property name, not demonstrated app-owned Required Reason API use.
- `package_info_plus` 10.2.x uses iOS file timestamp APIs while its packaged privacy manifest contains no Required Reason API declaration.
- Merzox does not import or call `package_info_plus` directly. It entered the resolved graph transitively through Linux support added by `geolocator` 14.0.2+.
- The iOS `GeneratedPluginRegistrant.m` is generated locally and is not tracked by Git in this repository, so it is not used as a permanent repository contract.
- The tracked macOS generated registrant is updated by Flutter dependency resolution and no longer imports or registers `package_info_plus`.

## Remediation

Merzox pins `geolocator` to `14.0.1`.

The documented production scope is Android and iOS mobile. Version 14.0.1 keeps `geolocator_apple` in the resolved graph while removing the `geolocator_linux -> package_info_plus` chain that caused the unrelated SDK to enter the resolved Flutter plugin graph.

The dependency is pinned exactly, not with a caret range, so a later `flutter pub get` cannot silently resolve 14.0.2+ and reintroduce that privacy surface.

## Guardrails

The repository contract requires:

- `geolocator: 14.0.1` in `pubspec.yaml`;
- no `geolocator_linux` or `package_info_plus` entry in `pubspec.lock`;
- `geolocator_apple` remains present in `pubspec.lock`;
- the tracked macOS generated registrant contains `GeolocatorPlugin` and does not contain `package_info_plus` or `FPPPackageInfoPlusPlugin`;
- no app-owned `ios/Runner/PrivacyInfo.xcprivacy` is created without demonstrated app-owned Required Reason API use.

## Remaining release gate

This repository audit does not replace Apple-platform archive validation.

Before setting `MERZOX_RELEASE_IOS_PRIVACY_AUDIT_COMPLETE=true` for a production release, the final signed iOS archive must be inspected on macOS/Xcode using the actual release dependency graph. Any App Store Connect privacy-manifest or Required Reason API diagnostic must be resolved at the bundle that owns the API use.

Until that macOS/archive validation succeeds, the production release-readiness checker must continue to report `iosPrivacyManifestAuditIncomplete`.
