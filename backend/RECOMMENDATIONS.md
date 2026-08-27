# Merzox Recommendation Contract

This is the engineering contract for the current recommendation feature. It does
not replace final production privacy-policy, terms, or legal review.

## Consent authority

`GET /api/v1/users/me/recommendations` requires authentication.

Recommendation processing is authorized only when both facts are true:

- `permissions.aiPersonalization === true`
- `permissionConsents.aiPersonalization.status === "granted"`

Missing, malformed, `notAsked`, denied, or contradictory states fail closed.
The backend checks consent before reading recommendation signals or candidates.
Flutter also verifies the authoritative user projection before calling the
recommendation endpoint.

## Inputs and bounds

Only existing first-party server records are used:

- business favorite: weight `3`
- product favorite: weight `2`, mapped through its business
- delivered order: weight `4`

Only delivered orders contribute.

The service reads at most:

- 200 recent favorites
- 200 recent delivered orders
- 8 derived preference categories

The derived profile is computed on demand and is not persisted.

## Data not used

Recommendations do not consume:

- device-local search history
- page views
- clicks or clickstream analytics
- contacts
- device location
- message content
- notification activity

No passive behavioral tracking is introduced by this feature.

## Ranking

Only active businesses are candidates. A business owned by the requesting user
is excluded.

Category affinity ranks first. Deterministic tie-breakers are rating average,
rating count, subscription date, then business id.

The response contains at most 12 businesses.

With granted consent but no usable preference signals, category affinity is zero
and the deterministic generic ranking is used. The response reports
`personalized: false`.

## Response minimization

The client receives the consent view, the `personalized` flag, ordered category
names, and normal business list projections.

It does not receive raw favorites, raw orders, affinity scores, interaction
counts, or a stored preference profile.

## Revocation and Flutter lifecycle

The personalization switch remains server-authoritative. Flutter does not treat
a requested toggle value as confirmed until the server returns the updated user
projection.

Home clears existing recommendations before every consent revalidation. A
server-confirmed opt-out therefore removes stale recommendations and closes the
section.

The recommendation result and derived preference profile are not persisted on
the device.

## Non-goals

This baseline does not use machine learning, external AI/recommendation
providers, vector databases, collaborative filtering, background preference
jobs, or passive behavioral telemetry.

Any future expansion of recommendation signals requires separate consent and
privacy review.
