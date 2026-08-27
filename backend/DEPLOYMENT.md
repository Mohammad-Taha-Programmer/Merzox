# Merzox Backend Production Deployment Contract

This document defines the provider-neutral production process contract for the
Merzox backend. It does not select a cloud provider, container runtime, reverse
proxy product, process manager, or deployment vendor.

## Supported Node.js runtime

Production deployments must run a Node.js version satisfying:

`>=24.0.0 <25.0.0`

The repository CI currently validates the backend on Node.js 24. The production
runtime must remain on Node.js major version 24 until a separately reviewed
change updates both the repository contract and CI.

## Installation and start command

Run the backend from the `backend/` directory.

Install the exact locked dependency graph:

```bash
npm ci --omit=dev
```

Start the authoritative API process with:

```bash
npm start
```

The canonical start command is `node src/server.js`. A deployment platform
must not replace this with a development watcher or alternate entry point.

## Production environment

Production configuration must be injected by the deployment environment or its
secret-management mechanism. Production secrets must not be committed to this
repository.

At minimum the runtime contract includes:

- `NODE_ENV=production`
- `PORT`
- `MONGODB_URI`
- `JWT_SECRET`
- `PUBLIC_BASE_URL`
- complete `SMTP_*` delivery configuration
- `CORS_ORIGINS`
- `RATE_LIMIT_WINDOW_MS`
- `RATE_LIMIT_MAX`
- `TRUST_PROXY_RANGES` when a trusted reverse proxy exists
- the bounded HTTP timeout/header/socket settings documented in
  `.env.example`

`PUBLIC_BASE_URL` and production CORS origins must follow the fail-closed HTTPS
rules enforced by the environment resolver.

Firebase push remains independently opt-in and must satisfy its existing
production activation guard.

## Liveness and readiness

The backend exposes two distinct operational probes:

- `GET /health` is process liveness.
- `GET /ready` is deployment readiness.

A deployment must send application traffic only after `/ready` returns HTTP
200.

A process may remain live while `/ready` returns HTTP 503, including while
MongoDB is unavailable or during shutdown.

The deployment must not reinterpret `/health` as database readiness.

## Graceful shutdown

The production supervisor or orchestration layer must terminate the Node process
with `SIGTERM` for normal replacement or shutdown.

The application withdraws readiness before closing its owned resources. The
shutdown operation is idempotent and closes the checkout reconciler, push
provider, Socket.IO transport, HTTP server, and MongoDB connection.

The supervisor must allow graceful shutdown to complete instead of immediately
forcing process termination.

`SIGINT` uses the same application shutdown contract for local/operator
termination.

## Reverse proxy and TLS boundary

TLS may terminate outside the Node.js process, but the external deployment must
provide HTTPS to public clients.

Proxy forwarding is trusted only for explicit IP/CIDR entries configured in
`TRUST_PROXY_RANGES`.

If no trusted reverse proxy is present, proxy trust must remain disabled.

A deployment must not enable Express `trust proxy=true`, numeric hop-count
trust, or broad implicit private-network trust.

## HTTP connection policy

The Node HTTP server uses the bounded request, header, keep-alive, header-count,
request-per-socket, and connection-checking policy defined by this repository.

The generic Node socket inactivity timeout intentionally remains disabled
because Socket.IO shares the HTTP server and owns heartbeat/liveness for its
long-lived transports.

## Realtime topology baseline

The current Socket.IO server has no repository-configured shared cross-process
adapter.

Therefore one backend Node process / one backend application replica is the
accepted production baseline for realtime delivery.

A multi-replica backend requires a separate architecture change that defines and
tests cross-replica Socket.IO delivery, connection routing, failure behavior,
and shutdown semantics before horizontal scaling is enabled.

This restriction applies to the current realtime transport architecture. It is
not a claim that MongoDB or ordinary HTTP handlers inherently require one
replica.

## Logs

Runtime diagnostics use the repository structured logger and server-generated
request correlation IDs.

Deployment log collection must preserve stdout/stderr without transforming
structured records into secret-bearing diagnostic dumps.

CLI tools remain human-facing and are not the runtime logging interface.

## Deployment artifact status

This contract deliberately does not add a Dockerfile, Procfile, PM2 definition,
systemd unit, Kubernetes manifest, or provider-specific descriptor.

Selecting one of those mechanisms is a separate decision that must preserve this
runtime contract.

## Database recovery contract

The provider-neutral backup, retention, restore verification, RPO/RTO, and
disaster-recovery safety contract is documented in
[RECOVERY.md](RECOVERY.md).

Provider-specific recovery activation still requires the real deployment's
selected consistency mechanism, storage, encryption/key ownership, retention,
RPO/RTO, and successful isolated restore-drill evidence. That activation remains
a separate required production-operations gate before Merzox is considered
production-ready.

## Store-release boundary

Android/iOS permanent application identifiers, signing credentials, Firebase
platform registration, and store publication remain outside this backend
deployment contract.

## Production telemetry contract

The application-side telemetry contract is defined in
[TELEMETRY.md](TELEMETRY.md). Deployment log collection must preserve the existing
structured JSON records and their bounded request ID, HTTP status, duration, and
operational-event fields without enriching them with customer content or secrets.

The real deployment must define log retention and access control, operational
dashboards or equivalent queries, alert thresholds and responder ownership, and
must exercise a non-destructive alert-delivery drill before telemetry is treated
as activated. Repository defaults do not invent production SLOs or alert
thresholds.

The current single-backend-replica baseline does not require a dedicated metrics
endpoint, distributed tracing, or an external error-reporting SDK. If the selected
platform cannot satisfy the accepted telemetry contract from structured logs and
platform signals, adding one of those mechanisms becomes a separately reviewed
architecture change.
