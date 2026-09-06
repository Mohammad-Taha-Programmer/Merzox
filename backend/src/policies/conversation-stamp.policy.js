/**
 * The time a conversation row shows.
 *
 * Not the time of the last message - the time of the last message the reader
 * RECEIVED. The two differ every time you answer someone: the thread moves to
 * the top and its stamp jumps to your own reply, so a row that says 9:43 is
 * telling you when you last spoke rather than when they last did. What a
 * reader scanning an inbox is deciding about is how long someone has been
 * waiting for them, and that is the other side's clock.
 */

/** The two sides a message can come from. */
export const SENDER_TYPES = ['customer', 'business'];

/**
 * Which side counts as "them" for a given reader.
 *
 * A customer's counterpart is the shop; a merchant's is the customer. Stated
 * once here so the two listings cannot drift into disagreeing about it.
 */
export function counterpartSenderType(viewerType) {
  return viewerType === 'business' ? 'customer' : 'business';
}

/**
 * The aggregation that finds each thread's newest incoming message.
 *
 * One query for a whole page of rows rather than one per row, and no
 * denormalised column to fall out of step with the messages it summarises.
 * The `{ conversation, createdAt, _id }` index already serves the sort.
 */
export function lastReceivedPipeline(conversationIds, senderType) {
  return [
    { $match: { conversation: { $in: conversationIds }, senderType } },
    { $sort: { conversation: 1, createdAt: -1, _id: -1 } },
    { $group: { _id: '$conversation', at: { $first: '$createdAt' } } }
  ];
}

/**
 * Turns the aggregation's rows into a lookup keyed by conversation id.
 *
 * A thread nobody has written to you in is simply absent, which the caller
 * reads as "nothing received yet" rather than as a zero date.
 */
export function lastReceivedByConversation(rows) {
  const byId = new Map();

  for (const row of rows ?? []) {
    if (!row || row._id === undefined || row._id === null) continue;
    byId.set(String(row._id), row.at ?? null);
  }

  return byId;
}
