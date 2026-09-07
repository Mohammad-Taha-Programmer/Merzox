import { AppError } from '../utils/AppError.js';

/**
 * The three things that can be done to one message: answer it, copy it, or
 * mark it to come back to.
 *
 * Copying never reaches here - it is the reader's own clipboard. The other
 * two do, and both are scoped the same way as sharing a product was: by the
 * conversation. A reply names a message by id and the id is looked up inside
 * the thread it was sent from, so there is no way to quote a stranger's
 * conversation into your own. A bookmark belongs to the reader who made it
 * and to nobody else.
 */

export const MESSAGE_ACTION_CODES = Object.freeze({
  invalidReply: 'INVALID_REPLY_TARGET',
  replyNotFound: 'REPLY_TARGET_NOT_FOUND',
  bookmarkNotFound: 'BOOKMARKED_MESSAGE_NOT_FOUND'
});

/// How much of the answered message the quote keeps.
///
/// Enough to recognise which one it was, not enough to repeat it. A quote as
/// long as the message would make the thread read twice.
export const REPLY_QUOTE_MAX = 200;

/**
 * Reads the answered message's id out of a request body.
 *
 * Absent is ordinary - most messages answer nothing. Present but unusable is
 * an error, because dropping it would send a bare message where the reader
 * meant to answer something.
 */
export function readReplyToId(body = {}) {
  const raw = body.replyToId;

  if (raw === undefined || raw === null) return null;

  if (typeof raw !== 'string' || raw.trim() === '') {
    throw new AppError(
      'The answered message is invalid',
      400,
      MESSAGE_ACTION_CODES.invalidReply
    );
  }

  return raw.trim();
}

/**
 * The copy of the answered message that travels with the answer.
 *
 * A copy rather than a pointer, for the reason every other copy in this app
 * is one: the quote has to stay readable when the message it quotes is a
 * hundred messages back, or gone. `hasProduct` is kept so a quote of a shared
 * card can say what it was rather than showing an empty line.
 */
export function replySnapshot(message) {
  const body = String(message.body ?? '').trim();

  return {
    messageId: message._id.toString(),
    senderType: message.senderType,
    senderName: message.senderName ?? '',
    body: body.length > REPLY_QUOTE_MAX ? body.slice(0, REPLY_QUOTE_MAX) : body,
    hasProduct: Boolean(message.sharedProduct)
  };
}

/**
 * Refuses an answer to something that is not in this conversation.
 *
 * The lookup that produces [message] is always scoped to the thread, so this
 * is the case where the id was real but belonged somewhere else - or where
 * the message has since been removed.
 */
export function requireReplyTarget(message) {
  if (!message) {
    throw new AppError(
      'The answered message was not found in this conversation',
      404,
      MESSAGE_ACTION_CODES.replyNotFound
    );
  }

  return message;
}

/**
 * Refuses a bookmark on a message that is not in this conversation.
 */
export function requireBookmarkTarget(message) {
  if (!message) {
    throw new AppError(
      'The message was not found in this conversation',
      404,
      MESSAGE_ACTION_CODES.bookmarkNotFound
    );
  }

  return message;
}
