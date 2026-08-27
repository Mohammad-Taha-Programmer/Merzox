import assert from 'node:assert/strict';
import test from 'node:test';

import {
  buildCategoryPreferenceProfile,
  buildRecommendationView,
  recommendationLimits,
  recommendationPipeline
} from '../src/services/recommendation.service.js';

function consentedUser() {
  return {
    _id: 'user-1',
    permissions: {
      aiPersonalization: true
    },
    permissionConsents: {
      aiPersonalization: {
        status: 'granted'
      }
    }
  };
}

class FakeQuery {
  constructor(result, record = {}) {
    this.result = result;
    this.record = record;
  }

  sort(value) {
    this.record.sort = value;
    return this;
  }

  limit(value) {
    this.record.limit = value;
    return this;
  }

  select(value) {
    this.record.select = value;
    return this;
  }

  lean() {
    this.record.lean = true;
    return this;
  }

  exec() {
    return Promise.resolve(this.result);
  }
}

function businessDocument({
  id,
  category
}) {
  return {
    _id: id,
    toListJSON() {
      return {
        id,
        category
      };
    }
  };
}

function fakeModels({
  favorites = [],
  orders = [],
  signalBusinesses = [],
  rankedIds = [],
  recommendationBusinesses = []
} = {}) {
  const calls = {
    favorites: [],
    orders: [],
    businessFind: [],
    aggregate: []
  };

  const FavoriteModel = {
    find(filter) {
      const record = { filter };
      calls.favorites.push(record);
      return new FakeQuery(favorites, record);
    }
  };

  const OrderModel = {
    find(filter) {
      const record = { filter };
      calls.orders.push(record);
      return new FakeQuery(orders, record);
    }
  };

  const BusinessModel = {
    find(filter) {
      const record = { filter };
      calls.businessFind.push(record);

      const signalLookup =
        filter?.isActive !== true &&
        filter?._id?.$in;

      return new FakeQuery(
        signalLookup
          ? signalBusinesses
          : recommendationBusinesses,
        record
      );
    },

    aggregate(pipeline) {
      calls.aggregate.push(pipeline);

      return {
        async exec() {
          return rankedIds.map(
            (_id) => ({ _id })
          );
        }
      };
    }
  };

  return {
    calls,
    FavoriteModel,
    OrderModel,
    BusinessModel
  };
}

test('category analysis uses only bounded favorite and delivered-order signals', () => {
  const profile = buildCategoryPreferenceProfile({
    favorites: [
      {
        business: 'food-1',
        itemType: 'business'
      },
      {
        business: 'tech-1',
        itemType: 'product'
      }
    ],
    orders: [
      { business: 'food-1' },
      { business: 'food-1' },
      { business: 'tech-1' }
    ],
    businesses: [
      {
        _id: 'food-1',
        category: 'Food'
      },
      {
        _id: 'tech-1',
        category: 'Technology'
      }
    ]
  });

  assert.deepEqual(
    profile,
    [
      {
        category: 'Food',
        score: 11
      },
      {
        category: 'Technology',
        score: 6
      }
    ]
  );
});

test('recommendation pipeline is active-only deterministic and contains no write stage', () => {
  const pipeline = recommendationPipeline([
    {
      category: '$special-category',
      score: 7
    }
  ]);

  assert.deepEqual(
    pipeline[0],
    {
      $match: {
        isActive: true
      }
    }
  );

  assert.deepEqual(
    pipeline[1].$addFields
      .__merzoxRecommendationAffinity
      .$switch.branches[0],
    {
      case: {
        $eq: [
          '$category',
          {
            $literal: '$special-category'
          }
        ]
      },
      then: 7
    }
  );

  assert.deepEqual(
    pipeline[2],
    {
      $sort: {
        __merzoxRecommendationAffinity: -1,
        ratingAverage: -1,
        ratingCount: -1,
        subscribedAt: -1,
        _id: 1
      }
    }
  );

  assert.deepEqual(
    pipeline[3],
    {
      $limit: recommendationLimits.recommendations
    }
  );

  const source = JSON.stringify(pipeline);

  assert.equal(source.includes('$out'), false);
  assert.equal(source.includes('$merge'), false);

  assert.equal(
    recommendationPipeline([])[1]
      .$addFields.__merzoxRecommendationAffinity,
    0
  );
});

test('missing recommendation consent performs zero signal or catalog reads', async () => {
  let reads = 0;

  const forbiddenModel = {
    find() {
      reads += 1;
      throw new Error('model read must not occur');
    },
    aggregate() {
      reads += 1;
      throw new Error('aggregate must not occur');
    }
  };

  await assert.rejects(
    () =>
      buildRecommendationView({
        user: {
          _id: 'user-1',
          permissions: {
            aiPersonalization: true
          },
          permissionConsents: {
            aiPersonalization: {
              status: 'denied'
            }
          }
        },
        FavoriteModel: forbiddenModel,
        OrderModel: forbiddenModel,
        BusinessModel: forbiddenModel
      }),
    (error) => {
      assert.equal(
        error?.code,
        'RECOMMENDATION_CONSENT_REQUIRED'
      );
      assert.equal(error?.statusCode, 403);
      return true;
    }
  );

  assert.equal(reads, 0);
});

test('recommendation view reads favorites and delivered orders then preserves server ranking', async () => {
  const models = fakeModels({
    favorites: [
      {
        business: 'food-1',
        itemType: 'business'
      }
    ],
    orders: [
      {
        business: 'tech-1'
      }
    ],
    signalBusinesses: [
      {
        _id: 'food-1',
        category: 'Food'
      },
      {
        _id: 'tech-1',
        category: 'Technology'
      }
    ],
    rankedIds: [
      'recommended-tech',
      'recommended-food'
    ],

    // Deliberately reversed to prove aggregate order is restored after
    // hydration.
    recommendationBusinesses: [
      businessDocument({
        id: 'recommended-food',
        category: 'Food'
      }),
      businessDocument({
        id: 'recommended-tech',
        category: 'Technology'
      })
    ]
  });

  const view = await buildRecommendationView({
    user: consentedUser(),
    FavoriteModel: models.FavoriteModel,
    OrderModel: models.OrderModel,
    BusinessModel: models.BusinessModel
  });

  assert.equal(
    models.calls.favorites.length,
    1
  );

  assert.deepEqual(
    models.calls.favorites[0].filter,
    {
      user: 'user-1'
    }
  );

  assert.equal(
    models.calls.favorites[0].limit,
    recommendationLimits.favoriteSignals
  );

  assert.deepEqual(
    models.calls.orders[0].filter,
    {
      user: 'user-1',
      status: 'delivered'
    }
  );

  assert.equal(
    models.calls.orders[0].limit,
    recommendationLimits.orderSignals
  );

  assert.equal(
    models.calls.aggregate.length,
    1
  );

  // SELF_OWNED_BUSINESS_EXCLUSION
  assert.deepEqual(
    models.calls.aggregate[0][0],
    {
      $match: {
        isActive: true,
        owner: {
          $ne: 'user-1'
        }
      }
    }
  );

  assert.deepEqual(
    view.consent,
    {
      enabled: true,
      status: 'granted'
    }
  );

  assert.equal(view.personalized, true);

  // Delivered order weight (4) ranks above business favorite weight (3).
  assert.deepEqual(
    view.preferenceCategories,
    [
      'Technology',
      'Food'
    ]
  );

  assert.deepEqual(
    view.recommendations,
    [
      {
        id: 'recommended-tech',
        category: 'Technology'
      },
      {
        id: 'recommended-food',
        category: 'Food'
      }
    ]
  );

  assert.equal(
    Object.prototype.hasOwnProperty.call(
      view,
      'scores'
    ),
    false
  );
});

test('consented user with no signals receives generic ranking without a fake profile', async () => {
  const models = fakeModels({
    rankedIds: [
      'generic-1'
    ],
    recommendationBusinesses: [
      businessDocument({
        id: 'generic-1',
        category: 'General'
      })
    ]
  });

  const view = await buildRecommendationView({
    user: consentedUser(),
    FavoriteModel: models.FavoriteModel,
    OrderModel: models.OrderModel,
    BusinessModel: models.BusinessModel
  });

  assert.equal(view.personalized, false);
  assert.deepEqual(
    view.preferenceCategories,
    []
  );

  assert.deepEqual(
    view.recommendations,
    [
      {
        id: 'generic-1',
        category: 'General'
      }
    ]
  );

  assert.equal(
    models.calls.businessFind.length,
    1
  );

  assert.equal(
    models.calls.aggregate.length,
    1
  );

  assert.equal(
    models.calls.aggregate[0][1]
      .$addFields.__merzoxRecommendationAffinity,
    0
  );
});
