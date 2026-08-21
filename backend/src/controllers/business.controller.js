import { Business } from '../models/Business.js';
import { BusinessReview } from '../models/BusinessReview.js';
import { Favorite } from '../models/Favorite.js';
import { ProductReview } from '../models/ProductReview.js';
import { requireBoolean } from './favorite.controller.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { AppError } from '../utils/AppError.js';

const validProductClassifications = new Set(['new', 'bestSelling', 'offers']);

function paginationParams(query) {
  const parsedPage = Number.parseInt(query.page ?? '1', 10);
  const parsedLimit = Number.parseInt(query.limit ?? '100', 10);
  const page = Number.isFinite(parsedPage) ? Math.max(parsedPage, 1) : 1;
  const limit = Number.isFinite(parsedLimit)
    ? Math.min(Math.max(parsedLimit, 1), 100)
    : 100;

  return { page, limit, skip: (page - 1) * limit };
}

function buildBusinessFilter(query) {
  const filter = { isActive: true };
  const search = String(query.search ?? '').trim();

  if (search) {
    filter.$text = { $search: search };
  }

  return filter;
}

function buildNearbyBusinessFilter(query) {
  const filter = { isActive: true };
  const search = String(query.search ?? '').trim().slice(0, 80);

  if (search) {
    const escaped = search.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    filter.$or = [
      { name: { $regex: escaped, $options: 'i' } },
      { category: { $regex: escaped, $options: 'i' } },
      { 'products.name': { $regex: escaped, $options: 'i' } }
    ];
  }

  return filter;
}

function nearbyParams(query) {
  const latitude = Number(query.lat ?? query.latitude);
  const longitude = Number(query.lng ?? query.longitude);

  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
    return null;
  }

  if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
    return null;
  }

  const parsedRadius = Number.parseInt(query.radiusMeters ?? '10000', 10);
  const radiusMeters = Number.isFinite(parsedRadius)
    ? Math.min(Math.max(parsedRadius, 100), 50000)
    : 10000;

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
  const { page, limit, skip } = paginationParams(req.query);
  const nearby = nearbyParams(req.query);
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
      { $sort: { distanceMeters: 1, subscribedAt: -1, _id: -1 } },
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
      .sort({ subscribedAt: -1, _id: -1 })
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
  const business = await findBusiness(req.params.id);

  if (!business || !business.isActive) {
    throw new AppError('Business not found', 404, 'BUSINESS_NOT_FOUND');
  }

  const classification = validProductClassifications.has(req.query.classification)
    ? req.query.classification
    : 'new';
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
  const { page, limit, skip } = paginationParams({
    ...req.query,
    limit: req.query.limit ?? '20'
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

export const createBusinessProductReview = asyncHandler(async (req, res) => {
  const { business, product } = await findActiveBusinessProduct(
    req.params.id,
    req.params.productId
  );
  const rating = Number(req.body.rating);

  if (!Number.isFinite(rating) || rating < 1 || rating > 5) {
    throw new AppError('Rating must be between 1 and 5', 400, 'INVALID_RATING');
  }

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

  res.status(201).json({
    success: true,
    data: {
      review: review.toJSONView(),
      product: business.productToJSON(product)
    }
  });
});

export const listBusinessReviews = asyncHandler(async (req, res) => {
  const { page, limit, skip } = paginationParams({ ...req.query, limit: req.query.limit ?? '20' });
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

export const createBusinessReview = asyncHandler(async (req, res) => {
  const business = await findBusiness(req.params.id);

  if (!business || !business.isActive) {
    throw new AppError('Business not found', 404, 'BUSINESS_NOT_FOUND');
  }

  const rating = Number(req.body.rating);
  if (!Number.isFinite(rating) || rating < 1 || rating > 5) {
    throw new AppError('Rating must be between 1 and 5', 400, 'INVALID_RATING');
  }

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
