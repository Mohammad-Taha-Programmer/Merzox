import { pushRegistrationService } from '../services/push-registration.service.js';
import { asyncHandler } from '../utils/asyncHandler.js';

export const registerPushRegistration =
  asyncHandler(async (req, res) => {
    const registration =
      await pushRegistrationService.register({
        // The client never supplies account ownership.
        userId: req.user._id,
        targetKind: req.body.targetKind,
        target: req.body.target,
        platform: req.body.platform
      });

    res.json({
      success: true,
      data: {
        registered: registration.registered,
        targetKind: registration.targetKind,
        platform: registration.platform,
        lastSeenAt: registration.lastSeenAt
      }
    });
  });

export const unregisterPushRegistration =
  asyncHandler(async (req, res) => {
    const result =
      await pushRegistrationService.unregister({
        // A target can be removed only from the authenticated owner.
        userId: req.user._id,
        targetKind: req.body.targetKind,
        target: req.body.target
      });

    res.json({
      success: true,
      data: {
        unregistered: result.unregistered
      }
    });
  });
