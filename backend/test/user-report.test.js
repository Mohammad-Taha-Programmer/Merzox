import assert from 'node:assert/strict';
import test from 'node:test';

import mongoose from 'mongoose';

import { UserReport } from '../src/models/UserReport.js';
import {
  assertReportableCounterpart,
  readReport,
  REPORT_NOTE_MAX,
  USER_REPORT_CODES,
  USER_REPORT_REASONS
} from '../src/policies/user-report.policy.js';

/**
 * Telling the operator about somebody.
 *
 * Whom it names is read from the conversation, as a block is. What a block
 * deliberately does not keep - a reason - is the whole of this: a report is
 * read by a person afterwards, and one that said only that somebody
 * complained could not be acted on.
 */

const reporter = new mongoose.Types.ObjectId();
const reported = new mongoose.Types.ObjectId();

test('a reason is required, and only a listed one will do', () => {
  // A reason the operator cannot sort by is a row they will never act on.
  for (const reason of USER_REPORT_REASONS) {
    assert.deepEqual(readReport({ reason }), { reason, note: '' });
  }

  for (const value of [undefined, null, '', 'rude', 7, {}, []]) {
    try {
      readReport({ reason: value });
      assert.fail(`${JSON.stringify(value)} was accepted as a reason`);
    } catch (error) {
      assert.equal(error.code, USER_REPORT_CODES.invalidReason);
      assert.equal(error.statusCode, 400);
    }
  }
});

test('the words beside the reason are optional, and trimmed', () => {
  assert.deepEqual(readReport({ reason: 'spam', note: '  يرسل روابط  ' }), {
    reason: 'spam',
    note: 'يرسل روابط'
  });

  assert.equal(readReport({ reason: 'spam', note: null }).note, '');
  assert.equal(readReport({ reason: 'spam' }).note, '');
});

test('an over-long note is sent back rather than quietly cut', () => {
  // A complaint that arrives half-said is worse than one that was returned to
  // be shortened.
  try {
    readReport({ reason: 'other', note: 'ـ'.repeat(REPORT_NOTE_MAX + 1) });
    assert.fail('an over-long note was accepted');
  } catch (error) {
    assert.equal(error.code, USER_REPORT_CODES.invalidNote);
  }

  // Exactly at the limit is not over it.
  assert.equal(
    readReport({ reason: 'other', note: 'ـ'.repeat(REPORT_NOTE_MAX) }).note
      .length,
    REPORT_NOTE_MAX
  );
});

test('a note that is not words at all is refused', () => {
  for (const value of [7, {}, []]) {
    try {
      readReport({ reason: 'spam', note: value });
      assert.fail(`${JSON.stringify(value)} was accepted as a note`);
    } catch (error) {
      assert.equal(error.code, USER_REPORT_CODES.invalidNote);
    }
  }
});

test('an account cannot report itself, and nobody cannot be reported', () => {
  assert.equal(assertReportableCounterpart(reporter, reported), reported);

  try {
    assertReportableCounterpart(reporter, reporter);
    assert.fail('an account reported itself');
  } catch (error) {
    assert.equal(error.code, USER_REPORT_CODES.self);
  }

  try {
    assertReportableCounterpart(reporter, null);
    assert.fail('a report was made against nobody');
  } catch (error) {
    assert.equal(error.statusCode, 404);
  }
});

test('a report keeps where it happened, and what was said about it', () => {
  const conversation = new mongoose.Types.ObjectId();

  const report = new UserReport({
    reporter,
    reported,
    conversation,
    reason: 'harassment',
    note: 'رسائل مسيئة'
  });

  assert.equal(report.validateSync(), undefined);
  // The thread is kept so whoever reads this can find what it is about
  // without asking the reporter what they meant.
  assert.equal(report.conversation.toString(), conversation.toString());
  assert.equal(report.note, 'رسائل مسيئة');
});

test('a reason the list does not know is refused by the schema too', () => {
  const report = new UserReport({
    reporter,
    reported,
    conversation: new mongoose.Types.ObjectId(),
    reason: 'whatever'
  });

  assert.notEqual(report.validateSync(), undefined);
});

test('there is no status, because nothing in the app could set one', () => {
  // A column that only ever said `open` would describe this app's lack of a
  // moderation screen rather than anything about the report.
  const paths = Object.keys(UserReport.schema.paths).sort();

  assert.deepEqual(paths, [
    '__v',
    '_id',
    'conversation',
    'createdAt',
    'note',
    'reason',
    'reported',
    'reporter',
    'updatedAt'
  ]);
});

test('two complaints about one account are two rows', () => {
  // It is the second that shows a pattern, so nothing here collapses them:
  // no unique index over the pair, unlike a block.
  const unique = UserReport.schema
    .indexes()
    .filter(([, options]) => options?.unique);

  assert.deepEqual(unique, []);
});
