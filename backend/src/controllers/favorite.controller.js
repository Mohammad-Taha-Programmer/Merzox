import { Business } from '../models/Business.js';
import { Favorite } from '../models/Favorite.js';
import { AppError } from '../utils/AppError.js';
import { asyncHandler } from '../utils/asyncHandler.js';

function paginationParams(query) {
  const page = Math.max(Number.parseInt(query.page ?? '1', 10), 1);
  const limit = Math.min(
    Math.max(Number.parseInt(query.limit ?? '20', 10), 1),
    100
  );

  return { page, limit, skip: (page - 1) * limit };
}

function findBusiness(id) {
  if (/^[a-f\d]{24}$/i.test(id)) {
    return Business.findById(id);
  }

  return Business.findOne({ publicId: id });
}

async function requireActiveBusiness(id) {
  const business = await findBusiness(id);
  if (!business || !business.isActive) {
    throw new AppError('Business not found', 404, 'BUSINESS_NOT_FOUND');
  }
  return business;
}

function requireBoolean(body, field) {
  if (typeof body[field] !== 'boolean') {
    throw new AppError(
      `${field} must be a boolean`,
      400,
      'INVALID_FAVORITE_VALUE'
    );
  }
  return body[field];
}

export const listFavoriteBusinesses = asyncHandler(async (req, res) => {
  const { page, limit, skip } = paginationParams(req.query);
  const filter = { user: req.user._id, itemType: 'business' };
  const [favorites, total] = await Promise.all([
    Favorite.find(filter)
      .sort({ createdAt: -1, _id: -1 })
      .skip(skip)
      .limit(limit)
      .populate({ path: 'business', match: { isActive: true } }),
    Favorite.countDocuments(filter)
  ]);

  const businesses = favorites
    .filter((favorite) => favorite.business)
    .map((favorite) => ({
      ...favorite.business.toListJSON(),
      favoritedAt: favorite.createdAt
    }));

  res.json({
    success: true,
    data: {
      businesses,
      pagination: {
        page,
        limit,
        total,
        hasMore: skip + favorites.length < total
      }
    }
  });
});

export const listFavoriteProducts = asyncHandler(async (req, res) => {
  const { page, limit, skip } = paginationParams(req.query);
  const filter = { user: req.user._id, itemType: 'product' };
  const [favorites, total] = await Promise.all([
    Favorite.find(filter)
      .sort({ createdAt: -1, _id: -1 })
      .skip(skip)
      .limit(limit)
      .lean(),
    Favorite.countDocuments(filter)
  ]);

  const businessIds = [...new Set(favorites.map((item) => String(item.business)))];
  const businesses = await Business.find({
    _id: { $in: businessIds },
    isActive: true
  });
  const businessById = new Map(
    businesses.map((business) => [business._id.toString(), business])
  );

  const products = favorites.flatMap((favorite) => {
    const business = businessById.get(String(favorite.business));
    const product = business?.products.id(favorite.productId);
    if (!business || !product || !product.isActive) return [];

    return [
      {
        business: business.toListJSON(),
        product: business.productToJSON(product),
        favoritedAt: favorite.createdAt
      }
    ];
  });

  res.json({
    success: true,
    data: {
      products,
      pagination: {
        page,
        limit,
        total,
        hasMore: skip + favorites.length < total
      }
    }
  });
});

export const getBusinessFavoriteStatus = asyncHandler(async (req, res) => {
  const business = await requireActiveBusiness(req.params.businessId);
  const favorites = await Favorite.find({
    user: req.user._id,
    business: business._id
  }).lean();

  res.json({
    success: true,
    data: {
      businessId: business._id.toString(),
      businessFavorited: favorites.some(
        (favorite) => favorite.itemType === 'business'
      ),
      productIds: favorites
        .filter((favorite) => favorite.itemType === 'product')
        .map((favorite) => favorite.productId.toString())
    }
  });
});

export const setBusinessFavorite = asyncHandler(async (req, res) => {
  const business = await requireActiveBusiness(req.params.id);
  const favorited = requireBoolean(req.body, 'favorited');
  const filter = {
    user: req.user._id,
    itemType: 'business',
    business: business._id
  };

  if (favorited) {
    await Favorite.updateOne(
      filter,
      { $setOnInsert: filter },
      { upsert: true, runValidators: true }
    );
  } else {
    await Favorite.deleteOne(filter);
  }

  const followerCount = await Favorite.countDocuments({
    itemType: 'business',
    business: business._id
  });
  await Business.updateOne(
    { _id: business._id },
    { $set: { followerCount } }
  );
  business.followerCount = followerCount;

  res.json({
    success: true,
    data: {
      business: business.toListJSON(),
      favorited
    }
  });
});

export { requireBoolean };
