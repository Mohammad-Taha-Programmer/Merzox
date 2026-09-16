import { Business } from '../models/Business.js';
import {
  matchMode,
  searchPattern,
  textMatches
} from '../policies/arabic-search.policy.js';
import { asyncHandler } from '../utils/asyncHandler.js';

function normalizeQuery(query) {
  return String(query ?? '').trim().slice(0, 80);
}

/**
 * Whether the shop itself answers - its name, what it sells, how it describes
 * itself - as distinct from whether one of its goods does.
 *
 * The distinction decides what the products tab shows. A shop found by its own
 * name is offering everything on its shelves; a shop found only because one
 * item on those shelves matched is offering that item. Searching `عطر` should
 * not return the mascara beside it.
 */
function shopItselfMatches(business, query, mode) {
  return (
    textMatches(business.name, query, mode) ||
    textMatches(business.category, query, mode) ||
    textMatches(business.description, query, mode)
  );
}

function productMatches(item, query, mode) {
  return (
    textMatches(item.name, query, mode) ||
    textMatches(item.description, query, mode)
  );
}

/**
 * The candidates to read, narrowed in the database where that is safe.
 *
 * Only an unanchored shop term on its own narrows anything: a `contains`
 * pattern is the one shape that can be asked of every field at once without
 * losing a shop whose match is in its goods. `starts` and `ends` anchor the
 * whole field - a shop called `حلويات أبو خالد` starts with `حلويات` while its
 * jacket does not - and a product term asks a second question the database
 * cannot combine field by field. Those read the active shops and decide here,
 * where one rule answers for every field.
 */
function candidateFilter(query, mode, productQuery) {
  const base = { isActive: true };
  if (query === '' || mode !== 'contains' || productQuery !== '') return base;

  const pattern = searchPattern(query, 'contains');
  if (pattern === null) return base;

  return {
    ...base,
    $or: [
      { name: pattern },
      { category: pattern },
      { description: pattern },
      { 'products.name': pattern },
      { 'products.description': pattern }
    ]
  };
}

function publicProductSearchResult(business, product) {
  return {
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
  };
}

export const searchCatalog = asyncHandler(async (req, res) => {
  const query = normalizeQuery(req.query.query ?? req.query.q);
  const mode = matchMode(req.query.match);
  const productQuery = normalizeQuery(req.query.product);
  const productMode = matchMode(req.query.productMatch, {
    allowSimilar: true
  });
  const limit = Math.min(
    Math.max(Number.parseInt(req.query.limit ?? '30', 10), 1),
    50
  );

  // Either box on its own is a search; neither is not.
  if (!query && !productQuery) {
    res.json({
      success: true,
      data: { query: '', products: [], businesses: [] }
    });
    return;
  }

  const exactIdBusiness = await Business.findOne({
    isActive: true,
    publicId: query
  });

  if (exactIdBusiness) {
    const products = exactIdBusiness.products
      .filter((product) => product.isActive)
      .slice(0, limit)
      .map((product) =>
        publicProductSearchResult(
          exactIdBusiness,
          product
        )
      );

    res.json({
      success: true,
      data: {
        query,
        products,
        businesses: [
          exactIdBusiness.toListJSON()
        ]
      }
    });
    return;
  }

  const businesses = await Business.find(
    candidateFilter(query, mode, productQuery)
  )
    .sort({ ratingAverage: -1, subscribedAt: -1 })
    .limit(80);

  // One box or two. With one, it has always meant "find me this, wherever it
  // is written", so it asks the shop and its goods alike. With two, the
  // question divides - this shop, selling that thing - and a shop can carry
  // the name and not the goods.
  const wantsGoods = productQuery !== '';
  const products = [];
  const matched = [];

  for (const business of businesses) {
    const shopItself =
      query === '' || shopItselfMatches(business, query, mode);
    const onSale = business.products.filter((item) => item.isActive);

    let goods;

    if (wantsGoods) {
      // Both conditions, which is the whole point of the second box.
      if (!shopItself) continue;

      goods = onSale.filter((item) =>
        productMatches(item, productQuery, productMode)
      );
      if (goods.length === 0) continue;
    } else {
      const answering = onSale.filter((item) =>
        productMatches(item, query, mode)
      );
      if (!shopItself && answering.length === 0) continue;

      goods = shopItself ? onSale : answering;
    }

    matched.push(business);

    for (const item of goods) {
      if (products.length >= limit) break;
      products.push(publicProductSearchResult(business, item));
    }
  }

  const matchedBusinesses = matched
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
