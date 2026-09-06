/**
 * Which notifications the bell is answerable for.
 *
 * A new message writes a notification record, and the bell counted it - so one
 * message from one customer put a `1` on the bell and a `1` on the messages
 * icon at the same time, for the same event. Two counts, one thing to do.
 *
 * The messages icon owns messages. The bell owns everything else. So the
 * record is still written - push delivery and the history both need it - and
 * simply does not belong to the bell's list or the bell's count.
 */
export const MESSAGE_NOTIFICATION_TYPE = 'newMessage';

/**
 * Narrows a notification query to what the bell speaks for.
 *
 * Returns a new filter rather than mutating the one passed in: the caller
 * builds one base filter and uses it for several counts, and a mutation here
 * would silently narrow all of them.
 */
export function bellNotificationFilter(filter = {}) {
  return { ...filter, type: { $ne: MESSAGE_NOTIFICATION_TYPE } };
}
