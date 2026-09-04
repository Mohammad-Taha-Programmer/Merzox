import validator from 'validator';

import {
  BIRTH_DATE_ERRORS,
  isValidBirthDate
} from '../policies/birth-date.policy.js';
import {
  COURIER_LOCATION_ERRORS,
  normalizeCourierLocationPayload
} from '../policies/courier-location.policy.js';
import { merchantSelectableStatuses } from '../policies/order-status.policy.js';
import {
  isKnownPaymentMethod,
  isOperationalPaymentMethod,
  PAYMENT_ERRORS
} from '../policies/payment.policy.js';
import {
  merchantWritableProductFields,
  normalizeKeywords,
  productClassifications,
  PRODUCT_LIMITS
} from '../policies/product.policy.js';
import { AppError } from '../utils/AppError.js';

export function validateSignup(req, _res, next) {
  const { name, email, phone, password } = req.body;

  if (!name || String(name).trim().length < 2) {
    throw new AppError('Name must be at least 2 characters', 400, 'INVALID_NAME');
  }

  const normalizedEmail = email ? String(email).trim() : '';
  const normalizedPhone = phone ? String(phone).trim() : '';

  if (!normalizedEmail && !normalizedPhone) {
    throw new AppError('Email or phone is required', 400, 'INVALID_IDENTIFIER');
  }

  if (normalizedEmail && !validator.isEmail(normalizedEmail)) {
    throw new AppError('Email is invalid', 400, 'INVALID_EMAIL');
  }

  if (normalizedPhone && !/^\+?[0-9]{7,15}$/.test(normalizedPhone)) {
    throw new AppError('Phone number is invalid', 400, 'INVALID_PHONE');
  }

  if (!password || String(password).length < 6) {
    throw new AppError('Password must be at least 6 characters', 400, 'INVALID_PASSWORD');
  }

  next();
}

export function validateLogin(req, _res, next) {
  const { identifier, password } = req.body;

  if (!identifier || String(identifier).trim().length < 4) {
    throw new AppError('Email or phone is required', 400, 'INVALID_IDENTIFIER');
  }

  if (!password || String(password).length < 6) {
    throw new AppError('Password must be at least 6 characters', 400, 'INVALID_PASSWORD');
  }

  next();
}

export function validateForgotPassword(req, _res, next) {
  const body = req.body ?? {};
  const keys = Object.keys(body);
  const invalid = keys.filter((key) => key !== 'email');

  if (invalid.length > 0 || keys.length !== 1) {
    throw new AppError(
      'Password recovery fields are invalid',
      400,
      'INVALID_PASSWORD_RECOVERY_FIELDS'
    );
  }

  if (typeof body.email !== 'string') {
    throw new AppError('Email is invalid', 400, 'INVALID_EMAIL');
  }

  const email = body.email.trim();

  if (
    email.length === 0 ||
    email.length > 254 ||
    !validator.isEmail(email)
  ) {
    throw new AppError('Email is invalid', 400, 'INVALID_EMAIL');
  }

  next();
}

export function validateResetPassword(req, _res, next) {
  const body = req.body ?? {};
  const keys = Object.keys(body);
  const allowed = ['token', 'newPassword'];
  const invalid = keys.filter((key) => !allowed.includes(key));

  if (invalid.length > 0 || keys.length !== allowed.length) {
    throw new AppError(
      'Password reset fields are invalid',
      400,
      'INVALID_PASSWORD_RESET_FIELDS'
    );
  }

  if (
    typeof body.token !== 'string' ||
    !/^[A-Za-z0-9_-]{43}$/.test(body.token)
  ) {
    throw new AppError(
      'Password reset token is invalid or expired',
      400,
      'INVALID_PASSWORD_RESET_TOKEN'
    );
  }

  if (
    typeof body.newPassword !== 'string' ||
    body.newPassword.length < 6 ||
    Buffer.byteLength(body.newPassword, 'utf8') > 72
  ) {
    throw new AppError(
      'Password must be at least 6 characters',
      400,
      'INVALID_PASSWORD'
    );
  }

  next();
}

export function validateProfilePatch(req, _res, next) {
  const allowed = [
    'name',
    'gender',
    'address',
    'birthDate',
    'emails',
    'phones',
    'permissions'
  ];
  const invalid = Object.keys(req.body).filter((key) => !allowed.includes(key));

  if (invalid.length > 0) {
    throw new AppError(`Unsupported profile fields: ${invalid.join(', ')}`, 400, 'INVALID_PROFILE_FIELDS');
  }

  // `null` clears the optional date. Any other value must be a canonical,
  // real, non-future calendar date; a malformed one is refused rather than
  // silently coerced into whatever `new Date()` would have made of it.
  if (
    req.body.birthDate !== undefined &&
    req.body.birthDate !== null &&
    !isValidBirthDate(req.body.birthDate)
  ) {
    throw new AppError(
      'Date of birth must be a real past date in YYYY-MM-DD format',
      400,
      BIRTH_DATE_ERRORS.invalid
    );
  }

  if (req.body.permissions !== undefined) {
    const permissions = req.body.permissions;

    if (
      !permissions ||
      typeof permissions !== 'object' ||
      Array.isArray(permissions)
    ) {
      throw new AppError(
        'Profile permissions must be an object',
        400,
        'INVALID_PROFILE_PERMISSIONS'
      );
    }

    const allowedPermissionKeys = [
      'aiPersonalization',
      'location',
      'contacts'
    ];

    const invalidPermissionKeys = Object.keys(permissions).filter(
      (key) => !allowedPermissionKeys.includes(key)
    );

    if (invalidPermissionKeys.length > 0) {
      throw new AppError(
        `Unsupported profile permissions: ${invalidPermissionKeys.join(', ')}`,
        400,
        'INVALID_PROFILE_PERMISSION_FIELDS'
      );
    }

    const invalidPermissionValue = Object.entries(permissions).find(
      ([, value]) => typeof value !== 'boolean'
    );

    if (invalidPermissionValue) {
      throw new AppError(
        `Profile permission ${invalidPermissionValue[0]} must be boolean`,
        400,
        'INVALID_PROFILE_PERMISSION_VALUE'
      );
    }
  }

  next();
}

/**
 * Variant-shaped keys are accepted only when empty. They exist purely so an
 * older client sending `variant: ''` is not rejected outright.
 */
const variantLikeItemFields = ['variant', 'degree', 'option'];
const allowedItemFields = [
  'productId',
  'variantId',
  'quantity',
  ...variantLikeItemFields
];

export function validateOrderCreate(req, _res, next) {
  // `deliveryOption` belongs here: `createOrder` reads it a few lines later to
  // price the delivery, and every client has always sent it. Leaving it out of
  // the allowlist refused every order at the door - from the basket and from
  // "buy now" alike - with `INVALID_ORDER_FIELDS`, before the handler that
  // needs it ever ran. The tier itself is still checked downstream, where an
  // unknown name is refused with `INVALID_DELIVERY_OPTION`.
  const allowed = [
    'businessId',
    'items',
    'deliveryAddress',
    'paymentMethod',
    'deliveryOption',
    'clientOrderId'
  ];
  const invalid = Object.keys(req.body).filter((key) => !allowed.includes(key));

  if (invalid.length > 0) {
    throw new AppError(
      `Unsupported order fields: ${invalid.join(', ')}`,
      400,
      'INVALID_ORDER_FIELDS'
    );
  }

  if (!req.body.businessId || !/^[a-f\d]{24}$/i.test(String(req.body.businessId))) {
    throw new AppError('Business id is invalid', 400, 'INVALID_BUSINESS_ID');
  }

  if (!Array.isArray(req.body.items) || req.body.items.length < 1 || req.body.items.length > 50) {
    throw new AppError(
      'An order must contain between 1 and 50 items',
      400,
      'INVALID_ORDER_ITEMS'
    );
  }

  for (const item of req.body.items) {
    if (!item || typeof item !== 'object' || Array.isArray(item)) {
      throw new AppError('Order item is invalid', 400, 'INVALID_ORDER_ITEM');
    }

    const itemFields = Object.keys(item);
    // Legacy label-shaped fields never carry sellable identity authority.
    // They remain accepted only when empty for compatibility with older
    // clients. A customer selects a variant solely by its server-owned id.
    for (const key of variantLikeItemFields) {
      if (String(item[key] ?? '').trim().length > 0) {
        throw new AppError(
          'Variant labels are not accepted; select the server variant id',
          400,
          'UNSUPPORTED_PRODUCT_VARIANT'
        );
      }
    }

    // Empty legacy fields are normalized away. `variantId`, when present, is
    // only an identity claim; price, label and stock are resolved from Business.
    if (itemFields.some((key) => !allowedItemFields.includes(key))) {
      throw new AppError('Order item contains unsupported fields', 400, 'INVALID_ORDER_ITEM');
    }

    if (!/^[a-f\d]{24}$/i.test(String(item.productId ?? ''))) {
      throw new AppError('Product id is invalid', 400, 'INVALID_PRODUCT_ID');
    }

    if (
      item.variantId !== undefined &&
      item.variantId !== null &&
      String(item.variantId).trim().length > 0 &&
      !/^[a-f\d]{24}$/i.test(String(item.variantId).trim())
    ) {
      throw new AppError(
        'Product variant id is invalid',
        400,
        'INVALID_PRODUCT_VARIANT_ID'
      );
    }

    if (!Number.isInteger(item.quantity) || item.quantity < 1 || item.quantity > 100) {
      throw new AppError('Product quantity is invalid', 400, 'INVALID_QUANTITY');
    }

  }

  // A missing/null method preserves the historical cash default. Any value
  // explicitly supplied by the client must first be recognized, then proven
  // operational. This gate executes before createOrder and therefore before a
  // CheckoutIntent, reservation, inventory mutation, or Order can exist.
  const paymentMethod = req.body.paymentMethod ?? 'cash';

  if (!isKnownPaymentMethod(paymentMethod)) {
    throw new AppError(
      'Payment method is invalid',
      400,
      'INVALID_PAYMENT_METHOD'
    );
  }

  if (!isOperationalPaymentMethod(paymentMethod)) {
    throw new AppError(
      'Payment method is not currently available',
      409,
      PAYMENT_ERRORS.unavailable
    );
  }

  if (req.body.deliveryAddress && String(req.body.deliveryAddress).trim().length > 250) {
    throw new AppError('Delivery address is too long', 400, 'INVALID_DELIVERY_ADDRESS');
  }

  if (
    req.body.clientOrderId &&
    !/^[A-Za-z0-9._:-]{8,80}$/.test(String(req.body.clientOrderId))
  ) {
    throw new AppError('Client order id is invalid', 400, 'INVALID_CLIENT_ORDER_ID');
  }

  next();
}

export function validateOrderCancellation(req, _res, next) {
  const invalid = Object.keys(req.body).filter((key) => key !== 'reason');
  if (invalid.length > 0) {
    throw new AppError(
      `Unsupported cancellation fields: ${invalid.join(', ')}`,
      400,
      'INVALID_CANCELLATION_FIELDS'
    );
  }

  if (String(req.body.reason ?? '').trim().length > 250) {
    throw new AppError('Cancellation reason is too long', 400, 'INVALID_CANCELLATION_REASON');
  }

  next();
}

export function validateBusinessEnrollment(req, _res, next) {
  const allowed = [
    'phone',
    'email',
    'currentPassword',
    'name',
    'englishName',
    'description',
    'category',
    'address',
    'attachmentUrl'
  ];
  const invalid = Object.keys(req.body).filter((key) => !allowed.includes(key));
  if (invalid.length > 0) {
    throw new AppError(
      `Unsupported business enrollment fields: ${invalid.join(', ')}`,
      400,
      'INVALID_BUSINESS_ENROLLMENT_FIELDS'
    );
  }

  if (!/^\+?[0-9]{7,15}$/.test(String(req.body.phone ?? '').trim())) {
    throw new AppError('Phone number is invalid', 400, 'INVALID_PHONE');
  }
  if (!validator.isEmail(String(req.body.email ?? '').trim())) {
    throw new AppError('Email is invalid', 400, 'INVALID_EMAIL');
  }
  if (String(req.body.currentPassword ?? '').length < 6) {
    throw new AppError('Current password is required', 400, 'INVALID_CURRENT_PASSWORD');
  }
  if (String(req.body.name ?? '').trim().length < 2) {
    throw new AppError('Business name must be at least 2 characters', 400, 'INVALID_BUSINESS_NAME');
  }
  if (String(req.body.englishName ?? '').trim().length > 120) {
    throw new AppError('English business name is too long', 400, 'INVALID_ENGLISH_NAME');
  }
  if (String(req.body.category ?? '').trim().length < 2) {
    throw new AppError('Business category is required', 400, 'INVALID_BUSINESS_CATEGORY');
  }
  if (String(req.body.description ?? '').trim().length > 1500) {
    throw new AppError('Business description is too long', 400, 'INVALID_BUSINESS_DESCRIPTION');
  }
  if (String(req.body.address ?? '').trim().length > 250) {
    throw new AppError('Business address is too long', 400, 'INVALID_BUSINESS_ADDRESS');
  }
  const attachmentUrl = String(req.body.attachmentUrl ?? '').trim();
  if (attachmentUrl.length > 1000 || !isOptionalHttpUrl(attachmentUrl)) {
    throw new AppError('Business attachment URL is invalid', 400, 'INVALID_ATTACHMENT_URL');
  }

  next();
}

export function validateBusinessProfilePatch(req, _res, next) {
  const allowed = [
    'name',
    'englishName',
    'description',
    'category',
    'address',
    'attachmentUrl',
    'logoUrl',
    'socialLinks'
  ];
  const keys = Object.keys(req.body);
  const invalid = keys.filter((key) => !allowed.includes(key));
  if (invalid.length > 0 || keys.length === 0) {
    throw new AppError('Business profile fields are invalid', 400, 'INVALID_BUSINESS_PROFILE_FIELDS');
  }

  if (req.body.name !== undefined && String(req.body.name).trim().length < 2) {
    throw new AppError('Business name must be at least 2 characters', 400, 'INVALID_BUSINESS_NAME');
  }
  if (
    req.body.englishName !== undefined &&
    String(req.body.englishName).trim().length > 120
  ) {
    throw new AppError('English business name is too long', 400, 'INVALID_ENGLISH_NAME');
  }
  if (req.body.category !== undefined && String(req.body.category).trim().length < 2) {
    throw new AppError('Business category is required', 400, 'INVALID_BUSINESS_CATEGORY');
  }
  if (req.body.description !== undefined && String(req.body.description).trim().length > 1500) {
    throw new AppError('Business description is too long', 400, 'INVALID_BUSINESS_DESCRIPTION');
  }
  if (req.body.address !== undefined && String(req.body.address).trim().length > 250) {
    throw new AppError('Business address is too long', 400, 'INVALID_BUSINESS_ADDRESS');
  }
  if (req.body.attachmentUrl !== undefined) {
    const attachmentUrl = String(req.body.attachmentUrl).trim();
    if (attachmentUrl.length > 1000 || !isOptionalHttpUrl(attachmentUrl)) {
      throw new AppError('Business attachment URL is invalid', 400, 'INVALID_ATTACHMENT_URL');
    }
  }
  if (req.body.logoUrl !== undefined) {
    const logoUrl = String(req.body.logoUrl).trim();
    if (logoUrl.length > 1000 || !isOptionalHttpUrl(logoUrl)) {
      throw new AppError('Business logo URL is invalid', 400, 'INVALID_BUSINESS_LOGO_URL');
    }
  }
  if (req.body.socialLinks !== undefined) {
    const links = req.body.socialLinks;
    if (typeof links !== 'object' || links === null || Array.isArray(links)) {
      throw new AppError('Social links are invalid', 400, 'INVALID_BUSINESS_SOCIAL_LINKS');
    }

    const allowedLinks = ['instagram', 'whatsapp', 'mobile', 'facebook'];
    const invalidLinks = Object.keys(links).filter(
      (key) => !allowedLinks.includes(key)
    );
    if (invalidLinks.length > 0) {
      throw new AppError('Social links are invalid', 400, 'INVALID_BUSINESS_SOCIAL_LINKS');
    }

    for (const key of ['instagram', 'facebook']) {
      if (links[key] !== undefined && String(links[key]).trim().length > 200) {
        throw new AppError('Social links are invalid', 400, 'INVALID_BUSINESS_SOCIAL_LINKS');
      }
    }
    for (const key of ['whatsapp', 'mobile']) {
      const value = String(links[key] ?? '').trim();
      if (value.length > 0 && !/^\+?[0-9]{7,15}$/.test(value)) {
        throw new AppError(
          'Social contact numbers are invalid',
          400,
          'INVALID_BUSINESS_SOCIAL_NUMBER'
        );
      }
    }
  }

  next();
}

function validateProductVariants(variants, { allowIds }) {
  if (!Array.isArray(variants) || variants.length > PRODUCT_LIMITS.maxVariants) {
    throw new AppError(
      'Product variants are invalid',
      400,
      'INVALID_PRODUCT_VARIANTS'
    );
  }

  const allowedFields = [
    'id',
    'label',
    'priceOverride',
    'costPrice',
    'stockQuantity',
    'unlimitedStock',
    'isActive'
  ];

  const ids = new Set();
  const labels = new Set();

  for (const variant of variants) {
    if (!variant || typeof variant !== 'object' || Array.isArray(variant)) {
      throw new AppError(
        'Product variant is invalid',
        400,
        'INVALID_PRODUCT_VARIANT'
      );
    }

    const invalidFields = Object.keys(variant).filter(
      (key) => !allowedFields.includes(key)
    );

    if (invalidFields.length > 0) {
      throw new AppError(
        'Product variant fields are invalid',
        400,
        'INVALID_PRODUCT_VARIANT_FIELDS'
      );
    }

    if (variant.id !== undefined) {
      const id = String(variant.id ?? '').trim();

      if (!allowIds || !/^[a-f\d]{24}$/i.test(id) || ids.has(id)) {
        throw new AppError(
          'Product variant id is invalid',
          400,
          'INVALID_PRODUCT_VARIANT_ID'
        );
      }

      ids.add(id);
    }

    const label = String(variant.label ?? '').trim();
    const normalizedLabel = label.toLocaleLowerCase();

    if (
      label.length < 1 ||
      label.length > PRODUCT_LIMITS.variantLabelMax ||
      labels.has(normalizedLabel)
    ) {
      throw new AppError(
        'Product variant label is invalid',
        400,
        'INVALID_PRODUCT_VARIANT_LABEL'
      );
    }

    labels.add(normalizedLabel);

    for (const [field, code] of [
      ['priceOverride', 'INVALID_PRODUCT_VARIANT_PRICE'],
      ['costPrice', 'INVALID_PRODUCT_VARIANT_COST_PRICE']
    ]) {
      const value = variant[field];

      if (value === undefined || value === null || value === '') continue;

      if (!isNumericInput(value)) {
        throw new AppError('Product variant price is invalid', 400, code);
      }

      const parsed = Number(value);

      if (
        !Number.isFinite(parsed) ||
        parsed < 0 ||
        parsed > PRODUCT_LIMITS.maxPrice
      ) {
        throw new AppError('Product variant price is invalid', 400, code);
      }
    }

    // Every variant states its stock mode explicitly. This prevents a supplied
    // finite quantity from being interpreted under the legacy unlimited default.
    if (typeof variant.unlimitedStock !== 'boolean') {
      throw new AppError(
        'Product variant stock mode is invalid',
        400,
        'INVALID_PRODUCT_VARIANT_STOCK_MODE'
      );
    }

    if (variant.stockQuantity !== undefined && variant.unlimitedStock !== true) {
      if (!isNumericInput(variant.stockQuantity)) {
        throw new AppError(
          'Product variant stock is invalid',
          400,
          'INVALID_PRODUCT_VARIANT_STOCK'
        );
      }

      const stock = Number(variant.stockQuantity);

      if (
        !Number.isInteger(stock) ||
        stock < 0 ||
        stock > PRODUCT_LIMITS.maxStockQuantity
      ) {
        throw new AppError(
          'Product variant stock is invalid',
          400,
          'INVALID_PRODUCT_VARIANT_STOCK'
        );
      }
    }

    if (
      variant.isActive !== undefined &&
      typeof variant.isActive !== 'boolean'
    ) {
      throw new AppError(
        'Product variant activity is invalid',
        400,
        'INVALID_PRODUCT_VARIANT_BOOLEAN'
      );
    }
  }
}

function validateBusinessProductBody(body, { partial, allowVariantIds }) {
  // Sourced from the shared contract: identity, ratings, likes, and timestamps
  // are absent from it, so injecting them is rejected here rather than being
  // silently dropped later.
  const keys = Object.keys(body);
  const invalid = keys.filter(
    (key) => !merchantWritableProductFields.includes(key)
  );
  if (invalid.length > 0 || (partial && keys.length === 0)) {
    throw new AppError('Product fields are invalid', 400, 'INVALID_PRODUCT_FIELDS');
  }

  if (!partial || body.name !== undefined) {
    const name = String(body.name ?? '').trim();
    if (
      name.length < PRODUCT_LIMITS.nameMin ||
      name.length > PRODUCT_LIMITS.nameMax
    ) {
      throw new AppError('Product name is invalid', 400, 'INVALID_PRODUCT_NAME');
    }
  }
  if (!partial || body.price !== undefined) {
    // Number(null), Number('') and Number([]) all coerce to 0, so the type is
    // checked before the value: a price must be stated, not implied.
    if (!isNumericInput(body.price)) {
      throw new AppError('Product price is invalid', 400, 'INVALID_PRODUCT_PRICE');
    }
    const price = Number(body.price);
    if (!Number.isFinite(price) || price < 0) {
      throw new AppError('Product price is invalid', 400, 'INVALID_PRODUCT_PRICE');
    }
  }
  if (
    body.description !== undefined &&
    String(body.description).trim().length > PRODUCT_LIMITS.descriptionMax
  ) {
    throw new AppError('Product description is too long', 400, 'INVALID_PRODUCT_DESCRIPTION');
  }
  if (body.price !== undefined && Number(body.price) > PRODUCT_LIMITS.maxPrice) {
    throw new AppError('Product price is invalid', 400, 'INVALID_PRODUCT_PRICE');
  }

  // costPrice is optional and may be cleared, but a supplied value must be a
  // real nonnegative number.
  if (body.costPrice !== undefined && body.costPrice !== null && body.costPrice !== '') {
    if (!isNumericInput(body.costPrice)) {
      throw new AppError('Product cost price is invalid', 400, 'INVALID_PRODUCT_COST_PRICE');
    }
    const costPrice = Number(body.costPrice);
    if (!Number.isFinite(costPrice) || costPrice < 0 || costPrice > PRODUCT_LIMITS.maxPrice) {
      throw new AppError('Product cost price is invalid', 400, 'INVALID_PRODUCT_COST_PRICE');
    }
  }

  if (body.unlimitedStock !== undefined && typeof body.unlimitedStock !== 'boolean') {
    throw new AppError('Unlimited stock must be boolean', 400, 'INVALID_PRODUCT_STOCK_MODE');
  }

  // A finite stock must be a whole, nonnegative count. When unlimited stock is
  // requested the quantity is meaningless and is normalized away rather than
  // rejected, so a form that leaves a stale number behind still saves cleanly.
  if (body.stockQuantity !== undefined && body.unlimitedStock !== true) {
    if (!isNumericInput(body.stockQuantity)) {
      throw new AppError('Product stock quantity is invalid', 400, 'INVALID_PRODUCT_STOCK');
    }
    const stockQuantity = Number(body.stockQuantity);
    if (
      !Number.isInteger(stockQuantity) ||
      stockQuantity < 0 ||
      stockQuantity > PRODUCT_LIMITS.maxStockQuantity
    ) {
      throw new AppError('Product stock quantity is invalid', 400, 'INVALID_PRODUCT_STOCK');
    }
  }

  if (body.discountPercent !== undefined) {
    if (!isNumericInput(body.discountPercent)) {
      throw new AppError('Product discount is invalid', 400, 'INVALID_PRODUCT_DISCOUNT');
    }
    const discountPercent = Number(body.discountPercent);
    if (!Number.isFinite(discountPercent) || discountPercent < 0 || discountPercent > 100) {
      throw new AppError('Product discount is invalid', 400, 'INVALID_PRODUCT_DISCOUNT');
    }
  }

  if (body.keywords !== undefined && normalizeKeywords(body.keywords) === null) {
    throw new AppError('Product keywords are invalid', 400, 'INVALID_PRODUCT_KEYWORDS');
  }
  if (body.imageUrl !== undefined) {
    const imageUrl = String(body.imageUrl).trim();
    if (imageUrl.length > 1000 || !isOptionalHttpUrl(imageUrl)) {
      throw new AppError('Product image URL is invalid', 400, 'INVALID_PRODUCT_IMAGE_URL');
    }
  }
  if (body.imageUrls !== undefined) {
    if (
      !Array.isArray(body.imageUrls) ||
      body.imageUrls.length > PRODUCT_LIMITS.maxImages ||
      body.imageUrls.some(
        (url) =>
          typeof url !== 'string' ||
          url.trim().length > 1000 ||
          !isOptionalHttpUrl(url.trim())
      )
    ) {
      throw new AppError('Product image URLs are invalid', 400, 'INVALID_PRODUCT_IMAGE_URLS');
    }
  }
  if (body.variants !== undefined) {
    validateProductVariants(body.variants, {
      allowIds: allowVariantIds === true
    });
  }

  if (
    body.classification !== undefined &&
    !productClassifications.includes(body.classification)
  ) {
    throw new AppError('Product classification is invalid', 400, 'INVALID_PRODUCT_CLASSIFICATION');
  }
  for (const field of ['isService', 'isActive']) {
    if (body[field] !== undefined && typeof body[field] !== 'boolean') {
      throw new AppError(`${field} must be boolean`, 400, 'INVALID_PRODUCT_BOOLEAN');
    }
  }
}

/**
 * A value that may legitimately be read as a number. Rejects the shapes that
 * JavaScript silently coerces to 0 - null, booleans, arrays, objects, and the
 * empty string - so an absent value can never masquerade as a free product.
 */
function isNumericInput(value) {
  if (typeof value === 'number') return Number.isFinite(value);
  if (typeof value === 'string') return value.trim().length > 0;
  return false;
}

function isOptionalHttpUrl(value) {
  return (
    value.length === 0 ||
    validator.isURL(value, {
      protocols: ['http', 'https'],
      require_protocol: true,
      require_host: true
    })
  );
}

export function validateBusinessProductCreate(req, _res, next) {
  validateBusinessProductBody(req.body, {
    partial: false,
    allowVariantIds: false
  });
  next();
}

export function validateBusinessProductPatch(req, _res, next) {
  validateBusinessProductBody(req.body, {
    partial: true,
    allowVariantIds: true
  });
  next();
}

export function validateBusinessOrderStatus(req, _res, next) {
  const invalid = Object.keys(req.body).filter(
    (key) => !['status', 'note'].includes(key)
  );
  if (invalid.length > 0) {
    throw new AppError('Order status fields are invalid', 400, 'INVALID_ORDER_STATUS_FIELDS');
  }

  // Sourced from the shared policy rather than restated here, so the validator
  // and the controller can never disagree about what a merchant may select.
  if (!merchantSelectableStatuses.includes(req.body.status)) {
    throw new AppError('Order status is invalid', 400, 'INVALID_ORDER_STATUS');
  }
  if (String(req.body.note ?? '').trim().length > 250) {
    throw new AppError('Order status note is too long', 400, 'INVALID_ORDER_STATUS_NOTE');
  }

  next();
}

export function validateConversationOpen(req, _res, next) {
  const invalid = Object.keys(req.body).filter((key) => key !== 'businessId');
  if (invalid.length > 0) {
    throw new AppError(
      `Unsupported conversation fields: ${invalid.join(', ')}`,
      400,
      'INVALID_CONVERSATION_FIELDS'
    );
  }

  const businessId = String(req.body.businessId ?? '').trim();
  if (businessId.length < 3 || businessId.length > 80) {
    throw new AppError('Business id is invalid', 400, 'INVALID_BUSINESS_ID');
  }

  next();
}

export function validateMessageCreate(req, _res, next) {
  const invalid = Object.keys(req.body).filter((key) => key !== 'body');
  if (invalid.length > 0) {
    throw new AppError(
      `Unsupported message fields: ${invalid.join(', ')}`,
      400,
      'INVALID_MESSAGE_FIELDS'
    );
  }

  const body = String(req.body.body ?? '').trim();
  if (body.length === 0) {
    throw new AppError('Message body is required', 400, 'INVALID_MESSAGE_BODY');
  }
  if (body.length > 2000) {
    throw new AppError('Message body is too long', 400, 'INVALID_MESSAGE_BODY');
  }

  next();
}

export function validateOrderAddressPatch(req, _res, next) {
  const invalid = Object.keys(req.body).filter(
    (key) => !['deliveryAddress'].includes(key)
  );
  if (invalid.length > 0) {
    throw new AppError(
      `Unsupported address fields: ${invalid.join(', ')}`,
      400,
      'INVALID_ORDER_ADDRESS_FIELDS'
    );
  }

  const address = String(req.body.deliveryAddress ?? '').trim();
  if (address.length < 5 || address.length > 250) {
    throw new AppError(
      'Delivery address must be between 5 and 250 characters',
      400,
      'INVALID_ORDER_ADDRESS'
    );
  }

  next();
}

export function validateOrderCourierPatch(req, _res, next) {
  const invalid = Object.keys(req.body).filter(
    (key) => !['name', 'phone'].includes(key)
  );
  if (invalid.length > 0) {
    throw new AppError(
      `Unsupported courier fields: ${invalid.join(', ')}`,
      400,
      'INVALID_ORDER_COURIER_FIELDS'
    );
  }

  const name = String(req.body.name ?? '').trim();
  if (name.length < 2 || name.length > 80) {
    throw new AppError('Courier name is invalid', 400, 'INVALID_ORDER_COURIER_NAME');
  }

  const phone = String(req.body.phone ?? '').trim();
  if (phone.length > 0 && !/^\+?[0-9]{7,15}$/.test(phone)) {
    throw new AppError('Courier phone is invalid', 400, 'INVALID_ORDER_COURIER_PHONE');
  }

  next();
}

export function validateCourierLocationUpdate(req, _res, next) {
  const result =
    normalizeCourierLocationPayload(
      req.body
    );

  if (!result.ok) {
    const messages = {
      [COURIER_LOCATION_ERRORS.invalidFields]:
        'Courier location fields are invalid',
      [COURIER_LOCATION_ERRORS.invalidLatitude]:
        'Courier latitude is invalid',
      [COURIER_LOCATION_ERRORS.invalidLongitude]:
        'Courier longitude is invalid',
      [COURIER_LOCATION_ERRORS.invalidAccuracy]:
        'Courier location accuracy is invalid',
      [COURIER_LOCATION_ERRORS.invalidCapturedAt]:
        'Courier location timestamp is invalid'
    };

    throw new AppError(
      messages[result.code] ??
        'Courier location is invalid',
      400,
      result.code
    );
  }

  req.courierLocationPayload =
    result.value;

  next();
}
