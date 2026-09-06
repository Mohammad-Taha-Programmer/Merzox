/**
 * What "search the messages" means, kept away from the database.
 *
 * Two different questions share one box in the inbox. Typing a person's name
 * should offer the thread; typing something that was said should offer the
 * place it was said. They are answered separately and returned separately, so
 * the screen never has to guess which one the reader meant.
 */

/** Longer than any name or phrase worth typing into a one-line box. */
export const MAX_QUERY_LENGTH = 80;

/**
 * How many occurrences inside one thread the reader may step through.
 *
 * The counter and its two arrows are only usable while the number is small;
 * past this the honest answer is the first fifty and a count that says so.
 */
export const MAX_MATCHES_PER_CONVERSATION = 50;

/** A ceiling on the rows a single query may read, whatever it matches. */
export const MAX_MESSAGE_HITS = 300;

/** How many threads a name search may return. */
export const MAX_PEOPLE_RESULTS = 30;

/**
 * Trims a typed query to something safe to build a pattern from.
 *
 * Blank in, blank out - the caller answers an empty query with empty results
 * rather than with every message ever written.
 */
export function normalizeSearchQuery(value) {
  return String(value ?? '')
    .trim()
    .slice(0, MAX_QUERY_LENGTH);
}

/**
 * Turns a typed query into a literal, case-insensitive pattern.
 *
 * Every regular-expression metacharacter is escaped: a reader typing `(` is
 * looking for a bracket, not opening a group, and an unescaped one would be a
 * 500 rather than a result.
 */
export function searchPattern(query) {
  return new RegExp(String(query).replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i');
}

/**
 * Collapses message hits into one row per conversation.
 *
 * A word said nine times in one thread is one result with a count, not nine
 * results - and the row opens at the FIRST time it was said, so stepping
 * forward with the arrows walks the conversation the way it happened.
 *
 * `hits` must be oldest first. Rows come back with the thread whose newest hit
 * is most recent at the top, which is the order the inbox already sorts by.
 */
export function groupMessageHits(hits) {
  const byConversation = new Map();

  for (const hit of hits ?? []) {
    const key = String(hit.conversation);
    const existing = byConversation.get(key);

    if (!existing) {
      byConversation.set(key, {
        conversationId: key,
        matchCount: 1,
        // The oldest hit: what the row opens at, and step 1 of the counter.
        matchIds: [String(hit._id)],
        snippet: hit.body,
        firstMatchAt: hit.createdAt ?? null,
        lastMatchAt: hit.createdAt ?? null
      });
      continue;
    }

    existing.matchCount += 1;
    existing.lastMatchAt = hit.createdAt ?? existing.lastMatchAt;

    // The count keeps rising past the ceiling; only the walkable list stops.
    if (existing.matchIds.length < MAX_MATCHES_PER_CONVERSATION) {
      existing.matchIds.push(String(hit._id));
    }
  }

  return [...byConversation.values()].sort((a, b) => {
    const left = a.lastMatchAt ? new Date(a.lastMatchAt).getTime() : 0;
    const right = b.lastMatchAt ? new Date(b.lastMatchAt).getTime() : 0;
    return right - left;
  });
}
