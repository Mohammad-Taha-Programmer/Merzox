import { Business, BUSINESS_LIST_FIELDS } from '../models/Business.js';
import { User } from '../models/User.js';
import {
  matchMode,
  searchPattern,
  similarPatterns,
  textMatches
} from '../policies/arabic-search.policy.js';
import {
  phoneSearchDigits,
  phoneSearchPattern
} from '../policies/phone-search.policy.js';
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

/** A product as a customer sees it, with the shop it belongs to attached. */
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

/** The shop's own fields - what it is called, what it sells, how it reads. */
function shopClauses(pattern) {
  return [
    { name: pattern },
    { category: pattern },
    { description: pattern }
  ];
}

function goodsClauses(patterns) {
  return patterns.flatMap((pattern) => [
    { 'products.name': pattern },
    { 'products.description': pattern }
  ]);
}

/** Every pattern a product term is satisfied by. */
function productPatterns(productQuery, productMode) {
  if (productMode === 'similar') return similarPatterns(productQuery);

  const pattern = searchPattern(productQuery, productMode);
  return pattern === null ? [] : [pattern];
}

/**
 * The candidates to read, narrowed in the database.
 *
 * This used to give up whenever the search was anchored or carried a product
 * term, and read every open shop instead. That is what made those searches
 * slow: not the matching, which the database does in a millisecond, but
 * hauling two megabytes of shop documents across the link to decide here what
 * could have been decided there.
 *
 * The filter does not have to be exact - the loop below still decides, field by
 * field, and it is the only thing that decides. It has to be no *narrower* than
 * the truth, and each clause here is the same pattern the loop tests, asked of
 * the same fields or of more of them: the database sees a shop's inactive goods
 * where the loop does not, so it can only over-admit, never exclude.
 */
function candidateFilter(query, mode, productQuery, productMode) {
  const clauses = [];

  if (query !== '') {
    const pattern = searchPattern(query, mode);

    if (pattern !== null) {
      // With no product term the words may be answered by the goods too, which
      // is what the single box has always meant.
      clauses.push({
        $or:
          productQuery === ''
            ? [...shopClauses(pattern), ...goodsClauses([pattern])]
            : shopClauses(pattern)
      });
    }
  }

  if (productQuery !== '') {
    const patterns = productPatterns(productQuery, productMode);
    if (patterns.length > 0) clauses.push({ $or: goodsClauses(patterns) });
  }

  // Nothing that could be matched on. A query of tatweels and marks normalizes
  // away to nothing, and reading every open shop to discover that the loop
  // rejects all of them is the one round trip nobody asked for.
  if (clauses.length === 0) return null;

  return { isActive: true, $and: clauses };
}

/**
 * One field of a candidate, tested where the candidate is.
 *
 * The source and a bare `i` rather than the expression itself: this policy
 * builds its patterns with `u`, BSON carries that flag, and `$regexMatch`
 * refuses it. `$ifNull` because a shop may have no description and
 * `$regexMatch` errs on anything that is not a string.
 */
function regexMatches(field, pattern) {
  return {
    $regexMatch: {
      input: { $ifNull: [field, ''] },
      regex: pattern.source,
      options: 'i'
    }
  };
}

/**
 * Whether a product is one this search could put on the screen.
 *
 * Nine tenths of a shop document is its goods, and a search shows thirty of
 * them. `حقيبة` matched sixty shops selling twelve products each, so seven
 * hundred products crossed the link to put thirty on the screen - three
 * seconds for a reply of forty-six kilobytes.
 *
 * So the ones that cannot be shown are cut down where they are, to the name
 * and the mark of being on sale, which is all the shops tab reads of them.
 *
 * The condition is the loop's own, stated as an expression: a product is
 * emittable when it answers the search, or when the shop answered for itself
 * and is therefore offering everything on its shelves. Which means a product
 * that is cut down is one the loop would not have emitted - it cannot match on
 * a field it still has, because matching on it is what would have kept it
 * whole. The cut fields can turn no decision, only save the carriage.
 */
function emittableProduct(query, mode, productQuery, productMode) {
  if (productQuery !== '') {
    // With a goods box the loop asks only about the goods, whatever the shop
    // box did.
    const patterns = productPatterns(productQuery, productMode);
    if (patterns.length === 0) return false;

    return {
      $or: patterns.flatMap((pattern) => [
        regexMatches('$$item.name', pattern),
        regexMatches('$$item.description', pattern)
      ])
    };
  }

  const pattern = searchPattern(query, mode);
  if (pattern === null) return true;

  return {
    $or: [
      // A shop found by its own name is offering all of its shelves.
      regexMatches('$name', pattern),
      regexMatches('$category', pattern),
      regexMatches('$description', pattern),
      regexMatches('$$item.name', pattern),
      regexMatches('$$item.description', pattern)
    ]
  };
}

/**
 * How much of a candidate has to travel.
 *
 * The fields the list shape reads, named in the model beside it so the two
 * move together; `description`, which only the matching here reads; and the
 * goods, whole where they can be shown and a name where they cannot.
 *
 * Products that are not on sale are dropped outright - every reader of this
 * array filters them out first.
 */
function candidateProjection(query, mode, productQuery, productMode) {
  const projection = {
    description: 1,
    products: {
      $map: {
        input: {
          $filter: {
            input: '$products',
            as: 'item',
            // Not `$eq: true`: a product stored before the field existed has
            // none, and the reader here treats that as on sale.
            cond: { $ne: ['$$item.isActive', false] }
          }
        },
        as: 'item',
        in: {
          $cond: [
            emittableProduct(query, mode, productQuery, productMode),
            '$$item',
            { _id: '$$item._id', name: '$$item.name', isActive: true }
          ]
        }
      }
    }
  };

  for (const field of BUSINESS_LIST_FIELDS) projection[field] = 1;

  return projection;
}

/**
 * Whether a search could be asking for a shop by its public identifier.
 *
 * Five digits, which is the whole of that identifier's shape. Asking the
 * database anyway cost a round trip on every search - and on this deployment a
 * round trip is four hundred milliseconds whatever it carries.
 */
function looksLikePublicId(query) {
  return /^[0-9]{5}$/.test(query);
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
      data: {
        query: '',
        products: [],
        businesses: [],
        shopsMatchedThemselves: false
      }
    });
    return;
  }

  /**
   * The shops whose owner answers on this number.
   *
   * A customer often has the merchant's number and not their shop's name - it
   * was on a receipt, or a neighbour sent it - and a number is the one thing
   * about a shop that is never spelled two ways.
   *
   * It reads the account rather than the shop because that is where a number
   * lives: a shop publishes its owner's, it does not keep its own.
   */
  const phoneDigits = phoneSearchDigits(query);

  if (phoneDigits && !productQuery) {
    const pattern = phoneSearchPattern(phoneDigits);
    const owners = await User.find({ 'phones.value': pattern })
      .select('_id')
      .limit(20);

    if (owners.length > 0) {
      const shops = await Business.find({
        isActive: true,
        owner: { $in: owners.map((owner) => owner._id) }
      })
        .sort({ ratingAverage: -1, subscribedAt: -1 })
        .limit(limit);

      if (shops.length > 0) {
        // A number names a shop, not a thing on its shelves - so the shops tab
        // is the answer, and the products tab shows what those shops sell.
        const found = [];

        for (const shop of shops) {
          for (const item of shop.products) {
            if (!item.isActive || found.length >= limit) continue;
            found.push(publicProductSearchResult(shop, item));
          }
        }

        res.json({
          success: true,
          data: {
            query,
            products: found,
            businesses: shops.map((shop) => shop.toListJSON()),
            // A number names the shop itself.
            shopsMatchedThemselves: true
          }
        });
        return;
      }
    }
  }

  const exactIdBusiness = looksLikePublicId(query)
    ? await Business.findOne({ isActive: true, publicId: query })
    : null;

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

  const filter = candidateFilter(query, mode, productQuery, productMode);

  if (filter === null) {
    res.json({
      success: true,
      data: { query, products: [], businesses: [], shopsMatchedThemselves: false }
    });
    return;
  }

  const businesses = await Business.find(
    filter,
    candidateProjection(query, mode, productQuery, productMode)
  )
    .sort({ ratingAverage: -1, subscribedAt: -1 })
    // Room above the cap for the shops the loop will drop - a shop whose only
    // matching item is one it has stopped selling - and no more than that,
    // because every extra candidate is eleven kilobytes over the wire.
    .limit(Math.min(limit * 2, 80));

  // One box or two. With one, it has always meant "find me this, wherever it
  // is written", so it asks the shop and its goods alike. With two, the
  // question divides - this shop, selling that thing - and a shop can carry
  // the name and not the goods.
  const wantsGoods = productQuery !== '';
  const products = [];
  const matched = [];

  /**
   * Whether any shop in the results is there for its own sake.
   *
   * A shop appears in the list when its goods answered too, which is right -
   * somebody searching `احمر` wants to see who sells it. But it means the list
   * of shops being non-empty says nothing about whether the *words* found a
   * shop, and the screen was using exactly that to decide which tab to open.
   * `احمر` found lipstick and opened on a tab of shops.
   *
   * So the fact travels, and the screen reads it instead of counting.
   */
  let shopsMatchedThemselves = false;

  for (const business of businesses) {
    // With no shop term at all - a search for goods alone - nothing has been
    // asked about the shop, so nothing about it has been answered.
    const shopItself =
      query === '' || shopItselfMatches(business, query, mode);
    if (query !== '' && shopItself) shopsMatchedThemselves = true;
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
      businesses: matchedBusinesses,
      shopsMatchedThemselves
    }
  });
});
