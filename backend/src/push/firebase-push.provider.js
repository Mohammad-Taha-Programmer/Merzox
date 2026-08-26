import {
  applicationDefault,
  getApps,
  initializeApp
} from 'firebase-admin/app';
import {
  getMessaging
} from 'firebase-admin/messaging';

import { env } from '../config/env.js';
import {
  firebasePushInitFailureLog,
  registerPushSender
} from './push.publisher.js';

function defaultApp(apps) {
  return (
    apps.find(
      (app) =>
        app?.name === '[DEFAULT]'
    ) ?? null
  );
}

export function createFirebasePushProvider({
  enabled =
    env.firebasePushEnabled,
  nodeEnv =
    env.nodeEnv,
  getAppsFn =
    getApps,
  initializeAppFn =
    initializeApp,
  applicationDefaultFn =
    applicationDefault,
  getMessagingFn =
    getMessaging,
  registerPushSenderFn =
    registerPushSender,
  logger =
    console
} = {}) {
  let unregisterSender = null;
  let initialized = false;

  function initialize() {
    if (!enabled) {
      return {
        enabled: false,
        initialized: false
      };
    }

    if (initialized) {
      return {
        enabled: true,
        initialized: true
      };
    }

    try {
      const existingApp =
        defaultApp(
          getAppsFn()
        );

      const app =
        existingApp ??
        initializeAppFn({
          credential:
            applicationDefaultFn()
        });

      const messaging =
        getMessagingFn(app);

      unregisterSender =
        registerPushSenderFn(
          async ({
            targetKind,
            target,
            message
          }) => {
            if (
              targetKind === 'fid'
            ) {
              return messaging.send({
                ...message,
                fid: target
              });
            }

            if (
              targetKind === 'token'
            ) {
              return messaging.send({
                ...message,
                token: target
              });
            }

            throw new TypeError(
              'Unsupported push target kind'
            );
          }
        );

      initialized = true;

      return {
        enabled: true,
        initialized: true
      };
    } catch (error) {
      if (
        nodeEnv !== 'test'
      ) {
        logger.error(
          ...firebasePushInitFailureLog(
            error
          )
        );
      }

      return {
        enabled: true,
        initialized: false
      };
    }
  }

  function close() {
    if (unregisterSender) {
      unregisterSender();
      unregisterSender = null;
    }

    initialized = false;
  }

  return {
    initialize,
    close
  };
}

const firebasePushProvider =
  createFirebasePushProvider();

export function initializeFirebasePushProvider() {
  return firebasePushProvider.initialize();
}

export function closeFirebasePushProvider() {
  firebasePushProvider.close();
}
