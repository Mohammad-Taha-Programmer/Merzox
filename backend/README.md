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
- `GET /api/v1/users/me/recommendations`
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
- `GET /ready`

The businesses endpoint uses pagination and caps `limit` at 100.

## Consent-based recommendations

`GET /api/v1/users/me/recommendations` is authenticated and fails closed unless
both `permissions.aiPersonalization` is `true` and
`permissionConsents.aiPersonalization.status` is `granted`.

The service computes an ephemeral deterministic category profile from existing
server-side favorites and delivered orders. It does not consume local search
history, page views, clicks, contacts, or location, and it does not persist the
derived profile.

Candidates are active businesses and exclude a business owned by the requesting
user. Raw favorites, orders, interaction counts, and internal affinity scores are
not returned.

See [`RECOMMENDATIONS.md`](RECOMMENDATIONS.md) for the complete engineering
contract.

## Payment capability

`POST /api/v1/orders` recognizes the historical payment-method vocabulary
`cash`, `card`, `bankTransfer`, and `assisted`.

Recognition and operational capability are intentionally separate:

- `cash` is currently the only operational method.
- `card`, `bankTransfer`, and `assisted` fail closed with HTTP `409` and
  application code `PAYMENT_METHOD_UNAVAILABLE`.
- Unknown or malformed payment values fail with HTTP `400` and
  `INVALID_PAYMENT_METHOD`.
- Payment capability is checked by `validateOrderCreate` before `createOrder`
  runs. Therefore a known-but-unavailable method cannot create a checkout
  intent, consume a reservation, mutate inventory, or create an order.
- The persisted `Order.paymentMethod` vocabulary remains backward-compatible;
  historical values are not rewritten merely because they are not operational
  today.

There is currently no configured payment gateway, provider SDK, merchant
credential, provider webhook, capture operation, monetary refund operation, or
provider payment state machine. Future payment-provider work must plug into an
explicit payment lifecycle rather than bypassing checkout/inventory consistency
controls.


## Operational probes

`GET /health` is a liveness probe. It confirms that the Node.js process can
serve HTTP and intentionally does not depend on MongoDB.

`GET /ready` is a readiness probe. It fails closed with HTTP `503` until the
server bootstrap has connected to MongoDB and started accepting traffic. Once
both conditions are true it returns HTTP `200`. If MongoDB is no longer
connected, readiness returns to `503` while liveness can remain healthy.

## Graceful shutdown

The production runtime handles both `SIGTERM` and `SIGINT`. Shutdown is
idempotent: the first signal withdraws readiness immediately, stops the checkout
reconciler timer, closes the Firebase push sender, closes Socket.IO and the HTTP
server, and finally disconnects MongoDB. A repeated signal reuses the same
shutdown operation instead of closing resources twice.

Cleanup continues through every resource even when one close operation fails.
Normal signal handling does not call `process.exit()`; after runtime handles are
closed Node exits naturally. Cleanup failure sets a non-zero process exit code.

## Request correlation and operational logs

Every HTTP request receives a Merzox-generated `X-Request-ID` response header.
Inbound request IDs are not trusted or reused. For browser clients,
`X-Request-ID` is exposed through CORS.

HTTP completion/error events and server lifecycle events are written as one-line
JSON records. The logger accepts only bounded operational fields such as request
ID, HTTP method, route template, status code, duration, application error code
and sanitized error class/code.

The operational logger intentionally does **not** accept request bodies, raw
URLs/query strings, Authorization/Cookie headers, customer identity fields,
message content, tokens, or raw Error message/stack data.

Server-runtime diagnostics also use this structured logger; runtime source does
not emit directly through `console.*`. Human-facing maintenance scripts under
`backend/src/scripts/` remain a separate CLI surface and are not treated as
server observability.

When SMTP is unavailable, verification and password-reset delivery failures are
logged only as fixed operational events. Recipient addresses, verification
links, reset tokens and provider error messages are never written by the server
runtime logger.

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

The API served at `MERZOX_TEST_API_URL` must itself be started with
`MONGODB_URI` pointing at `MERZOX_TEST_DB_URI`:

```powershell
cd backend
$env:MONGODB_URI = "mongodb://127.0.0.1:27017/merzox_test"
npm.cmd start
```

The harness cannot verify which database a running server is serving, so it
accepts only a **loopback** `MERZOX_TEST_API_URL` (`localhost`, `127.0.0.1`,
`::1`). A remote or production-looking API URL, a non-http scheme, an embedded
credential, or a malformed URL is refused. Pairing a local test database with a
remote API would create fixtures in production and clean only the local one. The harness refuses to run unless the **database name**
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

## Development CLI safety

The seed and SMTP diagnostic scripts remain human-facing CLI utilities rather
than server observability processes.

Both commands fail closed when `NODE_ENV=production`.

Outside production, destructive seeding requires the exact opt-in
`MERZOX_ALLOW_DESTRUCTIVE_SEED=true`. The guard is evaluated before the seed
connects to MongoDB.

Outside production, SMTP diagnostics require the exact opt-in
`MERZOX_ALLOW_EMAIL_DIAGNOSTIC=true`.

Neither opt-in overrides the production refusal. CLI failure output is bounded
to safe error class/code information and does not print raw provider responses,
raw error messages, stack traces, recipients, tokens, or verification URLs.

## Production environment contract

Runtime configuration is parsed through a pure, testable environment resolver
before the server connects to MongoDB or begins listening.

Supported `NODE_ENV` values are exactly `development`, `test`, and
`production`.

Production additionally requires:

- a `JWT_SECRET` of at least 32 characters;
- an explicit HTTPS `PUBLIC_BASE_URL`;
- complete SMTP host/user/password/from configuration;
- only exact HTTPS CORS origins when browser origins are configured.

An empty production CORS list remains valid and denies browser-origin requests;
it is not widened automatically. Wildcard CORS entries remain available for
local development only.

`PORT` and `SMTP_PORT` are bounded to valid TCP port numbers. Rate-limit
window/max values must be positive safe integers. Boolean environment flags
accept only literal `true` or `false`.

Environment validation errors use bounded error codes and never include secret
values.

## Reverse-proxy trust

Express `trust proxy` is explicitly `false` when `TRUST_PROXY_RANGES` is empty.

For deployments behind a reverse proxy/load balancer, set
`TRUST_PROXY_RANGES` to a comma-separated allowlist of the exact proxy source
IP addresses or CIDR ranges that can connect to the Node.js process.

Examples of accepted shapes are an exact IPv4/IPv6 address or a CIDR such as
`10.20.30.0/24`. Hostnames, booleans and numeric hop counts are not accepted.

This matters because the global and password-recovery rate limiters use
Express's `req.ip`. Trusting arbitrary forwarded headers would allow spoofed
client identities, while leaving proxy trust disabled behind a shared proxy
would collapse many users onto the proxy's source address.

The reverse proxy must overwrite/sanitize forwarded headers at the ingress
boundary. Only networks that are actually controlled as Merzox proxy ingress
should appear in the allowlist.

### HTTP parser and connection policy

Merzox does not rely on changing Node.js HTTP defaults for production behavior.
The HTTP server is created through a dedicated policy and the values can be
overridden only with validated positive integers:

- `HTTP_REQUEST_TIMEOUT_MS` defaults to `30000`.
- `HTTP_HEADERS_TIMEOUT_MS` defaults to `15000` and cannot exceed the whole
  request timeout.
- `HTTP_KEEP_ALIVE_TIMEOUT_MS` defaults to `5000`.
- `HTTP_CONNECTIONS_CHECKING_INTERVAL_MS` defaults to `5000` and cannot exceed
  the headers timeout.
- `HTTP_MAX_HEADERS_COUNT` defaults to `100`.
- `HTTP_MAX_REQUESTS_PER_SOCKET` defaults to `1000`.

`server.timeout` intentionally remains `0`. Socket.IO shares the same Node HTTP
server and manages liveness for its polling/WebSocket transports through its own
heartbeat. Ordinary incomplete HTTP requests remain bounded by the request and
header timers above.

The application request body remains independently capped at `32kb`; these HTTP
connection limits do not replace route-level validation or ingress/load-balancer
timeouts.

## Production deployment contract

See [`DEPLOYMENT.md`](DEPLOYMENT.md) for the provider-neutral production
process contract. Production backup/restore and disaster-recovery procedures
remain a separate required operations gate.

## Database recovery contract

See [RECOVERY.md](RECOVERY.md) for the provider-neutral MongoDB backup,
isolated restore-verification, and disaster-recovery safety contract.

The repository defines the safety boundaries, while production RPO/RTO,
retention, backup consistency, storage/encryption ownership, and the real
provider recovery mechanism remain deployment acceptance inputs.

## Production telemetry contract

See [TELEMETRY.md](TELEMETRY.md) for the provider-neutral production telemetry and
alerting contract. The existing structured logger, request correlation,
`http_request_completed` / `http_request_aborted` / `http_request_error` events,
and `/health` / `/ready` probes form the application-owned telemetry baseline.

Production activation must provide real collection, retention/access control,
dashboard or query visibility, alert rules, responder ownership, and an exercised
non-destructive alert-delivery path. A metrics endpoint, distributed tracing, or
external error-reporting SDK is not required by the current repository baseline.
