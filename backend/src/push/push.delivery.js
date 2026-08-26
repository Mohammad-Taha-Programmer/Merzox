import { env } from '../config/env.js';
import {
  notificationTypes
} from '../models/Notification.js';
import {
  pushRegistrationService
} from '../services/push-registration.service.js';
import {
  formatErrorCode,
  safeErrorName
} from '../utils/safe-log.js';
import {
  buildPushMessage,
  isPushTransportAvailable,
  pushDeliveryFailureLog,
  sendPushTarget
} from './push.publisher.js';

function safeNotificationType(value) {
  return notificationTypes.includes(value)
    ? value
    : 'unknown';
}

export function pushRegistryLookupFailureLog(
  notificationType,
  error
) {
  return [
    '[push] PUSH_REGISTRY_LOOKUP_FAILED',
    `type=${safeNotificationType(notificationType)}`,
    `errorName=${safeErrorName(error)}`,
    `errorCode=${formatErrorCode(error)}`
  ];
}

export function pushTargetCleanupFailureLog(
  {
    notificationType,
    targetKind,
    platform
  },
  error
) {
  const safeTargetKind =
    targetKind === 'token' ||
    targetKind === 'fid'
      ? targetKind
      : 'unknown';

  const safePlatform =
    platform === 'android' ||
    platform === 'ios'
      ? platform
      : 'unknown';

  return [
    '[push] PUSH_TARGET_CLEANUP_FAILED',
    `type=${safeNotificationType(notificationType)}`,
    `targetKind=${safeTargetKind}`,
    `platform=${safePlatform}`,
    `errorName=${safeErrorName(error)}`,
    `errorCode=${formatErrorCode(error)}`
  ];
}

export function pushPipelineFailureLog(
  notificationType,
  error
) {
  return [
    '[push] PUSH_PIPELINE_FAILED',
    `type=${safeNotificationType(notificationType)}`,
    `errorName=${safeErrorName(error)}`,
    `errorCode=${formatErrorCode(error)}`
  ];
}

function normalizedId(value) {
  return String(value ?? '').trim();
}

export function createPushDeliveryService({
  registrationService =
    pushRegistrationService,
  buildMessage =
    buildPushMessage,
  sendTarget =
    sendPushTarget,
  transportAvailable =
    isPushTransportAvailable,
  nodeEnv =
    env.nodeEnv,
  logger =
    console
} = {}) {
  async function deliverUnsafe(
    notification
  ) {
    /**
     * Important: when Firebase is disabled or initialization failed, do not
     * even touch the registry. Development/test remains a zero-push path.
     */
    if (!transportAvailable()) {
      return {
        sent: 0,
        failed: 0,
        removed: 0,
        skipped: 0,
        reason: 'disabled'
      };
    }

    const message =
      buildMessage(notification);

    const userId =
      normalizedId(
        notification?.user
      );

    if (!message || !userId) {
      return {
        sent: 0,
        failed: 0,
        removed: 0,
        skipped: 0,
        reason: 'invalid-notification'
      };
    }

    let registrations;

    try {
      registrations =
        await registrationService
          .listDeliveryTargetsForUser(
            userId
          );
    } catch (error) {
      if (nodeEnv !== 'test') {
        logger.error(
          ...pushRegistryLookupFailureLog(
            notification?.type,
            error
          )
        );
      }

      return {
        sent: 0,
        failed: 0,
        removed: 0,
        skipped: 0,
        reason: 'registry-error'
      };
    }

    const stats = {
      sent: 0,
      failed: 0,
      removed: 0,
      skipped: 0
    };

    await Promise.all(
      (registrations ?? [])
        .map(
          async (registration) => {
            const targetKind =
              registration?.targetKind;

            const target =
              typeof registration?.target ===
              'string'
                ? registration.target
                : '';

            const platform =
              registration?.platform;

            let result;

            try {
              result =
                await sendTarget({
                  targetKind,
                  target,
                  message
                });
            } catch (error) {
              // Dependency injection or a future transport must not widen the
              // authoritative notification failure surface.
              result = {
                sent: false,
                reason: 'provider-error',
                terminal: false,
                error
              };
            }

            if (result?.sent) {
              stats.sent += 1;
              return;
            }

            if (
              result?.reason ===
              'disabled'
            ) {
              stats.skipped += 1;
              return;
            }

            stats.failed += 1;

            if (
              result?.error &&
              nodeEnv !== 'test'
            ) {
              logger.error(
                ...pushDeliveryFailureLog(
                  {
                    notificationType:
                      notification?.type,
                    targetKind,
                    platform
                  },
                  result.error
                )
              );
            }

            if (
              result?.terminal !== true
            ) {
              return;
            }

            try {
              const removed =
                await registrationService
                  .removeDeliveryTarget({
                    registrationId:
                      registration?._id,
                    userId,
                    targetKind,
                    target
                  });

              if (removed) {
                stats.removed += 1;
              }
            } catch (error) {
              if (nodeEnv !== 'test') {
                logger.error(
                  ...pushTargetCleanupFailureLog(
                    {
                      notificationType:
                        notification?.type,
                      targetKind,
                      platform
                    },
                    error
                  )
                );
              }
            }
          }
        )
    );

    return stats;
  }

  async function deliver(
    notification
  ) {
    try {
      return await deliverUnsafe(
        notification
      );
    } catch (error) {
      if (nodeEnv !== 'test') {
        logger.error(
          ...pushPipelineFailureLog(
            notification?.type,
            error
          )
        );
      }

      return {
        sent: 0,
        failed: 0,
        removed: 0,
        skipped: 0,
        reason: 'pipeline-error'
      };
    }
  }

  return {
    deliver
  };
}

const pushDeliveryService =
  createPushDeliveryService();

export function deliverNotificationPush(
  notification
) {
  return pushDeliveryService.deliver(
    notification
  );
}
