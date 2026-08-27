# Merzox Production Telemetry Contract

This document defines the provider-neutral telemetry and alerting contract for the Merzox backend.

It does not select a logging vendor, metrics backend, tracing platform, error-reporting SDK, pager, or hosting provider. It also does not claim that production telemetry is active merely because the repository emits structured operational events.

## Existing application signals

The backend already provides these application-owned signals:

- one-line structured JSON runtime logs written to stdout/stderr;
- server-generated request IDs returned as `X-Request-ID`;
- `http_request_completed` records with request ID, method, bounded route, HTTP status code, and request duration;
- `http_request_aborted` warning records for requests that close before completion;
- `http_request_error` warning/error records with bounded operational error fields and no raw message or stack;
- fixed structured runtime events for startup, graceful-shutdown failures, push delivery/provider failures, notification failures, email fallback, checkout reconciliation failures, and messaging compensation failures;
- `GET /health` for process liveness;
- `GET /ready` for fail-closed deployment readiness.

These signals are the repository baseline. A deployment may derive operational metrics from them without changing application code.

## Production telemetry acceptance inputs

Before production launch, the deployment owner must explicitly record:

- the selected log collection and retention mechanism;
- log retention duration and access-control owner;
- the production dashboards or equivalent operational views;
- the alert delivery path and responsible responder;
- the deployment-specific alert thresholds;
- the accepted availability and latency objectives, if business owners define them;
- whether a dedicated metrics backend is required;
- whether distributed tracing is required;
- whether an external error-reporting service is required;
- the evidence used to prove that alerts reach the responsible responder.

The repository deliberately does not invent SLOs, latency thresholds, error-rate thresholds, pager destinations, or retention durations.

## Required operational signals

Production observability must make the following conditions visible from application logs, platform signals, or an explicitly selected telemetry backend:

- HTTP request volume;
- HTTP status distribution, including 5xx failures;
- request latency distribution using the emitted `durationMs` field;
- aborted HTTP requests;
- repeated or sustained `/ready` failures;
- process starts, exits, restarts, and graceful-shutdown failures;
- database unavailability as reflected by readiness;
- push provider initialization and delivery failures;
- notification delivery failures;
- email delivery fallback/failure events;
- checkout reconciliation or compensation failures;
- messaging compensation failures.

An operator must be able to correlate an HTTP failure with the server-generated request ID when that request reached the application.

## Alerting boundary

A production deployment must define alerts for conditions whose persistence or rate can threaten availability, data consistency, or delivery of important background work.

At minimum, the alert plan must consider:

- sustained readiness failure;
- elevated HTTP 5xx rate;
- latency degradation;
- repeated process restarts or crash loops;
- repeated graceful-shutdown failures;
- repeated checkout reconciliation or compensation failures;
- sustained push, notification, or email delivery failures when those channels are active.

Thresholds must be selected from real deployment capacity, traffic, and business requirements. Repository defaults must not silently become production SLOs.

An alert is not accepted until its delivery path has been exercised with a non-destructive test and evidence records the time, alert identity, destination class, and responder acknowledgement. Evidence must not contain customer content, tokens, credentials, raw provider errors, or secrets.

## Logging and privacy boundary

Production collection must preserve the repository's structured JSON records and must not enrich them with request bodies, authorization headers, cookies, push targets, verification URLs, email recipients, customer content, raw database URIs, raw provider responses, stack traces, or unbounded error messages.

Log aggregation access must be restricted to authorized operators. Retention and deletion must follow the deployment's approved operational and privacy policy.

## Metrics decision

A dedicated in-process metrics library and `/metrics` endpoint are not required by the current repository baseline.

The deployment may derive request counts, status distributions, latency, and event counts from the existing structured logs and platform runtime metrics. If the selected production platform cannot support the accepted dashboards or alerts from those signals, adding a metrics library becomes a separate reviewed architecture change.

No Prometheus-compatible endpoint should be added merely to satisfy this contract without a real scraper, retention backend, and access-control design.

## Distributed tracing decision

Distributed tracing is not required by the current single-backend-replica baseline.

If future architecture introduces multiple backend services, queues, workers, or other request hops where request IDs are insufficient, OpenTelemetry or another tracing mechanism may be proposed as a separate reviewed architecture change.

The repository must not accept inbound trace identity as trusted application identity.

## External error-reporting decision

An external error-reporting SDK is optional, not a requirement of this gate.

If one is selected later, it must preserve the existing safe-error boundary, avoid customer content and secrets, document data residency and retention, and prove that SDK failure cannot break an authoritative Merzox request or background operation.

## Health-probe telemetry boundary

`GET /health` and `GET /ready` remain authoritative health interfaces.

The deployment may monitor their status and latency, but probe traffic must not be reinterpreted as customer traffic. Alerting must distinguish process liveness from deployment readiness.

## Production activation evidence

Before Merzox is considered telemetry-ready in a real deployment, acceptance evidence must include:

- the production log collector or equivalent platform facility;
- proof that structured JSON fields remain queryable;
- proof that request ID, status code, and duration are usable in investigation;
- dashboard or query evidence for the required operational signals;
- the approved alert rules and responsible responder;
- one non-destructive alert-delivery drill;
- configured retention and access controls;
- the selected SLO/SLI values, if they have been defined by the responsible business/operator owners.

Until that evidence exists for the real deployment, Merzox has a telemetry contract but not an activated production telemetry service.
