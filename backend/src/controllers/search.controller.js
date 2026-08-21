import { Business } from '../models/Business.js';
import { asyncHandler } from '../utils/asyncHandler.js';

function escapeRegex(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function normalizeQuery(query) {
  return String(query ?? '').trim().slice(0, 80);
}

export const searchCatalog = asyncHandler(async (req, res) => {
  const query = normalizeQuery(req.query.query ?? req.query.q);
  const limit = Math.min(
    Math.max(Number.parseInt(req.query.limit ?? '30', 10), 1),
    50
  );

  if (!query) {
    res.json({
      success: true,
      data: { query: '', products: [], businesses: [] }
    });
    return;
  }

  const pattern = new RegExp(escapeRegex(query), 'i');
  const businesses = await Business.find({
    isActive: true,
    $or: [
      { name: pattern },
      { category: pattern },
      { description: pattern },
      { 'products.name': pattern },
      { 'products.description': pattern }
    ]
  })
    .sort({ ratingAverage: -1, subscribedAt: -1 })
    .limit(80);

  const products = [];
  const matchedBusinessIds = new Set();

  for (const business of businesses) {
    const businessMatches =
      pattern.test(business.name) ||
      pattern.test(business.category) ||
      pattern.test(business.description ?? '');

    for (const product of business.products) {
      if (!product.isActive) continue;

      const productMatches =
        pattern.test(product.name) ||
        pattern.test(product.description ?? '') ||
        businessMatches;

      if (!productMatches) continue;

      if (products.length < limit) {
        products.push({
          ...business.productToJSON(product),
          business: {
            id: business._id.toString(),
            publicId: business.publicId,
            name: business.name,
            category: business.category,
            colorValue: business.colorValue,
            rating: business.ratingAverage,
            address: business.address
          }
        });
      }

      matchedBusinessIds.add(business._id.toString());
    }
  }

  const matchedBusinesses = businesses
    .filter((business) => {
      return (
        matchedBusinessIds.has(business._id.toString()) ||
        pattern.test(business.name) ||
        pattern.test(business.category) ||
        pattern.test(business.description ?? '')
      );
    })
    .slice(0, limit)
    .map((business) => business.toListJSON());

  res.json({
    success: true,
    data: {
      query,
      products,
      businesses: matchedBusinesses
    }
  });
});
