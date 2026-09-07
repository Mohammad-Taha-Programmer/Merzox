import assert from 'node:assert/strict';
import test from 'node:test';

import mongoose from 'mongoose';

import { Message } from '../src/models/Message.js';
import { MessageBookmark } from '../src/models/MessageBookmark.js';
import {
  MESSAGE_ACTION_CODES,
  readReplyToId,
  replySnapshot,
  REPLY_QUOTE_MAX,
  requireBookmarkTarget,
  requireReplyTarget
} from '../src/policies/message-actions.policy.js';
import { validateMessageCreate } from '../src/middleware/validate.js';

/**
 * Answering one message, and marking one to come back to.
 *
 * Both name a message by id, and both look it up inside the thread the caller
 * is already in - so an id from another conversation is simply not found.
 * A mark belongs to the reader who made it: the same message is marked for
 * one side of a thread and not for the other.
 */

function message({ body = 'مرحبا', senderType = 'customer', product } = {}) {
  return new Message({
    conversation: new mongoose.Types.ObjectId(),
    business: new mongoose.Types.ObjectId(),
    user: new mongoose.Types.ObjectId(),
    senderType,
    senderName: 'ياسمين',
    body,
    sharedProduct: product ?? null
  });
}

function reject(handler, body) {
  try {
    handler({ body }, {}, () => {});
    return null;
  } catch (error) {
    return error.code;
  }
}

test('an answer names a message, or names nothing', () => {
  assert.equal(readReplyToId({}), null);
  assert.equal(readReplyToId({ replyToId: null }), null);
  assert.equal(readReplyToId({ replyToId: '  m1  ' }), 'm1');

  // Dropping an unusable one would send a bare message where the reader meant
  // to answer something.
  for (const value of ['', '   ', 7, {}, []]) {
    assert.equal(
      reject(validateMessageCreate, { body: 'x', replyToId: value }),
      MESSAGE_ACTION_CODES.invalidReply,
      `replyToId ${JSON.stringify(value)} should be refused`
    );
  }

  assert.equal(reject(validateMessageCreate, { body: 'x', replyToId: 'm1' }), null);
});

test('a message from another conversation is not there to answer', () => {
  // The lookup that feeds this is always scoped to the thread, so a real id
  // that belongs elsewhere arrives here as nothing.
  try {
    requireReplyTarget(null);
    assert.fail('a stranger message was accepted');
  } catch (error) {
    assert.equal(error.code, MESSAGE_ACTION_CODES.replyNotFound);
    assert.equal(error.statusCode, 404);
  }

  try {
    requireBookmarkTarget(null);
    assert.fail('a stranger message was marked');
  } catch (error) {
    assert.equal(error.code, MESSAGE_ACTION_CODES.bookmarkNotFound);
  }
});

test('the quote keeps enough to recognise the message, and no more', () => {
  const long = 'ـ'.repeat(REPLY_QUOTE_MAX + 50);
  const snapshot = replySnapshot(message({ body: long }));

  assert.equal(snapshot.body.length, REPLY_QUOTE_MAX);
  assert.equal(snapshot.hasProduct, false);
  assert.equal(snapshot.senderType, 'customer');
});

test('a quote of a shared card says that it was one', () => {
  // Its body may be empty - a card is a message without words - and a quote
  // showing an empty line would look like a fault.
  const snapshot = replySnapshot(
    message({
      body: '',
      product: {
        productId: 'p1',
        businessId: 'b1',
        name: 'أحمر الشفاه',
        price: 5,
        imageUrl: ''
      }
    })
  );

  assert.equal(snapshot.body, '');
  assert.equal(snapshot.hasProduct, true);
});

test('an answer carries its quote to the app, told from whose side', () => {
  const answered = message({ body: 'عندي استفسار', senderType: 'customer' });

  const answer = new Message({
    conversation: new mongoose.Types.ObjectId(),
    business: new mongoose.Types.ObjectId(),
    user: new mongoose.Types.ObjectId(),
    senderType: 'business',
    body: 'تفضلي',
    replyTo: replySnapshot(answered)
  });

  assert.equal(answer.validateSync(), undefined);

  const asMerchant = answer.toClientJSON('business');
  assert.equal(asMerchant.replyTo.body, 'عندي استفسار');
  // The quote is of the other side, seen from the merchant.
  assert.equal(asMerchant.replyTo.isMine, false);

  const asCustomer = answer.toClientJSON('customer');
  assert.equal(asCustomer.replyTo.isMine, true);

  // And an ordinary message says so plainly rather than by omission.
  assert.equal(message().toClientJSON('customer').replyTo, null);
});

test('a mark is the reader own, and the wire says so per reader', () => {
  const one = message();

  assert.equal(one.toClientJSON('customer').bookmarked, false);
  assert.equal(
    one.toClientJSON('customer', { bookmarked: true }).bookmarked,
    true
  );
  // The same message, the other side of the thread: their mark, not this one.
  assert.equal(one.toClientJSON('business').bookmarked, false);
});

test('marking twice is one mark', () => {
  // The index is what makes it so, rather than a check that could race with
  // a second tap.
  const index = MessageBookmark.schema.indexes().find(
    ([, options]) => options?.name === 'unique_bookmark_per_reader'
  );

  assert.ok(index, 'the unique index is missing');
  assert.deepEqual(index[0], { user: 1, message: 1 });
  assert.equal(index[1].unique, true);
});
