import {
  safeErrorCode,
  safeErrorName
} from '../utils/safe-log.js';

export const CLI_ACTIONS =
  Object.freeze({
    destructiveSeed:
      Object.freeze({
        label:
          'Seed',
        allowFlag:
          'MERZOX_ALLOW_DESTRUCTIVE_SEED'
      }),

    emailDiagnostic:
      Object.freeze({
        label:
          'SMTP diagnostic',
        allowFlag:
          'MERZOX_ALLOW_EMAIL_DIAGNOSTIC'
      })
  });

export const CLI_REFUSAL =
  Object.freeze({
    production:
      'PRODUCTION_BLOCKED',
    optIn:
      'EXPLICIT_OPT_IN_REQUIRED'
  });

function normalizedNodeEnv(
  nodeEnv
) {
  return String(
    nodeEnv ?? ''
  )
    .trim()
    .toLowerCase();
}

export function cliExecutionRefusal({
  nodeEnv,
  allowValue
}) {
  if (
    normalizedNodeEnv(
      nodeEnv
    ) === 'production'
  ) {
    return CLI_REFUSAL.production;
  }

  if (allowValue !== 'true') {
    return CLI_REFUSAL.optIn;
  }

  return null;
}

export function cliRefusalMessage({
  action,
  refusal
}) {
  if (
    !action ||
    typeof action.label !== 'string' ||
    typeof action.allowFlag !== 'string'
  ) {
    return (
      'CLI action refused by the safety policy.'
    );
  }

  if (
    refusal ===
    CLI_REFUSAL.production
  ) {
    return (
      `${action.label} is disabled when ` +
      'NODE_ENV=production.'
    );
  }

  if (
    refusal ===
    CLI_REFUSAL.optIn
  ) {
    return (
      `${action.label} requires explicit opt-in: ` +
      `${action.allowFlag}=true.`
    );
  }

  return (
    `${action.label} refused by the CLI safety policy.`
  );
}

export function safeCliErrorSummary(
  error
) {
  return Object.freeze({
    errorName:
      safeErrorName(error),
    errorCode:
      safeErrorCode(error)
  });
}
