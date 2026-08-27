import crypto from 'node:crypto';

export const COURIER_LOCATION_CAPABILITY_TTL_MS = 12 * 60 * 60 * 1000;

export const courierLocationLimits = Object.freeze({
  tokenBytes: 32,
  maximumAccuracyMeters: 10000,
  maximumPastAgeMs: 15 * 60 * 1000,
  maximumFutureSkewMs: 2 * 60 * 1000
});

export const COURIER_LOCATION_ERRORS = Object.freeze({
  authRequired: 'COURIER_LOCATION_AUTH_REQUIRED',
  capabilityInvalid: 'COURIER_LOCATION_CAPABILITY_INVALID',
  staleSample: 'COURIER_LOCATION_STALE_SAMPLE',
  invalidFields: 'INVALID_COURIER_LOCATION_FIELDS',
  invalidLatitude: 'INVALID_COURIER_LOCATION_LATITUDE',
  invalidLongitude: 'INVALID_COURIER_LOCATION_LONGITUDE',
  invalidAccuracy: 'INVALID_COURIER_LOCATION_ACCURACY',
  invalidCapturedAt: 'INVALID_COURIER_LOCATION_CAPTURED_AT'
});

const courierTokenPattern = /^[A-Za-z0-9_-]{43}$/;
const tokenHashPattern = /^[a-f0-9]{64}$/;

function normalizedDate(value) {
  const date =
    value instanceof Date
      ? new Date(value.getTime())
      : new Date(value);

  return Number.isFinite(date.getTime())
    ? date
    : null;
}

export function isCourierLocationToken(value) {
  return (
    typeof value === 'string' &&
    courierTokenPattern.test(value)
  );
}

export function hashCourierLocationToken(token) {
  if (!isCourierLocationToken(token)) {
    return null;
  }

  return crypto
    .createHash('sha256')
    .update(token, 'utf8')
    .digest('hex');
}

export function courierLocationTokenFromAuthorization(value) {
  if (typeof value !== 'string') {
    return null;
  }

  const match =
    /^Courier ([A-Za-z0-9_-]{43})$/.exec(
      value.trim()
    );

  return match?.[1] ?? null;
}

export function issueCourierLocationCapability({
  now = new Date(),
  randomBytes = crypto.randomBytes
} = {}) {
  const issuedAt = normalizedDate(now);

  if (!issuedAt) {
    throw new TypeError(
      'Courier capability issue time must be a valid date'
    );
  }

  const entropy = randomBytes(
    courierLocationLimits.tokenBytes
  );

  if (
    !Buffer.isBuffer(entropy) ||
    entropy.length !== courierLocationLimits.tokenBytes
  ) {
    throw new TypeError(
      'Courier capability entropy must contain exactly 32 bytes'
    );
  }

  const token = entropy.toString('base64url');
  const tokenHash = hashCourierLocationToken(token);

  if (!tokenHash) {
    throw new TypeError(
      'Courier capability token generation failed'
    );
  }

  return {
    token,
    tokenHash,
    issuedAt,
    expiresAt: new Date(
      issuedAt.getTime() +
        COURIER_LOCATION_CAPABILITY_TTL_MS
    )
  };
}

export function isCourierLocationCapabilityActive(
  capability,
  { now = new Date() } = {}
) {
  const current = normalizedDate(now);
  const expiresAt = normalizedDate(
    capability?.expiresAt
  );

  return Boolean(
    current &&
      typeof capability?.tokenHash === 'string' &&
      tokenHashPattern.test(capability.tokenHash) &&
      !capability?.revokedAt &&
      expiresAt &&
      expiresAt.getTime() > current.getTime()
  );
}

export function isCourierLocationSnapshotVisible(
  {
    status,
    capability,
    location
  },
  { now = new Date() } = {}
) {
  if (
    status !== 'outForDelivery' ||
    !location ||
    !isCourierLocationCapabilityActive(
      capability,
      { now }
    )
  ) {
    return false;
  }

  const current = normalizedDate(now);
  const expiresAt = normalizedDate(
    capability?.expiresAt
  );
  const capturedAt = normalizedDate(
    location.capturedAt
  );
  const receivedAt = normalizedDate(
    location.receivedAt
  );

  if (
    !current ||
    !expiresAt ||
    expiresAt.getTime() <= current.getTime() ||
    !capturedAt ||
    !receivedAt ||
    !Number.isFinite(location.latitude) ||
    location.latitude < -90 ||
    location.latitude > 90 ||
    !Number.isFinite(location.longitude) ||
    location.longitude < -180 ||
    location.longitude > 180
  ) {
    return false;
  }

  const age =
    current.getTime() -
    capturedAt.getTime();

  return (
    age <=
      courierLocationLimits.maximumPastAgeMs &&
    age >=
      -courierLocationLimits.maximumFutureSkewMs
  );
}

export function courierLocationMonotonicFilter(capturedAt) {
  const sample = normalizedDate(capturedAt);

  if (!sample) {
    throw new TypeError(
      'Courier location capturedAt must be a valid date'
    );
  }

  return {
    $or: [
      {
        courierLocation: null
      },
      {
        'courierLocation.capturedAt': {
          $exists: false
        }
      },
      {
        'courierLocation.capturedAt': {
          $lt: sample
        }
      }
    ]
  };
}

export function normalizeCourierLocationPayload(
  body,
  { now = new Date() } = {}
) {
  if (
    !body ||
    typeof body !== 'object' ||
    Array.isArray(body)
  ) {
    return {
      ok: false,
      code: COURIER_LOCATION_ERRORS.invalidFields
    };
  }

  const allowed = new Set([
    'latitude',
    'longitude',
    'accuracy',
    'capturedAt'
  ]);

  const keys = Object.keys(body);

  if (
    keys.some((key) => !allowed.has(key)) ||
    !keys.includes('latitude') ||
    !keys.includes('longitude') ||
    !keys.includes('capturedAt')
  ) {
    return {
      ok: false,
      code: COURIER_LOCATION_ERRORS.invalidFields
    };
  }

  const latitude = body.latitude;

  if (
    typeof latitude !== 'number' ||
    !Number.isFinite(latitude) ||
    latitude < -90 ||
    latitude > 90
  ) {
    return {
      ok: false,
      code: COURIER_LOCATION_ERRORS.invalidLatitude
    };
  }

  const longitude = body.longitude;

  if (
    typeof longitude !== 'number' ||
    !Number.isFinite(longitude) ||
    longitude < -180 ||
    longitude > 180
  ) {
    return {
      ok: false,
      code: COURIER_LOCATION_ERRORS.invalidLongitude
    };
  }

  const accuracy =
    body.accuracy === undefined ||
    body.accuracy === null
      ? null
      : body.accuracy;

  if (
    accuracy !== null &&
    (
      typeof accuracy !== 'number' ||
      !Number.isFinite(accuracy) ||
      accuracy < 0 ||
      accuracy >
        courierLocationLimits.maximumAccuracyMeters
    )
  ) {
    return {
      ok: false,
      code: COURIER_LOCATION_ERRORS.invalidAccuracy
    };
  }

  if (typeof body.capturedAt !== 'string') {
    return {
      ok: false,
      code: COURIER_LOCATION_ERRORS.invalidCapturedAt
    };
  }

  const current = normalizedDate(now);
  const capturedAt = normalizedDate(
    body.capturedAt
  );

  if (!current || !capturedAt) {
    return {
      ok: false,
      code: COURIER_LOCATION_ERRORS.invalidCapturedAt
    };
  }

  const age =
    current.getTime() -
    capturedAt.getTime();

  if (
    age >
      courierLocationLimits.maximumPastAgeMs ||
    age <
      -courierLocationLimits.maximumFutureSkewMs
  ) {
    return {
      ok: false,
      code: COURIER_LOCATION_ERRORS.invalidCapturedAt
    };
  }

  return {
    ok: true,
    value: {
      latitude,
      longitude,
      accuracy,
      capturedAt
    }
  };
}
