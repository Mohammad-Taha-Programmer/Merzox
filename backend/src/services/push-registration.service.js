import { PushRegistration } from '../models/PushRegistration.js';

function duplicateKey(error) {
  return Number(error?.code) === 11000;
}

/**
 * The service owns persistence semantics so controllers never decide
 * registration ownership.
 *
 * The push target itself is proof of the app instance's current FCM
 * registration, while account authority always comes from req.user.
 */
export function createPushRegistrationService({
  registrationModel = PushRegistration,
  now = () => new Date()
} = {}) {
  async function register({
    userId,
    targetKind,
    target,
    platform
  }) {
    const lastSeenAt = now();

    const filter = {
      targetKind,
      target
    };

    const update = {
      $set: {
        user: userId,
        targetKind,
        target,
        platform,
        lastSeenAt
      }
    };

    const options = {
      new: true,
      upsert: true,
      setDefaultsOnInsert: true,
      runValidators: true
    };

    try {
      await registrationModel.findOneAndUpdate(
        filter,
        update,
        options
      );
    } catch (error) {
      /**
       * Two concurrent first registrations for the same globally-unique target
       * may race at the unique index. The winner creates the record; the loser
       * then performs the same authoritative ownership update without upsert.
       */
      if (!duplicateKey(error)) {
        throw error;
      }

      const recovered =
        await registrationModel.findOneAndUpdate(
          filter,
          update,
          {
            ...options,
            upsert: false
          }
        );

      if (!recovered) {
        throw error;
      }
    }

    return {
      registered: true,
      targetKind,
      platform,
      lastSeenAt
    };
  }

  async function unregister({
    userId,
    targetKind,
    target
  }) {
    const result = await registrationModel.deleteOne({
      user: userId,
      targetKind,
      target
    });

    return {
      unregistered:
        Number(result?.deletedCount ?? 0) > 0
    };
  }

  /**
   * Internal-only delivery lookup for GAP-016D4.
   * `target` is select:false in the model and is explicitly selected only for
   * the privileged server-side delivery path.
   */
  async function listDeliveryTargetsForUser(userId) {
    return registrationModel
      .find({ user: userId })
      .select('+target')
      .sort({
        updatedAt: -1,
        _id: -1
      })
      .lean();
  }

  /**
   * Removes a transport target only if every identity fact observed at
   * delivery time is still true. If the same target moved to another
   * authenticated account while FCM was in flight, the stale delivery
   * attempt cannot delete the new owner's registration.
   */
  async function removeDeliveryTarget({
    registrationId,
    userId,
    targetKind,
    target
  }) {
    const result = await registrationModel.deleteOne({
      _id: registrationId,
      user: userId,
      targetKind,
      target
    });

    return Number(result?.deletedCount ?? 0) > 0;
  }

  return {
    register,
    unregister,
    listDeliveryTargetsForUser,
    removeDeliveryTarget
  };
}

export const pushRegistrationService =
  createPushRegistrationService();
