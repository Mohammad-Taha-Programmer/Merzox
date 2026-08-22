import assert from 'node:assert/strict';
import test from 'node:test';

import {
  notificationFailureLog,
  notificationLogSanitizers
} from '../src/services/notification.service.js';

const { safeType, safeErrorName, safeErrorCode } = notificationLogSanitizers;

const SECRET = 'customer-secret-123';

/** Everything the log emits, flattened into one string for inspection. */
function emitted(payload, error) {
  return notificationFailureLog(payload, error).join(' ');
}

test('a database error message never reaches the log', () => {
  // Mongoose puts the offending document value straight into `message`, which
  // is exactly why the logger must not read it.
  const error = new Error(
    `E11000 duplicate key error collection: merzox.notifications dup key: { body: "${SECRET}" }`
  );
  error.name = 'MongoServerError';
  error.code = 11000;

  const line = emitted({ type: 'orderPlaced', body: SECRET }, error);

  assert.equal(line.includes(SECRET), false, line);
  assert.equal(line.includes('duplicate key'), false, line);
  assert.equal(line.includes('merzox.notifications'), false, line);
  assert.equal(line.includes('[notification] NOTIFICATION_PERSIST_FAILED'), true);
  assert.equal(line.includes('type=orderPlaced'), true);
  assert.equal(line.includes('errorName=MongoServerError'), true);
  assert.equal(line.includes('errorCode=11000'), true);
});

test('a validation error carrying customer data is not echoed', () => {
  const error = new Error(
    `Notification validation failed: title: Path \`title\` is invalid (${SECRET}).`
  );
  error.name = 'ValidationError';
  error.errors = { title: { value: SECRET } };

  const line = emitted(
    {
      type: 'newMessage',
      title: SECRET,
      body: SECRET,
      data: { conversationId: SECRET, senderName: SECRET }
    },
    error
  );

  assert.equal(line.includes(SECRET), false, line);
  assert.equal(line.includes('validation failed'), false, line);
  assert.equal(line.includes('errorName=ValidationError'), true);
  assert.equal(line.includes('errorCode=none'), true);
});

test('the log never carries a stack trace', () => {
  const error = new Error('boom');
  error.name = 'TypeError';

  const line = emitted({ type: 'orderStatus' }, error);

  assert.equal(line.includes('at '), false, line);
  assert.equal(line.includes(String(error.stack).split('\n')[1] ?? 'no-frame'), false);
  assert.equal(line.includes('boom'), false, line);
});

test('the emitted field set is fixed and bounded', () => {
  const parts = notificationFailureLog({ type: 'newReview' }, new Error('x'));

  assert.equal(parts.length, 4);
  assert.equal(parts[0], '[notification] NOTIFICATION_PERSIST_FAILED');
  assert.match(parts[1], /^type=[A-Za-z]+$/);
  assert.match(parts[2], /^errorName=[A-Za-z]+$/);
  assert.match(parts[3], /^errorCode=(none|[A-Za-z0-9_]+)$/);
});

test('an unrecognised notification type is not echoed', () => {
  assert.equal(safeType('orderPlaced'), 'orderPlaced');
  assert.equal(safeType(`injected-${SECRET}`), 'unknown');
  assert.equal(safeType(undefined), 'unknown');
  assert.equal(safeType({ toString: () => SECRET }), 'unknown');

  // A payload whose type was tampered with still logs nothing identifying.
  const line = emitted({ type: `injected-${SECRET}` }, new Error('x'));
  assert.equal(line.includes(SECRET), false, line);
  assert.equal(line.includes('type=unknown'), true);
});

test('an attacker-shaped error name or code is rejected', () => {
  const hostile = new Error('x');
  hostile.name = `Error: ${SECRET}`;
  hostile.code = { toString: () => SECRET };

  assert.equal(safeErrorName(hostile), 'UnknownError');
  assert.equal(safeErrorCode(hostile), null);

  const line = emitted({ type: 'orderPlaced' }, hostile);
  assert.equal(line.includes(SECRET), false, line);
  assert.equal(line.includes('errorName=UnknownError'), true);
  assert.equal(line.includes('errorCode=none'), true);
});

test('sanitizers survive a missing or non-error rejection', () => {
  assert.equal(safeErrorName(undefined), 'UnknownError');
  assert.equal(safeErrorName(null), 'UnknownError');
  assert.equal(safeErrorCode(undefined), null);
  assert.equal(safeErrorCode({ code: 1.5 }), 1.5);
  assert.equal(safeErrorCode({ code: 'x'.repeat(41) }), null);

  const line = emitted(undefined, undefined);
  assert.equal(line.includes('type=unknown'), true);
  assert.equal(line.includes('errorName=UnknownError'), true);
});

test('the real console.error output is free of the secret', () => {
  const captured = [];
  const original = console.error;
  console.error = (...args) => captured.push(args.join(' '));

  try {
    const error = new Error(`failed for ${SECRET}`);
    error.name = 'MongoServerError';
    error.code = 11000;
    console.error(...notificationFailureLog({ type: 'orderPlaced', body: SECRET }, error));
  } finally {
    console.error = original;
  }

  assert.equal(captured.length, 1);
  assert.equal(captured[0].includes(SECRET), false, captured[0]);
  assert.equal(captured[0].includes('NOTIFICATION_PERSIST_FAILED'), true);
});
