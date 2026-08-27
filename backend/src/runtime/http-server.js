import { createServer } from 'node:http';

export function createConfiguredHttpServer(
  requestListener,
  {
    requestTimeoutMs,
    headersTimeoutMs,
    keepAliveTimeoutMs,
    connectionsCheckingIntervalMs,
    maxHeadersCount,
    maxRequestsPerSocket
  }
) {
  const server =
    createServer(
      {
        requestTimeout:
          requestTimeoutMs,
        headersTimeout:
          headersTimeoutMs,
        keepAliveTimeout:
          keepAliveTimeoutMs,
        connectionsCheckingInterval:
          connectionsCheckingIntervalMs
      },
      requestListener
    );

  server.maxHeadersCount =
    maxHeadersCount;

  server.maxRequestsPerSocket =
    maxRequestsPerSocket;

  // Deliberately preserve Node's generic inactivity timeout at zero.
  // Socket.IO is attached to this same HTTP server and owns heartbeat/liveness
  // for upgraded and long-polling transports. Request/header bounds above still
  // protect incomplete ordinary HTTP requests.
  server.timeout = 0;

  return server;
}
