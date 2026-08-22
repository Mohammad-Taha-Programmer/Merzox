/**
 * Conversation unread-counter arithmetic.
 *
 * The counter is written by two independent paths that can interleave in any
 * order: a sender increments it by one, and a reader acknowledges some number
 * of messages. Both must therefore be expressed as *deltas* applied by the
 * database, never as an absolute value computed by the application.
 *
 * The rejected approach was:
 *
 *   count = countDocuments({ readAt: null })   // reader reads 0
 *   ...                                        // sender increments to 1
 *   $set: { unread: count }                    // reader overwrites back to 0
 *
 * That loses the sender's increment and leaves an unread message behind a
 * zeroed badge. `applyAcknowledgement` below is a subtraction, so the two
 * paths commute and no ordering can lose a write.
 *
 * MongoDB applies a single update document atomically, so expressing the
 * reader's side as `max(0, unread - modifiedCount)` inside one update makes
 * the whole reconciliation a single atomic step. No transaction and no replica
 * set is required, which keeps standalone local and CI MongoDB working.
 */

/**
 * The sender's side: one new message for the counterpart. The current value is
 * clamped before the increment so a counter that somehow went negative cannot
 * swallow the next arrivals. (The schema also declares `min: 0`, so a negative
 * value cannot actually persist - this is belt and braces.)
 */
export function applyIncrement(current) {
  return Math.max(0, toCount(current)) + 1;
}

/**
 * The reader's side. `modifiedCount` is what the message update actually
 * changed - not a recount of what remains - so the subtraction only ever
 * removes acknowledgements this request is responsible for.
 */
export function applyAcknowledgement(current, modifiedCount) {
  const acknowledged = Math.max(0, toCount(modifiedCount));
  return Math.max(0, Math.max(0, toCount(current)) - acknowledged);
}

/**
 * The aggregation-pipeline update for the reader's side.
 *
 * A pipeline is used rather than `$inc: -n` so the clamp at zero happens
 * inside the same atomic update; `$inc` alone could drive a counter negative
 * if it ever drifted. Pipeline updates need MongoDB 4.2+, which is well below
 * the version this project already relies on, and unlike transactions they
 * work on a standalone server.
 */
export function acknowledgementUpdate(field, modifiedCount) {
  const acknowledged = Math.max(0, toCount(modifiedCount));

  return [
    {
      $set: {
        [field]: {
          $max: [0, { $subtract: [`$${field}`, acknowledged] }]
        }
      }
    }
  ];
}

/**
 * The set of messages a read acknowledgement may cover: unread, addressed to
 * the reader, and already in existence when the request was received. The
 * `createdAt` bound is what stops a message that arrives mid-request from
 * being consumed by an acknowledgement the reader never saw.
 */
export function acknowledgementFilter({
  conversationId,
  counterpartSenderType,
  readThrough
}) {
  return {
    conversation: conversationId,
    senderType: counterpartSenderType,
    readAt: null,
    createdAt: { $lte: readThrough }
  };
}

/**
 * True when the acknowledgement changed nothing, so the caller can skip the
 * counter write entirely rather than issuing a no-op update.
 */
export function isNoOpAcknowledgement(modifiedCount) {
  return Math.max(0, toCount(modifiedCount)) === 0;
}

function toCount(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? Math.trunc(parsed) : 0;
}
