import {
  randomUUID
} from 'node:crypto';

import {
  isRequestId,
  logger
} from '../observability/logger.js';

export const REQUEST_ID_HEADER =
  'X-Request-ID';

function requestRoute(req) {
  const route =
    req.route?.path;

  return (
    typeof route === 'string' &&
    route.length > 0
  )
    ? route
    : 'unmatched';
}

export function createRequestContextMiddleware({
  createId = randomUUID,
  log = logger,
  clock = () =>
    process.hrtime.bigint()
} = {}) {
  return function requestContext(
    req,
    res,
    next
  ) {
    const requestId =
      createId();

    if (!isRequestId(requestId)) {
      throw new Error(
        'Request ID generator returned an invalid value'
      );
    }

    req.requestId =
      requestId.toLowerCase();

    res.setHeader(
      REQUEST_ID_HEADER,
      req.requestId
    );

    const startedAt =
      clock();

    let terminalLogWritten =
      false;

    const writeTerminalLog = (
      event,
      level = 'info'
    ) => {
      if (terminalLogWritten) {
        return;
      }

      terminalLogWritten =
        true;

      const endedAt =
        clock();

      const elapsedNs =
        endedAt - startedAt;

      const durationMs =
        Number(elapsedNs) /
        1_000_000;

      log[level](
        event,
        {
          requestId:
            req.requestId,
          method:
            req.method,
          route:
            requestRoute(req),
          statusCode:
            res.statusCode,
          durationMs
        }
      );
    };

    res.once(
      'finish',
      () => {
        writeTerminalLog(
          'http_request_completed'
        );
      }
    );

    res.once(
      'close',
      () => {
        if (!res.writableEnded) {
          writeTerminalLog(
            'http_request_aborted',
            'warn'
          );
        }
      }
    );

    next();
  };
}

export const requestContextMiddleware =
  createRequestContextMiddleware();
