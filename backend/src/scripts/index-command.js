import {
  applyMissingIndexes,
  createIndexPlan,
  INDEX_PLAN_VERSION,
  IndexManagementError,
  inspectIndexDrift,
  isIndexDriftClean,
  validateIndexApplyApproval
} from './index-management.js';

function commandError(code) {
  throw new IndexManagementError(code);
}

function requireOperationalDependency(
  value,
  code
) {
  if (typeof value !== 'function') {
    commandError(code);
  }

  return value;
}

export async function executeIndexCommand({
  mode,
  models,
  env = process.env,
  connect,
  disconnect
}) {
  const plan =
    createIndexPlan(models);

  if (mode === 'plan') {
    return {
      exitCode: 0,
      payload: plan
    };
  }

  if (
    mode !== 'check' &&
    mode !== 'apply'
  ) {
    commandError(
      'INVALID_INDEX_MODE'
    );
  }

  if (mode === 'apply') {
    validateIndexApplyApproval({
      env,
      planId: plan.planId
    });
  }

  const uri =
    String(
      env?.MONGODB_URI ?? ''
    ).trim();

  if (!uri) {
    commandError(
      'INDEX_DATABASE_URI_REQUIRED'
    );
  }

  const openConnection =
    requireOperationalDependency(
      connect,
      'INDEX_CONNECT_UNAVAILABLE'
    );

  const closeConnection =
    requireOperationalDependency(
      disconnect,
      'INDEX_DISCONNECT_UNAVAILABLE'
    );

  let connectionAttempted = false;

  try {
    connectionAttempted = true;

    await openConnection(uri);

    const before =
      await inspectIndexDrift(
        models
      );

    if (mode === 'check') {
      const clean =
        isIndexDriftClean(before);

      return {
        exitCode: clean ? 0 : 2,
        payload: {
          kind:
            'merzox-mongodb-index-check',
          version:
            INDEX_PLAN_VERSION,
          planId:
            plan.planId,
          modelCount:
            plan.modelCount,
          indexCount:
            plan.indexCount,
          clean,
          drift:
            before
        }
      };
    }

    const createdCollections =
      await applyMissingIndexes({
        models,
        drift: before
      });

    const after =
      await inspectIndexDrift(
        models
      );

    if (!isIndexDriftClean(after)) {
      commandError(
        'INDEX_APPLY_VERIFICATION_FAILED'
      );
    }

    return {
      exitCode: 0,
      payload: {
        kind:
          'merzox-mongodb-index-apply',
        version:
          INDEX_PLAN_VERSION,
        planId:
          plan.planId,
        modelCount:
          plan.modelCount,
        indexCount:
          plan.indexCount,
        clean: true,
        createdCollections:
          [...createdCollections],
        drift:
          after
      }
    };
  } finally {
    if (connectionAttempted) {
      await closeConnection();
    }
  }
}
