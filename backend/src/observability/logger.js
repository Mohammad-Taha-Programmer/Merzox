const SERVICE_NAME = 'merzox-api';

const LEVELS = new Set([
  'info',
  'warn',
  'error'
]);

const EVENT_PATTERN =
  /^[a-z][a-z0-9_]{0,63}$/;

const REQUEST_ID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const METHOD_PATTERN =
  /^[A-Z]{1,12}$/;

const ROUTE_PATTERN =
  /^[A-Za-z0-9_/:.*?+-]{1,160}$/;

const APP_CODE_PATTERN =
  /^[A-Z][A-Z0-9_]{0,63}$/;

const ERROR_NAME_PATTERN =
  /^[A-Za-z]{1,40}$/;

const ERROR_CODE_PATTERN =
  /^[A-Za-z0-9_]{1,40}$/;

function finiteNumber(
  value,
  {
    min,
    max
  }
) {
  if (
    typeof value !== 'number' ||
    !Number.isFinite(value) ||
    value < min ||
    value > max
  ) {
    return null;
  }

  return value;
}

function boundedToken(
  value,
  pattern
) {
  return (
    typeof value === 'string' &&
    pattern.test(value)
  )
    ? value
    : null;
}

export function isRequestId(value) {
  return (
    boundedToken(
      value,
      REQUEST_ID_PATTERN
    ) !== null
  );
}

export function sanitizeLogFields(
  fields = {}
) {
  const output = {};

  const requestId =
    boundedToken(
      fields.requestId,
      REQUEST_ID_PATTERN
    );

  if (requestId !== null) {
    output.requestId =
      requestId.toLowerCase();
  }

  const method =
    boundedToken(
      fields.method,
      METHOD_PATTERN
    );

  if (method !== null) {
    output.method = method;
  }

  const route =
    boundedToken(
      fields.route,
      ROUTE_PATTERN
    );

  if (route !== null) {
    output.route = route;
  }

  const statusCode =
    finiteNumber(
      fields.statusCode,
      {
        min: 100,
        max: 599
      }
    );

  if (
    statusCode !== null &&
    Number.isInteger(statusCode)
  ) {
    output.statusCode =
      statusCode;
  }

  const durationMs =
    finiteNumber(
      fields.durationMs,
      {
        min: 0,
        max: 86_400_000
      }
    );

  if (durationMs !== null) {
    output.durationMs =
      Math.round(
        durationMs * 1000
      ) / 1000;
  }

  const port =
    finiteNumber(
      fields.port,
      {
        min: 1,
        max: 65535
      }
    );

  if (
    port !== null &&
    Number.isInteger(port)
  ) {
    output.port = port;
  }

  const appCode =
    boundedToken(
      fields.appCode,
      APP_CODE_PATTERN
    );

  if (appCode !== null) {
    output.appCode =
      appCode;
  }

  const errorName =
    boundedToken(
      fields.errorName,
      ERROR_NAME_PATTERN
    );

  if (errorName !== null) {
    output.errorName =
      errorName;
  }

  const errorCode =
    fields.errorCode;

  if (
    typeof errorCode === 'number' &&
    Number.isFinite(errorCode)
  ) {
    output.errorCode =
      errorCode;
  } else {
    const safeErrorCode =
      boundedToken(
        errorCode,
        ERROR_CODE_PATTERN
      );

    if (safeErrorCode !== null) {
      output.errorCode =
        safeErrorCode;
    }
  }

  return output;
}

export function buildLogRecord({
  level,
  event,
  fields = {},
  timestamp = new Date()
}) {
  if (!LEVELS.has(level)) {
    throw new TypeError(
      'Unsupported log level'
    );
  }

  if (
    typeof event !== 'string' ||
    !EVENT_PATTERN.test(event)
  ) {
    throw new TypeError(
      'Invalid log event'
    );
  }

  if (
    !(timestamp instanceof Date) ||
    Number.isNaN(
      timestamp.getTime()
    )
  ) {
    throw new TypeError(
      'Invalid log timestamp'
    );
  }

  return {
    timestamp:
      timestamp.toISOString(),
    level,
    event,
    service: SERVICE_NAME,
    ...sanitizeLogFields(fields)
  };
}

export function createStructuredLogger({
  stdout = process.stdout,
  stderr = process.stderr,
  now = () => new Date(),
  enabled =
    process.env.NODE_ENV !== 'test'
} = {}) {
  function write(
    level,
    event,
    fields
  ) {
    if (!enabled) {
      return;
    }

    const record =
      buildLogRecord({
        level,
        event,
        fields,
        timestamp: now()
      });

    const line =
      `${JSON.stringify(record)}\n`;

    const stream =
      level === 'info'
        ? stdout
        : stderr;

    stream.write(line);
  }

  return Object.freeze({
    info(event, fields = {}) {
      write(
        'info',
        event,
        fields
      );
    },

    warn(event, fields = {}) {
      write(
        'warn',
        event,
        fields
      );
    },

    error(event, fields = {}) {
      write(
        'error',
        event,
        fields
      );
    }
  });
}

export const logger =
  createStructuredLogger();
