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
- `PATCH /api/v1/businesses/me/orders/:orderId/courier`
- `GET /api/v1/businesses/me/conversations?filter=all|unread`
- `GET /api/v1/businesses/me/conversations/unread-count`
- `GET|POST /api/v1/businesses/me/products`
- `PATCH|DELETE /api/v1/businesses/me/products/:productId`
- `PATCH /api/v1/users/me`
- `GET|POST /api/v1/orders`
- `GET /api/v1/orders/:id`
- `PATCH /api/v1/orders/:id/address`
- `PATCH /api/v1/orders/:id/cancel`
- `GET|POST /api/v1/conversations`
- `GET /api/v1/conversations/unread-count`
- `GET|POST /api/v1/conversations/:id/messages`
- `POST /api/v1/conversations/:id/read`
- `GET /api/v1/notifications?audience=customer|business&filter=all|unread`
- `GET /api/v1/notifications/unread-count`
- `POST /api/v1/notifications/:id/read`
- `POST /api/v1/notifications/read-all`
- `GET /health`

The businesses endpoint uses pagination and caps `limit` at 100.

## Integration authorization tests

`backend/test/integration/authorization.matrix.test.js` is a tracked
cross-account authorization matrix. It seeds its own throwaway accounts through
the public API, asserts that every cross-account read and write is refused, and
then deletes exactly the rows it created.

It is opt-in and fails closed. Without all three variables it reports
`INTEGRATION_AUTHZ=SKIPPED` naming the missing prerequisite, and it never falls
back to `MONGODB_URI`:

```dotenv
MERZOX_INTEGRATION_TESTS=true
MERZOX_TEST_API_URL=http://localhost:4100/api/v1
MERZOX_TEST_DB_URI=mongodb://127.0.0.1:27017/merzox_test
```

The API served at `MERZOX_TEST_API_URL` must be running against
`MERZOX_TEST_DB_URI`. The harness refuses to run unless the **database name**
contains `test` or `integration` - a hostname is not accepted as proof, and a
URI identical to `MONGODB_URI` is rejected outright. Cleanup is scoped to the
user ids the run created; no collection is ever dropped.

## Messaging

A conversation is unique per customer and business. `POST /api/v1/conversations`
returns the existing thread when one is already open, so a store page can link
straight into a chat without checking first. Access is resolved per request: the
customer who owns the thread and the owner of its business can read and write to
it, and everyone else receives a 404.

## Order tracking

`toClientJSON` and `toMerchantJSON` both carry a `tracking` object that collapses
the six stored statuses onto the four steps the design draws (`placed`,
`preparing`, `outForDelivery`, `delivered`), along with `canCancel`,
`canChangeAddress`, and `canReview` flags. The delivery address can be changed
only while the order is `pending` or `confirmed`; a courier can be assigned from
`confirmed` through `outForDelivery`.

## Notifications

Notifications are written as a side effect of orders, status changes, messages,
and reviews. Delivery is best-effort: a failed notification write never fails the
request that triggered it. Each record carries a `type` and a `data` payload so a
client can localize the copy and deep-link to the order or conversation, with a
server-rendered Arabic `title`/`body` as a fallback.

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
