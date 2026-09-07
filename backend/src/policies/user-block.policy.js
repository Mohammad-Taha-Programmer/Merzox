import { AppError } from '../utils/AppError.js';

/**
 * Refusing to hear from someone.
 *
 * Who may be blocked is never asked for: a block is made from inside a
 * conversation, so the other side of that conversation is the only person it
 * can name. There is no id to forge and no list to search - the same shape as
 * sharing a product into a thread, for the same reason.
 *
 * A block closes the thread both ways. Letting the one who blocked keep
 * writing while the other cannot answer would be a worse thing than either
 * outcome: it turns a refusal to hear into a way to speak unanswerable.
 */

export const USER_BLOCK_CODES = Object.freeze({
  blocked: 'CONVERSATION_BLOCKED',
  self: 'CANNOT_BLOCK_SELF'
});

/**
 * Who the other side of a conversation is, for the reader looking at it.
 *
 * The customer is on the conversation; the merchant is the shop's owner. A
 * thread whose shop has no owner - which the data allows - has nobody to
 * block, and that is an absence rather than an error.
 */
export function conversationCounterpart({
  conversation,
  viewerType,
  businessOwnerId
}) {
  if (viewerType === 'customer') return businessOwnerId ?? null;

  return conversation?.user ?? null;
}

/**
 * Refuses a block that names the reader themselves.
 *
 * It cannot happen through a conversation - a shop may not open one with
 * itself - but the rule is stated here rather than trusted to that.
 */
export function assertBlockableCounterpart(readerId, counterpartId) {
  if (!counterpartId) {
    throw new AppError(
      'There is nobody to block in this conversation',
      404,
      'CONVERSATION_NOT_FOUND'
    );
  }

  if (String(readerId) === String(counterpartId)) {
    throw new AppError(
      'An account cannot block itself',
      400,
      USER_BLOCK_CODES.self
    );
  }

  return counterpartId;
}

/**
 * Refuses to carry a message between two people, either of whom has closed
 * the door.
 *
 * The same refusal whichever way round it is, and deliberately worded for the
 * sender rather than about the other person: "this conversation is closed"
 * tells them what to expect without telling them what somebody else did.
 */
export function assertNotBlocked({ blockedByMe, blockedMe }) {
  if (!blockedByMe && !blockedMe) return;

  throw new AppError(
    'This conversation is closed',
    403,
    USER_BLOCK_CODES.blocked
  );
}
