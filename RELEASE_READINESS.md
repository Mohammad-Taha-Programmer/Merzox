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
- Android debug release signing;
- Firebase platform-configuration readiness.

Missing, malformed, or ambiguous required source fails the scan. A Firebase
attestation cannot override a repository readiness flag of `false`.

## Boolean production attestations

Only the literal value `true` satisfies these external evidence flags:

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
identity is still `com.example.merzox`, Android release still uses debug
signing, Firebase platform readiness is false, and production attestations are
not supplied.

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
