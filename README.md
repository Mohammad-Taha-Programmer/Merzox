# Merzox

<p align="center">
  <img src="assets/images/MERZOX_LOGO.png" alt="Merzox logo" width="150">
</p>

Merzox is a bilingual, neighborhood-focused e-commerce application that connects
customers with nearby businesses, their products, and their services. The mobile
client is built with Flutter for Android and iOS, while the API uses Node.js,
Express, MongoDB, and Mongoose.

The project is under active development. Arabic is the default language and the
interface also supports English, including automatic RTL/LTR layout changes.

## Current Features

### Customer experience

- Custom splash screen and three-step onboarding flow.
- Sign up and login with either an email address or an international phone number.
- Email verification before an email-based account is persisted.
- Guest browsing with purchasing and account changes restricted to authenticated users.
- Home feed for new, highly rated, discounted, and nearby businesses.
- Paginated all-businesses catalog with advertisement sliders.
- Search for products, services, and businesses, with local search history.
- Business profiles with information, products, services, ratings, and reviews.
- Product details with image galleries, variants, quantities, ratings, favorites,
  cart actions, and direct-purchase entry points.
- Persistent cart and authenticated checkout flow.
- Order history grouped into current, completed, and cancelled orders.
- Favorites for businesses, products, and services.
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

### Application foundations

- BLoC-based state management for application workflows.
- Arabic and English localization with RTL/LTR support.
- Runtime location permission handling.
- Responsive Android and iOS UI based on the supplied Adobe XD designs.
- Secure local session persistence and configurable API endpoints.

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

The health endpoint is available at `http://localhost:3000/health`. More backend
details and endpoint documentation are in [backend/README.md](backend/README.md).

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

These controls reduce common risks but do not replace a professional security
review, production secret management, monitoring, backups, or dependency audits.

## Roadmap

- Production-ready real-time chat between customers and businesses.
- Payment processing for cards, cash, bank transfers, and purchases for others.
- Rich delivery tracking and notifications.
- Consent-based recommendation and preference analysis.
- Production deployment, observability, automated CI, and store publication.

## Project Status

Merzox is currently a development-stage product. Store identifiers, payment
credentials, production SMTP credentials, deployment URLs, privacy documents,
and final legal content must be supplied before public release.
