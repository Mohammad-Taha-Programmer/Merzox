import { Business } from '../models/Business.js';
import { Favorite } from '../models/Favorite.js';
import { Order } from '../models/Order.js';
import {
  hasRecommendationConsent,
  recommendationConsentView
} from '../policies/recommendation.policy.js';
import { AppError } from '../utils/AppError.js';

const MAX_FAVORITE_SIGNALS = 200;
const MAX_ORDER_SIGNALS = 200;
const MAX_PREFERENCE_CATEGORIES = 8;
const RECOMMENDATION_LIMIT = 12;

const FAVORITE_BUSINESS_WEIGHT = 3;
const FAVORITE_PRODUCT_WEIGHT = 2;
const DELIVERED_ORDER_WEIGHT = 4;

function identity(value) {
  if (value === null || value === undefined) {
    return '';
  }

  return String(value);
}

function normalizedCategory(value) {
  if (typeof value !== 'string') {
    return '';
  }

  return value.trim();
}

function favoriteWeight(itemType) {
  if (itemType === 'business') {
    return FAVORITE_BUSINESS_WEIGHT;
  }

  if (itemType === 'product') {
    return FAVORITE_PRODUCT_WEIGHT;
  }

  return 0;
}

function comparePreferenceEntries(left, right) {
  if (left.score !== right.score) {
    return right.score - left.score;
  }

  if (left.category < right.category) return -1;
  if (left.category > right.category) return 1;
  return 0;
}

/**
 * Build an ephemeral category profile from already-authoritative server data.
 *
 * Nothing returned by this function is persisted. Search history, page views,
 * message contents and device-local activity are deliberately absent.
 */
export function buildCategoryPreferenceProfile({
  favorites = [],
  orders = [],
  businesses = []
} = {}) {
  const categoryByBusiness = new Map();

  for (const business of businesses) {
    const id = identity(business?._id);
    const category = normalizedCategory(business?.category);

    if (id && category) {
      categoryByBusiness.set(id, category);
    }
  }

  const scores = new Map();

  function addSignal(businessId, weight) {
    if (weight <= 0) {
      return;
    }

    const category = categoryByBusiness.get(identity(businessId));

    if (!category) {
      return;
    }

    scores.set(
      category,
      (scores.get(category) ?? 0) + weight
    );
  }

  for (const favorite of favorites) {
    addSignal(
      favorite?.business,
      favoriteWeight(favorite?.itemType)
    );
  }

  for (const order of orders) {
    addSignal(
      order?.business,
      DELIVERED_ORDER_WEIGHT
    );
  }

  return [...scores.entries()]
    .map(([category, score]) => ({
      category,
      score
    }))
    .sort(comparePreferenceEntries)
    .slice(0, MAX_PREFERENCE_CATEGORIES);
}

/**
 * Candidate ranking happens inside MongoDB and never writes.
 *
 * `$literal` prevents merchant-controlled category text beginning with "$"
 * from being interpreted as an aggregation field expression.
 */
export function recommendationPipeline(
  preferenceProfile = [],
  { excludeOwnerId } = {}
) {
  const branches = preferenceProfile.map(
    ({ category, score }) => ({
      case: {
        $eq: [
          '$category',
          { $literal: category }
        ]
      },
      then: score
    })
  );

  const affinity = branches.length === 0
    ? 0
    : {
        $switch: {
          branches,
          default: 0
        }
      };

  return [
    {
      $match: {
        isActive: true,
        ...(excludeOwnerId
          ? {
              owner: {
                $ne: excludeOwnerId
              }
            }
          : {})
      }
    },
    {
      $addFields: {
        __merzoxRecommendationAffinity: affinity
      }
    },
    {
      $sort: {
        __merzoxRecommendationAffinity: -1,
        ratingAverage: -1,
        ratingCount: -1,
        subscribedAt: -1,
        _id: 1
      }
    },
    {
      $limit: RECOMMENDATION_LIMIT
    },
    {
      $project: {
        _id: 1
      }
    }
  ];
}

async function readFavoriteSignals({
  userId,
  FavoriteModel
}) {
  return FavoriteModel.find({
    user: userId
  })
    .sort({
      createdAt: -1,
      _id: -1
    })
    .limit(MAX_FAVORITE_SIGNALS)
    .select({
      business: 1,
      itemType: 1
    })
    .lean()
    .exec();
}

async function readDeliveredOrderSignals({
  userId,
  OrderModel
}) {
  return OrderModel.find({
    user: userId,
    status: 'delivered'
  })
    .sort({
      deliveredAt: -1,
      _id: -1
    })
    .limit(MAX_ORDER_SIGNALS)
    .select({
      business: 1
    })
    .lean()
    .exec();
}

function signalBusinessIds({
  favorites,
  orders
}) {
  return [
    ...new Set(
      [
        ...favorites.map((favorite) => identity(favorite?.business)),
        ...orders.map((order) => identity(order?.business))
      ].filter(Boolean)
    )
  ];
}

async function readSignalBusinessCategories({
  ids,
  BusinessModel
}) {
  if (ids.length === 0) {
    return [];
  }

  return BusinessModel.find({
    _id: {
      $in: ids
    }
  })
    .select({
      _id: 1,
      category: 1
    })
    .lean()
    .exec();
}

async function rankedRecommendationIds({
  profile,
  userId,
  BusinessModel
}) {
  const rows = await BusinessModel.aggregate(
    recommendationPipeline(profile, {
      excludeOwnerId: userId
    })
  ).exec();

  return rows
    .map((row) => identity(row?._id))
    .filter(Boolean);
}

async function hydrateRankedBusinesses({
  ids,
  BusinessModel
}) {
  if (ids.length === 0) {
    return [];
  }

  // Re-assert activity because a business could be disabled between
  // aggregation and hydration.
  const businesses = await BusinessModel.find({
    _id: {
      $in: ids
    },
    isActive: true
  }).exec();

  const byId = new Map(
    businesses.map((business) => [
      identity(business?._id),
      business
    ])
  );

  return ids.flatMap((id) => {
    const business = byId.get(id);
    return business ? [business] : [];
  });
}

export async function buildRecommendationView({
  user,
  FavoriteModel = Favorite,
  OrderModel = Order,
  BusinessModel = Business
} = {}) {
  /**
   * This check intentionally precedes every model read.
   *
   * A missing, stale, malformed or denied consent state therefore performs
   * zero preference-signal queries.
   */
  if (!hasRecommendationConsent(user)) {
    throw new AppError(
      'Recommendation personalization consent is required',
      403,
      'RECOMMENDATION_CONSENT_REQUIRED'
    );
  }

  const userId = user?._id;

  const [
    favorites,
    orders
  ] = await Promise.all([
    readFavoriteSignals({
      userId,
      FavoriteModel
    }),
    readDeliveredOrderSignals({
      userId,
      OrderModel
    })
  ]);

  const ids = signalBusinessIds({
    favorites,
    orders
  });

  const signalBusinesses =
    await readSignalBusinessCategories({
      ids,
      BusinessModel
    });

  const profile =
    buildCategoryPreferenceProfile({
      favorites,
      orders,
      businesses: signalBusinesses
    });

  const rankedIds =
    await rankedRecommendationIds({
      profile,
      userId,
      BusinessModel
    });

  const businesses =
    await hydrateRankedBusinesses({
      ids: rankedIds,
      BusinessModel
    });

  return {
    consent: recommendationConsentView(user),
    personalized: profile.length > 0,

    // Expose ordered categories for transparency, but never expose raw
    // interaction counts or internal affinity scores.
    preferenceCategories: profile.map(
      ({ category }) => category
    ),

    recommendations: businesses.map(
      (business) => business.toListJSON()
    )
  };
}

export const recommendationLimits = Object.freeze({
  favoriteSignals: MAX_FAVORITE_SIGNALS,
  orderSignals: MAX_ORDER_SIGNALS,
  preferenceCategories: MAX_PREFERENCE_CATEGORIES,
  recommendations: RECOMMENDATION_LIMIT
});
