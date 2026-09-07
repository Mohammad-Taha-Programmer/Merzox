import { Business } from '../models/Business.js';
import { Conversation } from '../models/Conversation.js';

/**
 * Carries a shop's picture everywhere a copy of it is kept.
 *
 * A conversation stores the shop's logo rather than reading it, so the inbox
 * can render a list without loading every shop behind it. The copy is taken
 * when the chat is opened and was never refreshed afterwards - so a merchant
 * who set a picture kept a blank circle in every conversation that already
 * existed, and one who changed it kept the old one.
 *
 * Written straight through the collection rather than by loading each row: a
 * merchant may have any number of conversations, and this is one field.
 */
export async function applyLogoToConversations(
  businessId,
  logoUrl,
  { model = Conversation } = {}
) {
  if (!businessId) return 0;

  const result = await model.updateMany(
    { business: businessId },
    { $set: { businessLogoUrl: logoUrl ?? '' } }
  );

  return result?.modifiedCount ?? 0;
}

/**
 * Carries a customer's picture into the threads that show it.
 *
 * The mirror of [applyLogoToConversations]: a conversation keeps the
 * customer's picture as well as the shop's, so the merchant's inbox can draw
 * a list without loading an account per row. Nothing refreshed that copy
 * either, so a customer who set a picture kept a blank circle in every thread
 * they had already opened.
 */
export async function applyAvatarToConversations(
  userId,
  avatarUrl,
  { model = Conversation } = {}
) {
  if (!userId) return 0;

  const result = await model.updateMany(
    { user: userId },
    { $set: { userAvatarUrl: avatarUrl ?? '' } }
  );

  return result?.modifiedCount ?? 0;
}

/**
 * Carries an account's new picture onto the shop it owns.
 *
 * A merchant has one picture, not two. Before this, setting it changed only
 * the account, and the shop kept whatever logo it had - so the bar the
 * merchant looks at and the card a customer sees showed different pictures
 * with no way to reconcile them.
 *
 * Addressed by ownership rather than by a shop id from the client, so nobody
 * can put their picture on somebody else's shop. A customer owns no shop and
 * this is then a no-op rather than a refusal, and a disabled shop still takes
 * it: its owner is entitled to change their picture, and refusing here would
 * fail the whole request over a shop the merchant cannot even see.
 */
export async function applyPictureToOwnedBusiness(
  ownerId,
  url,
  { model = Business, conversations = Conversation } = {}
) {
  if (!ownerId || !url) return false;

  // `findOneAndUpdate` rather than `updateOne`: the shop's id is needed to
  // reach the conversations that hold a copy of its logo.
  const business = await model.findOneAndUpdate(
    { owner: ownerId },
    { $set: { logoUrl: url } },
    { new: true, projection: { _id: 1 } }
  );

  if (!business) return false;

  await applyLogoToConversations(business._id, url, { model: conversations });

  return true;
}
