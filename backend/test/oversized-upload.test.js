import assert from 'node:assert/strict';
import test from 'node:test';

import { errorHandler } from '../src/middleware/errorHandler.js';

/// What a reader is told when their picture is too big.
///
/// body-parser refuses an oversized body before any route runs, and its error
/// carried no code of ours - so it reached the screen as "an unexpected error,
/// try again". Both halves of that are wrong: it is not unexpected, and trying
/// again with the same photo does the same thing. The one action available is
/// to send a smaller picture, and nothing said so.

function capture() {
  const sent = { status: 0, body: null };

  return {
    res: {
      status(code) {
        sent.status = code;
        return this;
      },
      json(payload) {
        sent.body = payload;
        return this;
      }
    },
    sent
  };
}

const request = { requestId: 'r1', method: 'POST', originalUrl: '/x' };

test('an oversized body is named, not called unexpected', () => {
  const { res, sent } = capture();
  const tooLarge = Object.assign(new Error('request entity too large'), {
    type: 'entity.too.large',
    statusCode: 413
  });

  errorHandler(tooLarge, request, res, () => {});

  assert.equal(sent.status, 413);
  assert.equal(sent.body.error.code, 'PAYLOAD_TOO_LARGE');
});

test('a 413 with no type is still recognised', () => {
  const { res, sent } = capture();

  errorHandler(
    Object.assign(new Error('too big'), { statusCode: 413 }),
    request,
    res,
    () => {}
  );

  assert.equal(sent.body.error.code, 'PAYLOAD_TOO_LARGE');
});

test('the message reaches the reader rather than being swallowed', () => {
  // AppError marks its own messages as safe to show; a raw framework error
  // would be replaced by "Internal server error" and say nothing.
  const { res, sent } = capture();

  errorHandler(
    Object.assign(new Error('request entity too large'), {
      type: 'entity.too.large'
    }),
    request,
    res,
    () => {}
  );

  assert.match(sent.body.error.message, /too large/i);
});

test('an ordinary failure is still an internal error', () => {
  const { res, sent } = capture();

  errorHandler(new Error('something else'), request, res, () => {});

  assert.equal(sent.status, 500);
  assert.equal(sent.body.error.code, 'INTERNAL_ERROR');
});
