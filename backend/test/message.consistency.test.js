import assert from 'node:assert/strict';
import test from 'node:test';

import {
  messageCompensationLog,
  resolveSendFailure
} from '../src/policies/message-consistency.policy.js';

/**
 * FIX3-B: the message write spans two documents, so the interesting failure is
 * not the summary update failing - it is the compensating delete failing too.
 * At that point an orphaned message exists, and the response must say so.
 */

const SECRET = 'customer-secret-123';

test('a failed compensation never reports the original cause', () => {
  // The original error would imply nothing was written. It no longer holds.
  const original = new Error('summary update failed');
  const failure = resolveSendFailure({
    compensated: false,
    originalError: original
  });

  assert.notEqual(failure, original);
  assert.equal(failure.code, 'MESSAGE_STATE_INCONSISTENT');
  assert.equal(failure.statusCode, 500);
});

test('a failed compensation with no original cause still reports inconsistency', () => {
  const failure = resolveSendFailure({ compensated: false });

  assert.equal(failure.code, 'MESSAGE_STATE_INCONSISTENT');
  assert.equal(failure.statusCode, 500);
});

test('a successful compensation surfaces the original cause', () => {
  const original = new Error('summary update failed');
  const failure = resolveSendFailure({
    compensated: true,
    originalError: original
  });

  assert.equal(failure, original, 'the real cause must not be masked');
});

test('a vanished conversation with clean compensation is a 404', () => {
  const failure = resolveSendFailure({ compensated: true });

  assert.equal(failure.code, 'CONVERSATION_NOT_FOUND');
  assert.equal(failure.statusCode, 404);
});

test('every outcome is an error - success is unreachable from here', () => {
  for (const compensated of [true, false]) {
    for (const originalError of [null, new Error('boom')]) {
      const failure = resolveSendFailure({ compensated, originalError });

      assert.ok(failure instanceof Error, 'must always be an error');

      // An AppError carries its own 4xx/5xx; a plain rethrown cause has no
      // statusCode and the error handler maps it to 500. Either way the
      // request fails, so a 201 is unreachable.
      if (failure.statusCode !== undefined) {
        assert.ok(
          failure.statusCode >= 400,
          `status ${failure.statusCode} must be a failure`
        );
      }
    }
  }

  // The inconsistent case is always an explicit 500, never an inherited status.
  const inconsistent = resolveSendFailure({
    compensated: false,
    originalError: Object.assign(new Error('x'), { statusCode: 404 })
  });
  assert.equal(inconsistent.statusCode, 500);
  assert.equal(inconsistent.code, 'MESSAGE_STATE_INCONSISTENT');
});

test('the compensation log carries no message or customer content', () => {
  const error = new Error(
    `E11000 duplicate key: { body: "${SECRET}", senderName: "${SECRET}" }`
  );
  error.name = 'MongoServerError';
  error.code = 11000;

  const line = messageCompensationLog(error).join(' ');

  assert.equal(line.includes(SECRET), false, line);
  assert.equal(line.includes('duplicate key'), false, line);
  assert.equal(line.includes('[messaging] MESSAGE_COMPENSATION_FAILED'), true);
  assert.equal(line.includes('errorName=MongoServerError'), true);
  assert.equal(line.includes('errorCode=11000'), true);
});

test('the compensation log carries no stack trace', () => {
  const error = new Error('boom');
  error.name = 'TypeError';

  const line = messageCompensationLog(error).join(' ');

  assert.equal(line.includes('at '), false, line);
  assert.equal(line.includes('boom'), false, line);
  assert.equal(line.includes('.js'), false, line);
});

test('an attacker-shaped error cannot widen the compensation log', () => {
  const hostile = new Error('x');
  hostile.name = `Error: ${SECRET}`;
  hostile.code = { toString: () => SECRET };

  const parts = messageCompensationLog(hostile);
  const line = parts.join(' ');

  assert.equal(line.includes(SECRET), false, line);
  assert.equal(parts.length, 3, 'the field set is fixed');
  assert.equal(parts[0], '[messaging] MESSAGE_COMPENSATION_FAILED');
  assert.match(parts[1], /^errorName=[A-Za-z]+$/);
  assert.match(parts[2], /^errorCode=(none|[A-Za-z0-9_]+)$/);
});

test('the compensation log survives a missing error', () => {
  for (const value of [undefined, null, 'not-an-error']) {
    const line = messageCompensationLog(value).join(' ');
    assert.equal(line.includes('errorName=UnknownError'), true, String(value));
    assert.equal(line.includes('errorCode=none'), true, String(value));
  }
});
