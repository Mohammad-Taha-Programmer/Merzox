# Merzox Backend

Node.js, Express, and MongoDB API for the current Merzox app flow.

## Setup

```bash
cd backend
npm install
copy .env.example .env
npm run seed
npm run dev
```

Default API base URL:

```text
http://localhost:3000/api/v1
```

Flutter can point to another host with:

```bash
flutter run --dart-define=MERZOX_API_BASE_URL=http://localhost:3000/api/v1
```

## Main Endpoints

- `POST /api/v1/auth/signup`
- `POST /api/v1/auth/login`
- `GET /api/v1/auth/me`
- `POST /api/v1/auth/logout`
- `GET /api/v1/businesses?page=1&limit=100&search=`
- `GET /api/v1/businesses/:id`
- `POST /api/v1/businesses/enroll` (authenticated normal user)
- `GET|PATCH /api/v1/businesses/me` (business owner)
- `GET /api/v1/businesses/me/dashboard`
- `GET /api/v1/businesses/me/orders?statusGroup=current`
- `PATCH /api/v1/businesses/me/orders/:orderId/status`
- `GET|POST /api/v1/businesses/me/products`
- `PATCH|DELETE /api/v1/businesses/me/products/:productId`
- `PATCH /api/v1/users/me`
- `GET /health`

The businesses endpoint uses pagination and caps `limit` at 100.

## Business enrollment

All accounts are created as normal users. A logged-in normal user can upgrade the
same account with `POST /api/v1/businesses/enroll`:

```json
{
  "phone": "+972590000001",
  "email": "user@example.com",
  "currentPassword": "Password123",
  "name": "اسم المتجر",
  "englishName": "Store Name",
  "description": "Store description",
  "category": "Groceries",
  "address": "Ramallah",
  "attachmentUrl": "https://files.example.com/registration.pdf"
}
```

If the original account has only a phone number, enrollment adds the supplied
email as unverified; phone login remains available. If the account already has
an email or phone, the enrollment values must match it. Enrollment creates one
owned business and changes the user's `userType` to `business`. The client should
then clear the old session and show the business login screen.

Products are soft-deleted so historical orders remain intact. Owner order status
changes must follow `pending -> confirmed -> preparing -> outForDelivery -> delivered`;
the owner may cancel before delivery where the API permits it.
