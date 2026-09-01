import {
  createHash
} from 'node:crypto';

export const INDEX_PLAN_VERSION = 1;

export const INDEX_MODES =
  Object.freeze([
    'plan',
    'check',
    'apply'
  ]);

export const INDEX_APPLY_ENV =
  Object.freeze({
    allow:
      'MERZOX_ALLOW_INDEX_APPLY',
    planId:
      'MERZOX_INDEX_PLAN_ID'
  });

export class IndexManagementError
  extends Error {
  constructor(code) {
    super(code);

    this.name =
      'IndexManagementError';

    this.code =
      code;
  }
}

function managementError(code) {
  throw new IndexManagementError(
    code
  );
}

function canonicalValue(value) {
  if (Array.isArray(value)) {
    return value.map(
      canonicalValue
    );
  }

  if (
    value === null ||
    typeof value !== 'object'
  ) {
    return value;
  }

  return Object.fromEntries(
    Object.keys(value)
      .filter(
        (key) =>
          value[key] !== undefined
      )
      .sort()
      .map(
        (key) => [
          key,
          canonicalValue(
            value[key]
          )
        ]
      )
  );
}

function serialized(value) {
  return JSON.stringify(
    canonicalValue(value)
  );
}

function modelIdentity(model) {
  const modelName =
    model?.modelName;

  const collection =
    model?.collection
      ?.collectionName;

  if (
    typeof modelName !== 'string' ||
    !modelName ||
    typeof collection !== 'string' ||
    !collection ||
    typeof model?.schema
      ?.indexes !== 'function'
  ) {
    managementError(
      'INVALID_INDEX_MODEL'
    );
  }

  return {
    modelName,
    collection
  };
}

function normalizedIndex({
  keys,
  options
}) {
  if (
    !keys ||
    typeof keys !== 'object' ||
    Array.isArray(keys)
  ) {
    managementError(
      'INVALID_INDEX_KEYS'
    );
  }

  return {
    keys:
      Object.entries(keys)
        .map(
          ([path, direction]) => [
            path,
            canonicalValue(
              direction
            )
          ]
        ),

    options:
      canonicalValue(
        options ?? {}
      )
  };
}

export function buildIndexManifest(
  models
) {
  if (
    !Array.isArray(models) ||
    models.length === 0
  ) {
    managementError(
      'INDEX_MODELS_REQUIRED'
    );
  }

  const collections =
    models.map(
      (model) => {
        const {
          modelName,
          collection
        } =
          modelIdentity(model);

        const indexes =
          model.schema
            .indexes()
            .map(
              ([keys, options]) =>
                normalizedIndex({
                  keys,
                  options
                })
            )
            .sort(
              (left, right) =>
                serialized(left)
                  .localeCompare(
                    serialized(right)
                  )
            );

        return {
          model:
            modelName,
          collection,
          indexes
        };
      }
    )
      .sort(
        (left, right) =>
          left.collection
            .localeCompare(
              right.collection
            )
      );

  const collectionNames =
    collections.map(
      (entry) =>
        entry.collection
    );

  if (
    new Set(collectionNames).size !==
      collectionNames.length
  ) {
    managementError(
      'DUPLICATE_INDEX_COLLECTION'
    );
  }

  return canonicalValue({
    collections
  });
}

export function createIndexPlan(
  models
) {
  const manifest =
    buildIndexManifest(
      models
    );

  const indexCount =
    manifest.collections
      .reduce(
        (
          total,
          collection
        ) =>
          total +
          collection.indexes.length,
        0
      );

  const identityPayload =
    canonicalValue({
      version:
        INDEX_PLAN_VERSION,
      manifest
    });

  const digest =
    createHash('sha256')
      .update(
        JSON.stringify(
          identityPayload
        ),
        'utf8'
      )
      .digest('hex');

  return canonicalValue({
    kind:
      'merzox-mongodb-index-plan',
    version:
      INDEX_PLAN_VERSION,
    planId:
      `sha256:${digest}`,
    modelCount:
      manifest.collections.length,
    indexCount,
    collections:
      manifest.collections
  });
}

export function parseIndexMode(
  argv
) {
  if (
    !Array.isArray(argv) ||
    argv.length !== 1
  ) {
    managementError(
      'INDEX_MODE_REQUIRED'
    );
  }

  const mode =
    String(argv[0] ?? '')
      .trim();

  if (
    !INDEX_MODES.includes(
      mode
    )
  ) {
    managementError(
      'INVALID_INDEX_MODE'
    );
  }

  return mode;
}

export function validateIndexApplyApproval({
  env,
  planId
}) {
  if (
    env?.[
      INDEX_APPLY_ENV.allow
    ] !== 'true'
  ) {
    managementError(
      'INDEX_APPLY_OPT_IN_REQUIRED'
    );
  }

  const approvedPlanId =
    String(
      env?.[
        INDEX_APPLY_ENV.planId
      ] ?? ''
    ).trim();

  if (
    !approvedPlanId ||
    approvedPlanId !== planId
  ) {
    managementError(
      'INDEX_PLAN_APPROVAL_MISMATCH'
    );
  }

  return true;
}

export async function inspectIndexDrift(
  models
) {
  const manifest =
    buildIndexManifest(
      models
    );

  const byCollection =
    new Map(
      models.map(
        (model) => [
          model.collection
            .collectionName,
          model
        ]
      )
    );

  const drift = [];

  for (
    const entry of
    manifest.collections
  ) {
    const model =
      byCollection.get(
        entry.collection
      );

    if (
      typeof model?.diffIndexes !==
        'function'
    ) {
      managementError(
        'INDEX_DIFF_UNAVAILABLE'
      );
    }

    const result =
      await model.diffIndexes({
        indexOptionsToCreate:
          true
      });

    drift.push(
      canonicalValue({
        model:
          entry.model,
        collection:
          entry.collection,
        toDrop:
          [
            ...(
              result?.toDrop ??
              []
            )
          ].sort(),
        toCreate:
          result?.toCreate ??
          []
      })
    );
  }

  return drift;
}

export function isIndexDriftClean(
  drift
) {
  return (
    Array.isArray(drift) &&
    drift.every(
      (entry) =>
        Array.isArray(
          entry?.toDrop
        ) &&
        entry.toDrop.length === 0 &&
        Array.isArray(
          entry?.toCreate
        ) &&
        entry.toCreate.length === 0
    )
  );
}

export async function applyMissingIndexes({
  models,
  drift
}) {
  if (
    !Array.isArray(models) ||
    !Array.isArray(drift)
  ) {
    managementError(
      'INDEX_APPLY_INPUT_REQUIRED'
    );
  }

  if (
    drift.some(
      (entry) =>
        Array.isArray(
          entry?.toDrop
        ) &&
        entry.toDrop.length > 0
    )
  ) {
    managementError(
      'INDEX_DROP_REFUSED'
    );
  }

  const byCollection =
    new Map(
      models.map(
        (model) => [
          model.collection
            .collectionName,
          model
        ]
      )
    );

  const createdCollections = [];

  for (const entry of drift) {
    if (
      !Array.isArray(
        entry?.toCreate
      ) ||
      entry.toCreate.length === 0
    ) {
      continue;
    }

    const model =
      byCollection.get(
        entry.collection
      );

    if (
      typeof model?.createIndexes !==
        'function'
    ) {
      managementError(
        'INDEX_CREATE_UNAVAILABLE'
      );
    }

    await model.createIndexes();

    createdCollections.push(
      entry.collection
    );
  }

  return Object.freeze(
    createdCollections.sort()
  );
}
