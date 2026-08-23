import { Business } from '../models/Business.js';
import { BusinessReview } from '../models/BusinessReview.js';
import { Favorite } from '../models/Favorite.js';
import { ProductReview } from '../models/ProductReview.js';
import { requireBoolean } from './favorite.controller.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { notifyNewReview } from '../services/notification.service.js';
import {
  assertReviewEligible,
  getReviewEligibility
} from '../services/review-eligibility.service.js';
import { AppError } from '../utils/AppError.js';
import {
  decimalParam,
  enumParam,
  paginationParams as sharedPaginationParams,
  positiveIntegerParam,
  rejectPollutedQueryParams
} from '../policies/query.policy.js';

const productClassifications = ['new', 'bestSelling', 'offers'];
const businessSorts = ['newest', 'rating'];

const BUSINESS_DEFAULT_LIMIT = 100;
const BUSINESS_MAX_LIMIT = 100;
const REVIEW_DEFAULT_LIMIT = 20;
const DEFAULT_RADIUS_METERS = 10000;
const MIN_RADIUS_METERS = 100;
const MAX_RADIUS_METERS = 50000;

const BUSINESS_LIST_POLLUTED_QUERY_CODES = Object.freeze({
  page: 'INVALID_PAGE',
  limit: 'INVALID_LIMIT',
  sort: 'INVALID_BUSINESS_SORT',
  discounted: 'INVALID_DISCOUNTED_FILTER',
  search: 'INVALID_BUSINESS_SEARCH',
  lat: 'INVALID_LATITUDE',
  latitude: 'INVALID_LATITUDE',
  lng: 'INVALID_LONGITUDE',
  longitude: 'INVALID_LONGITUDE',
  radiusMeters: 'INVALID_RADIUS_METERS'
});

const BUSINESS_PRODUCTS_POLLUTED_QUERY_CODES = Object.freeze({
  classification: 'INVALID_PRODUCT_CLASSIFICATION'
});

const BUSINESS_REVIEWS_POLLUTED_QUERY_CODES = Object.freeze({
  page: 'INVALID_PAGE',
  limit: 'INVALID_LIMIT'
});

export function paginationParams(
  query = {},
  { limitFallback = BUSINESS_DEFAULT_LIMIT } = {}
) {
  return sharedPaginationParams(query, {
    limitFallback,
    maxLimit: BUSINESS_MAX_LIMIT,
    allowBlankAsFallback: false,
    allowSurroundingWhitespace: false
  });
}

export function discountedParam(query = {}) {
  return (
    enumParam(query.discounted, {
      name: 'discounted',
      allowed: ['true', 'false'],
      fallback: 'false',
      code: 'INVALID_DISCOUNTED_FILTER',
      allowBlankAsFallback: false,
      allowSurroundingWhitespace: false
    }) === 'true'
  );
}

export function businessSort(query = {}) {
  const requestedSort = enumParam(query.sort, {
    name: 'sort',
    allowed: businessSorts,
    fallback: 'newest',
    code: 'INVALID_BUSINESS_SORT',
    allowBlankAsFallback: false,
    allowSurroundingWhitespace: false
  });

  if (requestedSort === 'rating') {
    return {
      ratingAverage: -1,
      ratingCount: -1,
      subscribedAt: -1,
      _id: -1
    };
  }

  return { subscribedAt: -1, _id: -1 };
}

export function classificationParam(query = {}) {
  return enumParam(query.classification, {
    name: 'classification',
    allowed: productClassifications,
    fallback: 'new',
    code: 'INVALID_PRODUCT_CLASSIFICATION',
    allowBlankAsFallback: false,
    allowSurroundingWhitespace: false
  });
}

export function searchParam(query = {}) {
  const value = query.search;

  if (value === undefined || value === null) {
    return '';
  }

  if (Array.isArray(value)) {
    throw new AppError(
      'search is invalid',
      400,
      'INVALID_BUSINESS_SEARCH'
    );
  }

  return String(value).trim().slice(0, 80);
}

export function nearbyBusinessSort() {
  return { distanceMeters: 1, subscribedAt: -1, _id: -1 };
}

function applyDiscountFilter(filter, query) {
  if (discountedParam(query)) {
    filter.discountLabel = { $exists: true, $type: 'string', $ne: '' };
  }

  return filter;
}

export function buildBusinessFilter(query) {
  const filter = { isActive: true };
  const search = searchParam(query);

  if (search) {
    filter.$text = { $search: search };
  }

  return applyDiscountFilter(filter, query);
}

export function buildNearbyBusinessFilter(query) {
  const filter = { isActive: true };
  const search = searchParam(query);

  if (search) {
    const escaped = search.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    filter.$or = [
      { name: { $regex: escaped, $options: 'i' } },
      { category: { $regex: escaped, $options: 'i' } },
      { 'products.name': { $regex: escaped, $options: 'i' } }
    ];
  }

  return applyDiscountFilter(filter, query);
}

export function nearbyParams(query = {}) {
  const hasLat = query.lat !== undefined;
  const hasLatitude = query.latitude !== undefined;
  const hasLng = query.lng !== undefined;
  const hasLongitude = query.longitude !== undefined;
  const hasRadius = query.radiusMeters !== undefined;

  const hasNearbyInput =
    hasLat || hasLatitude || hasLng || hasLongitude || hasRadius;

  if (!hasNearbyInput) {
    return null;
  }

  if (
    (hasLat && hasLatitude) ||
    (hasLng && hasLongitude)
  ) {
    throw new AppError(
      'Nearby coordinate aliases are ambiguous',
      400,
      'AMBIGUOUS_NEARBY_COORDINATES'
    );
  }

  const hasLatitudeValue = hasLat || hasLatitude;
  const hasLongitudeValue = hasLng || hasLongitude;

  if (!hasLatitudeValue || !hasLongitudeValue) {
    throw new AppError(
      'A complete latitude and longitude pair is required',
      400,
      'INCOMPLETE_NEARBY_COORDINATES'
    );
  }

  const latitude = decimalParam(
    hasLat ? query.lat : query.latitude,
    {
      name: 'latitude',
      min: -90,
      max: 90,
      code: 'INVALID_LATITUDE'
    }
  );

  const longitude = decimalParam(
    hasLng ? query.lng : query.longitude,
    {
      name: 'longitude',
      min: -180,
      max: 180,
      code: 'INVALID_LONGITUDE'
    }
  );

  const parsedRadius = positiveIntegerParam(query.radiusMeters, {
    name: 'radiusMeters',
    fallback: DEFAULT_RADIUS_METERS,
    max: MAX_RADIUS_METERS,
    code: 'INVALID_RADIUS_METERS',
    allowBlankAsFallback: false,
    allowSurroundingWhitespace: false
  });

  const radiusMeters = Math.max(parsedRadius, MIN_RADIUS_METERS);

  return { latitude, longitude, radiusMeters };
}

function businessListView(business) {
  const json = Business.hydrate(business).toListJSON();

  if (business.distanceMeters !== undefined) {
    json.distanceMeters = Math.round(business.distanceMeters);
  }

  return json;
}

export const listBusinesses = asyncHandler(async (req, res) => {
  rejectPollutedQueryParams(req, BUSINESS_LIST_POLLUTED_QUERY_CODES);

  const { page, limit, skip } = paginationParams(req.query);
  const nearby = nearbyParams(req.query);
  const sort = businessSort(req.query);
  const filter = nearby
    ? buildNearbyBusinessFilter(req.query)
    : buildBusinessFilter(req.query);

  if (nearby) {
    const [result] = await Business.aggregate([
      {
        $geoNear: {
          near: {
            type: 'Point',
            coordinates: [nearby.longitude, nearby.latitude]
          },
          distanceField: 'distanceMeters',
          maxDistance: nearby.radiusMeters,
          spherical: true,
          query: filter
        }
      },
      { $sort: nearbyBusinessSort() },
      {
        $facet: {
          items: [{ $skip: skip }, { $limit: limit }],
          total: [{ $count: 'count' }]
        }
      }
    ]);

    const items = result?.items ?? [];
    const total = result?.total?.[0]?.count ?? 0;

    return res.json({
      success: true,
      data: {
        businesses: items.map(businessListView),
        pagination: {
          page,
          limit,
          total,
          hasMore: skip + items.length < total
        }
      }
    });
  }

  const [items, total] = await Promise.all([
    Business.find(filter)
      .sort(sort)
      .skip(skip)
      .limit(limit)
      .lean(false),
    Business.countDocuments(filter)
  ]);

  res.json({
    success: true,
    data: {
      businesses: items.map((business) => business.toListJSON()),
      pagination: {
        page,
        limit,
        total,
        hasMore: skip + items.length < total
      }
    }
  });
});

export const getBusiness = asyncHandler(async (req, res) => {
  const business = await findBusiness(req.params.id);

  if (!business || !business.isActive) {
    throw new AppError('Business not found', 404, 'BUSINESS_NOT_FOUND');
  }

  await Business.updateOne({ _id: business._id }, { $inc: { viewCount: 1 } });
  business.viewCount += 1;

  res.json({ success: true, data: { business: business.toDetailJSON() } });
});

export const listBusinessProducts = asyncHandler(async (req, res) => {
  rejectPollutedQueryParams(
    req,
    BUSINESS_PRODUCTS_POLLUTED_QUERY_CODES
  );

  const classification = classificationParam(req.query);
  const business = await findBusiness(req.params.id);

  if (!business || !business.isActive) {
    throw new AppError('Business not found', 404, 'BUSINESS_NOT_FOUND');
  }
  const products = business.products
    .filter((product) => product.isActive && product.classification === classification)
    .map((product) => business.productToJSON(product));

  res.json({ success: true, data: { products } });
});

export const getBusinessProduct = asyncHandler(async (req, res) => {
  const { business, product } = await findActiveBusinessProduct(
    req.params.id,
    req.params.productId
  );

  res.json({
    success: true,
    data: { product: business.productToJSON(product) }
  });
});

export const likeBusinessProduct = asyncHandler(async (req, res) => {
  const business = await findBusiness(req.params.id);

  if (!business || !business.isActive) {
    throw new AppError('Business not found', 404, 'BUSINESS_NOT_FOUND');
  }

  const product = business.products.id(req.params.productId);
  if (!product || !product.isActive) {
    throw new AppError('Product not found', 404, 'PRODUCT_NOT_FOUND');
  }

  const liked = requireBoolean(req.body, 'liked');
  const filter = {
    user: req.user._id,
    itemType: 'product',
    business: business._id,
    productId: product._id
  };

  if (liked) {
    await Favorite.updateOne(
      filter,
      { $setOnInsert: filter },
      { upsert: true, runValidators: true }
    );
  } else {
    await Favorite.deleteOne(filter);
  }

  const likeCount = await Favorite.countDocuments({
    itemType: 'product',
    business: business._id,
    productId: product._id
  });
  await Business.updateOne(
    { _id: business._id },
    { $set: { 'products.$[product].likeCount': likeCount } },
    { arrayFilters: [{ 'product._id': product._id }] }
  );
  product.likeCount = likeCount;

  res.json({
    success: true,
    data: { product: business.productToJSON(product), liked }
  });
});

export const listBusinessProductReviews = asyncHandler(async (req, res) => {
  rejectPollutedQueryParams(
    req,
    BUSINESS_REVIEWS_POLLUTED_QUERY_CODES
  );

  const { page, limit, skip } = paginationParams(req.query, {
    limitFallback: REVIEW_DEFAULT_LIMIT
  });
  const { business } = await findActiveBusinessProduct(
    req.params.id,
    req.params.productId
  );
  const productId = String(req.params.productId);

  const [items, total] = await Promise.all([
    ProductReview.find({ business: business._id, productId })
      .sort({ createdAt: -1, _id: -1 })
      .skip(skip)
      .limit(limit),
    ProductReview.countDocuments({ business: business._id, productId })
  ]);

  res.json({
    success: true,
    data: {
      reviews: items.map((review) => review.toJSONView()),
      pagination: { page, limit, total, hasMore: skip + items.length < total }
    }
  });
});

export const getBusinessProductReviewEligibility = asyncHandler(
  async (req, res) => {
    const { business, product } = await findActiveBusinessProduct(
      req.params.id,
      req.params.productId
    );

    const eligibility = await getReviewEligibility({
      user: req.user,
      businessId: business._id,
      productId: product._id
    });

    res.json({
      success: true,
      data: { eligibility }
    });
  }
);

export const createBusinessProductReview = asyncHandler(async (req, res) => {
  const { business, product } = await findActiveBusinessProduct(
    req.params.id,
    req.params.productId
  );
  const rating = Number(req.body.rating);

  if (!Number.isFinite(rating) || rating < 1 || rating > 5) {
    throw new AppError('Rating must be between 1 and 5', 400, 'INVALID_RATING');
  }

  await assertReviewEligible({
    user: req.user,
    businessId: business._id,
    productId: product._id
  });

  const productId = String(product._id);
  const review = await ProductReview.findOneAndUpdate(
    { business: business._id, productId, user: req.user._id },
    {
      business: business._id,
      productId,
      user: req.user._id,
      userName: req.user.name,
      rating,
      comment: String(req.body.comment ?? '').trim()
    },
    { upsert: true, new: true, setDefaultsOnInsert: true }
  );

  const aggregate = await ProductReview.aggregate([
    { $match: { business: business._id, productId } },
    {
      $group: {
        _id: '$productId',
        ratingAverage: { $avg: '$rating' },
        ratingCount: { $sum: 1 }
      }
    }
  ]);

  product.ratingAverage = aggregate[0]?.ratingAverage ?? 0;
  product.ratingCount = aggregate[0]?.ratingCount ?? 0;
  await business.save();

  if (business.owner) {
    await notifyNewReview({
      ownerId: business.owner,
      businessId: business._id,
      reviewerName: req.user.name,
      rating,
      target: 'product'
    });
  }

  res.status(201).json({
    success: true,
    data: {
      review: review.toJSONView(),
      product: business.productToJSON(product)
    }
  });
});

export const listBusinessReviews = asyncHandler(async (req, res) => {
  rejectPollutedQueryParams(
    req,
    BUSINESS_REVIEWS_POLLUTED_QUERY_CODES
  );

  const { page, limit, skip } = paginationParams(req.query, {
    limitFallback: REVIEW_DEFAULT_LIMIT
  });
  const business = await findBusiness(req.params.id);

  if (!business || !business.isActive) {
    throw new AppError('Business not found', 404, 'BUSINESS_NOT_FOUND');
  }

  const [items, total] = await Promise.all([
    BusinessReview.find({ business: business._id })
      .sort({ createdAt: -1, _id: -1 })
      .skip(skip)
      .limit(limit),
    BusinessReview.countDocuments({ business: business._id })
  ]);

  res.json({
    success: true,
    data: {
      reviews: items.map((review) => review.toJSONView()),
      pagination: { page, limit, total, hasMore: skip + items.length < total }
    }
  });
});

export const getBusinessReviewEligibility = asyncHandler(
  async (req, res) => {
    const business = await findBusiness(req.params.id);

    if (!business || !business.isActive) {
      throw new AppError(
        'Business not found',
        404,
        'BUSINESS_NOT_FOUND'
      );
    }

    const eligibility = await getReviewEligibility({
      user: req.user,
      businessId: business._id
    });

    res.json({
      success: true,
      data: { eligibility }
    });
  }
);

export const createBusinessReview = asyncHandler(async (req, res) => {
  const business = await findBusiness(req.params.id);

  if (!business || !business.isActive) {
    throw new AppError('Business not found', 404, 'BUSINESS_NOT_FOUND');
  }

  const rating = Number(req.body.rating);
  if (!Number.isFinite(rating) || rating < 1 || rating > 5) {
    throw new AppError('Rating must be between 1 and 5', 400, 'INVALID_RATING');
  }

  await assertReviewEligible({
    user: req.user,
    businessId: business._id
  });

  const review = await BusinessReview.findOneAndUpdate(
    { business: business._id, user: req.user._id },
    {
      business: business._id,
      user: req.user._id,
      userName: req.user.name,
      rating,
      comment: String(req.body.comment ?? '').trim()
    },
    { upsert: true, new: true, setDefaultsOnInsert: true }
  );

  const aggregate = await BusinessReview.aggregate([
    { $match: { business: business._id } },
    {
      $group: {
        _id: '$business',
        ratingAverage: { $avg: '$rating' },
        ratingCount: { $sum: 1 }
      }
    }
  ]);

  business.ratingAverage = aggregate[0]?.ratingAverage ?? 0;
  business.ratingCount = aggregate[0]?.ratingCount ?? 0;
  await business.save();

  if (business.owner) {
    await notifyNewReview({
      ownerId: business.owner,
      businessId: business._id,
      reviewerName: req.user.name,
      rating,
      target: 'business'
    });
  }

  res.status(201).json({
    success: true,
    data: {
      review: review.toJSONView(),
      business: business.toListJSON()
    }
  });
});

function findBusiness(id) {
  if (/^[a-f\d]{24}$/i.test(id)) {
    return Business.findById(id);
  }

  return Business.findOne({ publicId: id });
}

async function findActiveBusinessProduct(businessId, productId) {
  const business = await findBusiness(businessId);

  if (!business || !business.isActive) {
    throw new AppError('Business not found', 404, 'BUSINESS_NOT_FOUND');
  }

  const product = business.products.id(productId);
  if (!product || !product.isActive) {
    throw new AppError('Product not found', 404, 'PRODUCT_NOT_FOUND');
  }

  return { business, product };
}
