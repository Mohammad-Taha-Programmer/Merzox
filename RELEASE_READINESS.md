# Merzox Production Release Readiness

This document defines the repository-side production release preflight.

It does not claim that Merzox is currently production-ready and does not invent
identifiers, credentials, provider configuration, legal approval, or operational
evidence.

## Commands

Non-blocking audit:

```bash
dart run tool/release_readiness.dart --audit
```

A successful scan exits `0` even when `CAN_RELEASE=false`.

Authoritative release gate:

```bash
dart run tool/release_readiness.dart --require-ready
```

This mode exits `2` while any release blocker remains. Invalid usage exits `64`;
a bounded repository scan failure exits `3`.

## Repository-derived facts

The scanner reads tracked repository facts for:

- canonical Merzox application identity;
- Android `applicationId`;
- iOS application bundle identifier;
- Android debug release-signing regression state;
- Android production-signing repository structure;
- Firebase platform-configuration readiness.

Missing, malformed, or ambiguous required source fails the scan. A Firebase
attestation cannot override a repository readiness flag of `false`.

## Boolean production attestations

Only the literal value `true` satisfies these external evidence flags:

- `MERZOX_RELEASE_ANDROID_SIGNING_READY`
- `MERZOX_RELEASE_IOS_SIGNING_READY`
- `MERZOX_RELEASE_FIREBASE_READY`
- `MERZOX_RELEASE_PLAY_STORE_READY`
- `MERZOX_RELEASE_APP_STORE_READY`
- `MERZOX_RELEASE_PAYMENT_READY`
- `MERZOX_RELEASE_DEPLOYMENT_READY`
- `MERZOX_RELEASE_TELEMETRY_READY`
- `MERZOX_RELEASE_RECOVERY_READY`
- `MERZOX_RELEASE_PRIVACY_LEGAL_APPROVED`
- `MERZOX_RELEASE_IOS_PRIVACY_AUDIT_COMPLETE`

These are attestations, not credentials. The preflight does not request, read,
or print keystore passwords, private keys, Apple credentials, provider secrets,
JWT secrets, SMTP passwords, or Firebase service credentials.

## Release rule

A production release is allowed only when the blocker set is empty.

The development repository intentionally remains fail-closed: its mobile
identity is still `com.example.merzox`, Android has a fail-closed production
signing structure but its real signing activation attestation is not supplied,
Firebase platform readiness is false, and other production attestations remain
unsupplied.

## CI boundary

Normal CI runs only:

```bash
dart run tool/release_readiness.dart --audit
```

Normal CI must not run `--require-ready` while production activation remains
intentionally incomplete.

A future explicit release workflow may run `--require-ready` only after the
required repository changes and approved production evidence exist.

The preflight does not build, sign, upload, publish, deploy, or mutate
production infrastructure.

## Android production signing

Tracked Gradle configuration must bind the Android `release` build type to a
dedicated `signingConfigs.release` configuration. There is no debug-signing
fallback.

Real signing material is deliberately external to Git. The approved release
environment provides an ignored `android/key.properties` with these property
names:

- `storeFile`
- `storePassword`
- `keyAlias`
- `keyPassword`

`storeFile` is resolved from the Android project root. The referenced upload
keystore must also remain outside source control.

When a Gradle task whose name contains `release` is requested, configuration
fails closed if `android/key.properties` is absent, if any required property is
blank, or if the referenced keystore file does not exist. Debug tasks do not
require production signing material.

Repository structure alone does not prove that the real production key is
available and approved. `MERZOX_RELEASE_ANDROID_SIGNING_READY=true` may be set
only by the approved release environment after the real signing material has
been injected and validated, for example by a successful
`:app:validateSigningRelease` or equivalent signed release pipeline evidence.

The release-readiness scanner never reads `android/key.properties`, keystore
bytes, passwords, aliases, or private-key material. It inspects only tracked
Gradle structure and the boolean activation attestation.

Normal development and CI must leave
`MERZOX_RELEASE_ANDROID_SIGNING_READY` unset unless approved production
evidence is actually present.

## iOS privacy audit

The repository-level Required Reason API audit and dependency remediation are documented in [`IOS_PRIVACY_AUDIT.md`](IOS_PRIVACY_AUDIT.md).

Repository-level remediation does not satisfy the production archive gate by itself. `MERZOX_RELEASE_IOS_PRIVACY_AUDIT_COMPLETE=true` must remain unset until the final signed iOS archive is validated on macOS/Xcode.
