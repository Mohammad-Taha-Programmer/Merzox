import assert from 'node:assert/strict';
import http from 'node:http';
import test from 'node:test';

import express from 'express';

import {
  applyProxyTrust
} from '../src/runtime/proxy-trust.js';

async function requestIp({
  app,
  forwardedFor
}) {
  const server =
    http.createServer(
      app
    );

  await new Promise(
    (resolve, reject) => {
      server.once(
        'error',
        reject
      );

      server.listen(
        0,
        '127.0.0.1',
        resolve
      );
    }
  );

  try {
    const {
      port
    } =
      server.address();

    return await new Promise(
      (resolve, reject) => {
        const request =
          http.request(
            {
              host:
                '127.0.0.1',
              port,
              path:
                '/',
              headers: {
                'X-Forwarded-For':
                  forwardedFor
              }
            },
            (response) => {
              let body = '';

              response.setEncoding(
                'utf8'
              );

              response.on(
                'data',
                (chunk) => {
                  body += chunk;
                }
              );

              response.on(
                'end',
                () => {
                  try {
                    resolve(
                      JSON.parse(
                        body
                      )
                    );
                  } catch (error) {
                    reject(error);
                  }
                }
              );
            }
          );

        request.on(
          'error',
          reject
        );

        request.end();
      }
    );
  } finally {
    await new Promise(
      (resolve) =>
        server.close(
          resolve
        )
    );
  }
}

function probeApp(
  ranges
) {
  const app =
    express();

  applyProxyTrust(
    app,
    ranges
  );

  app.get(
    '/',
    (req, res) => {
      res.json({
        ip:
          req.ip,
        ips:
          req.ips
      });
    }
  );

  return app;
}

test(
  'proxy trust is explicitly false when no ranges are configured',
  () => {
    const app =
      probeApp([]);

    assert.equal(
      app.get(
        'trust proxy'
      ),
      false
    );
  }
);

test(
  'untrusted direct requests cannot spoof req.ip with X-Forwarded-For',
  async () => {
    const result =
      await requestIp({
        app:
          probeApp([]),
        forwardedFor:
          '198.51.100.25'
      });

    assert.equal(
      result.ip,
      '127.0.0.1'
    );

    assert.deepEqual(
      result.ips,
      []
    );
  }
);

test(
  'an explicitly trusted direct proxy may supply the client address',
  async () => {
    const result =
      await requestIp({
        app:
          probeApp([
            '127.0.0.1/32'
          ]),
        forwardedFor:
          '198.51.100.25'
      });

    assert.equal(
      result.ip,
      '198.51.100.25'
    );

    assert.deepEqual(
      result.ips,
      [
        '198.51.100.25'
      ]
    );
  }
);

test(
  'trust stops at the first untrusted forwarded hop',
  async () => {
    const result =
      await requestIp({
        app:
          probeApp([
            '127.0.0.1/32'
          ]),
        forwardedFor:
          '198.51.100.25, 10.0.0.7'
      });

    assert.equal(
      result.ip,
      '10.0.0.7'
    );

    assert.deepEqual(
      result.ips,
      [
        '10.0.0.7'
      ]
    );
  }
);

test(
  'proxy adapter refuses malformed runtime input',
  () => {
    assert.throws(
      () =>
        applyProxyTrust(
          null,
          []
        ),
      TypeError
    );

    assert.throws(
      () =>
        applyProxyTrust(
          express(),
          '127.0.0.1'
        ),
      TypeError
    );
  }
);
