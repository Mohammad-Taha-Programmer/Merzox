import { Business } from '../models/Business.js';

/**
 * Carries an account's new picture onto the shop it owns.
 *
 * A merchant has one picture, not two. Before this, setting it changed only
 * the account, and the shop kept whatever logo it had - so the bar the
 * merchant looks at and the card a customer sees showed different pictures
 * with no way to reconcile them.
 *
 * Written straight through the collection rather than by loading the shop
 * first, for two reasons. A customer owns no shop, and this must then be a
 * no-op rather than a refusal. And a shop that has been disabled must still
 * take the picture: its owner is entitled to change it, and refusing here
 * would fail the whole request over a shop the merchant cannot even see.
 */
export async function applyPictureToOwnedBusiness(
  ownerId,
  url,
  { model = Business } = {}
) {
  if (!ownerId || !url) return false;

  const result = await model.updateOne(
    { owner: ownerId },
    { $set: { logoUrl: url } }
  );

  // Mongo reports how many documents it matched; a customer matches none.
  return (result?.matchedCount ?? 0) > 0;
}
