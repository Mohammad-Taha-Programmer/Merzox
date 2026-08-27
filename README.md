# Merzox

<p align="center">
  <img src="assets/images/MERZOX_LOGO.png" alt="Merzox logo" width="150">
</p>

Merzox is a bilingual, neighborhood-focused e-commerce application that connects
customers with nearby businesses, their products, and their services. The mobile
client is built with Flutter for Android and iOS, while the API uses Node.js,
Express, MongoDB, and Mongoose.

The project is under active development. Arabic is the default language, with
English coverage across application UI copy and RTL/LTR support. Controlled
client-side API fallback errors are localized in both languages, while
language-aware sharing payloads are generated in Arabic or English at runtime.

## Current Features

### Customer experience

- Custom splash screen and three-step onboarding flow.
- Sign up and login with either an email address or an international phone number.
- Email verification before an email-based account is persisted.
- Guest browsing with purchasing and account changes restricted to authenticated users.
- Home feed for new, highly rated, discounted, and nearby businesses.
- Explicitly opt-in business recommendations derived on demand from existing
  server-side favorites and delivered-order categories.
- Paginated all-businesses catalog.
- Search for products, services, and businesses, with local search history.
- Business profiles with information, products, services, ratings, and reviews.
- Product details with image galleries, quantities, ratings, favorites, cart
  actions, direct-purchase entry points, and product variant selection with
  variant-specific pricing, stock, and availability.
- Persistent cart and authenticated checkout flow.
- Order history grouped into current, completed, and cancelled orders.
- Favorites for businesses, products, and services.
- Direct messaging with a business, with all/unread inbox tabs and unread badges.
- Order tracking with a four-step delivery timeline, courier details, foreground
  courier live-location mapping during delivery, delivery address changes before
  preparation starts, and a post-delivery store rating.
- Notification feed for order status changes, replies, and new orders.
- Nearby-business map with filtering, business details, and external directions.
- Profile editing with multiple labeled phone numbers and email addresses.
- About Us content retrieved from MongoDB and displayed in accordions.
- Platform-aware app sharing through WhatsApp, Messenger, Instagram, Telegram,
  email, link copying, and the native share sheet.

### Business experience

- Upgrade an existing customer account through business enrollment.
- Business dashboard and profile management.
- Product and service management.
- Business order management with validated status transitions.
- Order detail and invoice view with customer, delivery, and payment details.
- Courier assignment with an order-scoped capability whose raw credential is
  returned once for merchant-to-courier handoff.
- Merchant inbox for customer conversations.
- Store settings for the logo, description, and social media links.

### Application foundations

- BLoC-based state management for application workflows.
- Arabic and English application UI localization with RTL/LTR support, including
  controlled client-side API fallback errors and locale-aware error rendering.
- Runtime location permission handling.
- Responsive Android and iOS UI based on the supplied Adobe XD designs.
- Local session persistence and configurable API endpoints.
- GitHub Actions CI verifies pull requests and pushes to `main` with Flutter,
  backend, and disposable-MongoDB integration test jobs.

## Technology

| Area | Technology |
| --- | --- |
| Mobile | Flutter, Dart, Material |
| State management | `flutter_bloc` |
| Navigation | `go_router` |
| Networking | `dio` |
| Local persistence | Shared Preferences, Hive, Flutter Secure Storage |
| Maps and location | `flutter_map`, OpenStreetMap, Geolocator |
| Backend | Node.js, Express |
| Database | MongoDB, Mongoose |
| Authentication | JWT, bcrypt |
| Email | Nodemailer with configurable SMTP |

## Repository Structure

```text
merzox/
|- android/                 Android platform configuration
|- ios/                     iOS platform configuration
|- assets/                  Images, fonts, and translations
|- backend/                 Express and MongoDB API
|- lib/
|  |- app/                  Application bootstrap and root widget
|  |- core/                 Shared constants and startup behavior
|  |- features/             Feature-first Flutter modules and BLoCs
|  |- router/               Application routes
|  `- services/             API, storage, location, and sharing services
`- test/                    Flutter tests
```

## Prerequisites

- Flutter SDK compatible with Dart `^3.8.1`.
- Android Studio and an Android SDK for Android development.
- Xcode on macOS for iOS development.
- A recent Node.js LTS release and npm.
- MongoDB locally or a MongoDB Atlas connection string.

## Backend Setup

From the project root:

```powershell
cd backend
npm install
Copy-Item .env.example .env
```

Update `backend/.env` with your own values. At minimum, use a real MongoDB URI
and a long, randomly generated JWT secret:

```dotenv
PORT=3000
MONGODB_URI=mongodb://127.0.0.1:27017/merzox
JWT_SECRET=replace-with-a-random-secret-at-least-32-characters-long
PUBLIC_BASE_URL=http://localhost:3000
```

To enable verification emails, configure one SMTP account. The SMTP provider
can send to recipients at Gmail, Outlook, Yandex, or other email services:

```dotenv
SMTP_HOST=smtp.example.com
SMTP_PORT=587
SMTP_SECURE=false
SMTP_USER=your-smtp-user
SMTP_PASS=your-smtp-or-app-password
SMTP_FROM="Merzox <no-reply@example.com>"
```

Start the API:

```powershell
npm run dev
```

Optional development data can be recreated with:

```powershell
npm run seed
```

> `npm run seed` clears the collections managed by the seed script. Do not run
> it against a production database.

The backend exposes separate operational probes:

- `GET /health` is process liveness and does not depend on MongoDB.
- `GET /ready` is deployment readiness. It returns HTTP `200` only after the
  runtime is accepting traffic and MongoDB is connected; otherwise it returns
  HTTP `503`.
- `SIGTERM` and `SIGINT` trigger an idempotent graceful shutdown: readiness is
  withdrawn first, background reconciliation stops, realtime/push transports
  close, HTTP drains, and MongoDB disconnects before Node exits naturally.
- Every HTTP request receives a server-generated `X-Request-ID`. Operational
  access/error/runtime logs are one-line structured JSON with a bounded field
  allowlist; request bodies, query strings, authentication headers and raw
  errors are not logged.

More backend details and endpoint documentation are in
[backend/README.md](backend/README.md).

## Flutter Setup

Install dependencies from the project root:

```powershell
flutter pub get
```

Run against a locally hosted API:

```powershell
flutter run --dart-define=MERZOX_API_BASE_URL=http://10.0.2.2:3000/api/v1
```

Use `10.0.2.2` for the Android emulator. For a physical device, replace it with
the development computer's LAN address and ensure the device and computer are on
the same network. On the iOS simulator, `localhost` can normally be used.

## Store Sharing Configuration

The sharing feature selects Google Play on Android and the App Store on iOS.
Provide the final listing URLs when running or building a published version:

```powershell
flutter build apk `
  --dart-define=MERZOX_PLAY_STORE_URL=https://play.google.com/store/apps/details?id=your.package.id `
  --dart-define=MERZOX_APP_STORE_URL=https://apps.apple.com/app/idYOUR_APP_ID
```

Until a listing exists, Android derives a Google Play URL from the package ID and
iOS falls back to an App Store search for Merzox.

## Validation

Run Flutter static analysis and tests:

```powershell
flutter analyze
flutter test
```

Run backend syntax checks and model tests:

```powershell
cd backend
npm run check
npm test
```

GitHub Actions automatically verifies pull requests and pushes to `main`. The workflow runs Flutter formatting, analysis, and tests; backend syntax checks and standard tests; and the authorization and checkout/inventory integration suites against disposable loopback MongoDB databases. If either integration suite reports `SKIPPED`, the integration job fails.

Build an Android debug APK:

```powershell
flutter build apk --debug
```

## Security Notes

- Passwords are hashed with bcrypt and are never returned by the API.
- Protected endpoints require JWT authentication.
- API input is validated, normalized, and size-limited.
- Helmet, CORS restrictions, rate limiting, HPP protection, and MongoDB query
  sanitization are enabled by the backend.
- Local `.env` files, dependencies, and build output are excluded from Git.
- Location and other sensitive permissions are requested only for relevant flows.
- Personalized recommendations require both the server-side
  `aiPersonalization` permission and a `granted` consent lifecycle. They are
  computed on demand from bounded favorites and delivered orders; local search
  history, clicks, page views, contacts, and location are not recommendation
  signals, and no derived preference profile is persisted.
- Courier location sharing is foreground-only; Merzox does not request Android
  or iOS background-location permission for the courier flow.
- Courier location capabilities are order-scoped and expire after 12 hours. Only
  the SHA-256 capability hash is stored; reassignment rotates the credential and
  explicit revocation or a terminal order state removes its authority.
- Courier tracking stores only the latest location snapshot, not route history.
  Samples older than 15 minutes are hidden from the customer, and Socket.IO sends
  only order invalidation metadata; coordinates are obtained from authenticated
  REST order tracking.

These controls reduce common risks but do not replace a professional security
review, production secret management, monitoring, backups, or dependency audits.

## Roadmap

- Finalize the permanent mobile application identity, Firebase platform
  registrations/APNs setup, and production activation of the already implemented
  realtime and background push transport.
- Activate real processing for card, bank-transfer, and assisted payment flows beyond the current cash-only operational baseline.
- Production deployment, observability, and store publication.

## Payment capability guard

Merzox keeps the historical order-payment vocabulary `cash`, `card`,
`bankTransfer`, and `assisted`, but recognized does not mean operational.

The backend currently fails closed:

- `cash` is the only operational checkout payment method.
- `card`, `bankTransfer`, and `assisted` remain recognized for API/history
  compatibility but are rejected with `PAYMENT_METHOD_UNAVAILABLE`.
- Unknown or malformed methods are rejected separately with
  `INVALID_PAYMENT_METHOD`.
- The rejection occurs in request validation before `createOrder`, so an
  unavailable payment method cannot create a `CheckoutIntent`, reserve stock,
  mutate inventory, or create an `Order`.
- No payment gateway, card SDK, merchant credential, provider webhook, capture,
  or monetary refund flow is configured by this repository yet.

A future provider integration must explicitly activate a payment method only
after its processing lifecycle, idempotency, webhook verification, failure
recovery, and refund/cancellation semantics have been implemented and reviewed.

## Production Firebase activation guard

Realtime chat, live notification invalidation, push registration lifecycle,
background delivery plumbing, and notification-tap routing are implemented.
Production Firebase activation is intentionally deferred until Merzox has a
permanent application namespace.

The repository fails closed by default:

- `MERZOX_FIREBASE_PUSH_ENABLED` defaults to `false`.
- The current application identity remains development-only.
- Firebase initialization additionally requires a matching
  `MERZOX_FIREBASE_PRODUCTION_ID`.
- The repository-level Firebase platform-readiness flag remains `false` until
  the final Android/iOS Firebase applications and configuration files are
  reviewed together.
- Android/iOS Firebase applications must not be registered against a guessed
  temporary namespace merely to enable production push during development.

After a permanent identity is selected, migrate the platform identifiers first.
Only then register the Android/iOS Firebase applications, add the reviewed
platform configuration, enable the readiness flag in the same change, and
explicitly supply the production Firebase dart-defines.

## Project Status

Merzox is currently a development-stage product. Store identifiers, payment
credentials, production SMTP credentials, deployment URLs, privacy documents,
and final legal content must be supplied before public release.

### Development CLI safety

The database seed and SMTP diagnostic are development-only maintenance tools.

- The seed command refuses to run when `NODE_ENV=production`.
- Outside production, the seed command requires
  `MERZOX_ALLOW_DESTRUCTIVE_SEED=true`.
- The SMTP diagnostic refuses to run when `NODE_ENV=production`.
- Outside production, the SMTP diagnostic requires
  `MERZOX_ALLOW_EMAIL_DIAGNOSTIC=true`.
- The production refusal cannot be overridden by either opt-in flag.
- CLI failures expose only bounded error class/code information rather than raw
  provider responses, error messages, stack traces, recipients, tokens, or
  verification URLs.
- Development seed credentials are fixtures only and must never be reused as
  production credentials.

### Backend production configuration

The backend validates its runtime environment before accepting traffic.

When `NODE_ENV=production`:

- `JWT_SECRET` must contain at least 32 characters.
- `PUBLIC_BASE_URL` is mandatory and must be an HTTPS origin.
- Configured CORS entries must be exact HTTPS origins; development wildcard
  patterns are refused.
- SMTP delivery must be fully configured because production email signup does
  not expose verification URLs to the API client.

In every environment, invalid ports, rate-limit numbers, boolean flags, or an
unknown `NODE_ENV` are refused during configuration loading rather than being
silently coerced into unusable runtime values.

### Reverse-proxy client IPs

The backend does not trust forwarded client-IP headers by default.

When deployment places Merzox behind a reverse proxy or load balancer, configure
`TRUST_PROXY_RANGES` with only the IP addresses or CIDR ranges from which the
API server actually receives trusted proxy connections.

Merzox deliberately does not support `trust proxy=true` or numeric hop counts.
This keeps IP-based rate limiting tied to a verifiable proxy topology rather
than trusting an attacker-controlled `X-Forwarded-For` chain.

The ingress proxy must also overwrite or sanitize forwarded headers rather than
blindly preserving attacker-supplied forwarding information.

### Backend HTTP connection hardening

The Node.js API uses an explicit, validated HTTP server policy instead of
depending on runtime defaults. The default whole-request/header/keep-alive
bounds are 30 seconds, 15 seconds, and 5 seconds respectively, timeout checks
run every 5 seconds, incoming headers are capped at 100, and a keep-alive socket
is recycled after 1000 requests.

The generic Node socket inactivity timeout remains disabled because Socket.IO
shares the HTTP server and owns heartbeat/liveness for its long-lived transports.
Production reverse proxies and load balancers should use compatible outer
timeouts rather than silently overriding these application assumptions.

### Production deployment contract

The provider-neutral backend production process contract is documented in
[`backend/DEPLOYMENT.md`](backend/DEPLOYMENT.md). It defines the supported Node
runtime, start command, readiness/liveness probes, graceful shutdown, trusted
proxy boundary, HTTP connection policy, and the current single-replica realtime
baseline. It intentionally does not select a hosting platform.

### Database recovery contract

The provider-neutral MongoDB backup, isolated restore-verification, and
disaster-recovery safety contract is documented in
[backend/RECOVERY.md](backend/RECOVERY.md).

Production RPO/RTO, retention, backup consistency, encrypted off-host storage,
and provider-specific recovery activation remain deployment acceptance inputs.

### Production telemetry contract

The provider-neutral production telemetry and alerting contract is documented in
[backend/TELEMETRY.md](backend/TELEMETRY.md). Merzox already emits structured JSON
runtime events with server-generated request IDs, HTTP status codes, request
durations, and authoritative `/health` and `/ready` probes.

Real production telemetry activation still requires the selected deployment's log
collector, retention/access controls, dashboards or equivalent queries, alert
rules and responder ownership, plus a non-destructive alert-delivery drill.
Dedicated metrics, distributed tracing, and an external error-reporting SDK remain
separate architecture decisions rather than repository defaults.
