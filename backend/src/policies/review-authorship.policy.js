/**
 * Who may write a review.
 *
 * It used to be "a customer account, and nobody else". That was a stand-in
 * for the thing actually worth preventing - a shopkeeper rating their own
 * shop - and it cost more than it bought: a merchant buying from another
 * merchant is an ordinary customer of that shop, and had no way to say so.
 *
 * So the rule is now about the shop, not the account: anyone who bought may
 * review, except the person who owns what they are reviewing.
 */

/** What a refusal is called, so the client can say it in Arabic. */
export const OWN_BUSINESS_REVIEW_CODE = 'CANNOT_REVIEW_OWN_BUSINESS';

/**
 * Reads an id off whatever shape it arrives in.
 *
 * Mongoose hands back an ObjectId, a lean read hands back the same, and a
 * test hands back a string. All three have to compare the same way.
 */
function idOf(value) {
  if (value === null || value === undefined) return null;
  if (typeof value === 'string') return value;
  if (typeof value.toHexString === 'function') return value.toHexString();

  return String(value);
}

/**
 * Whether [userId] is the owner of the shop being reviewed.
 *
 * An absent owner is not a match: a shop with no owner recorded belongs to
 * nobody, and refusing everyone would be the wrong way round.
 */
export function reviewsOwnBusiness(userId, ownerId) {
  const user = idOf(userId);
  const owner = idOf(ownerId);

  if (user === null || owner === null) return false;

  return user === owner;
}
