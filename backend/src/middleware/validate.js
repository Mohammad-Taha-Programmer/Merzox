import validator from 'validator';

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

export function validateProfilePatch(req, _res, next) {
  const allowed = ['name', 'gender', 'address', 'emails', 'phones', 'permissions'];
  const invalid = Object.keys(req.body).filter((key) => !allowed.includes(key));

  if (invalid.length > 0) {
    throw new AppError(`Unsupported profile fields: ${invalid.join(', ')}`, 400, 'INVALID_PROFILE_FIELDS');
  }

  next();
}

export function validateOrderCreate(req, _res, next) {
  const allowed = [
    'businessId',
    'items',
    'deliveryAddress',
    'paymentMethod',
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
    if (itemFields.some((key) => !['productId', 'quantity', 'variant'].includes(key))) {
      throw new AppError('Order item contains unsupported fields', 400, 'INVALID_ORDER_ITEM');
    }

    if (!/^[a-f\d]{24}$/i.test(String(item.productId ?? ''))) {
      throw new AppError('Product id is invalid', 400, 'INVALID_PRODUCT_ID');
    }

    if (!Number.isInteger(item.quantity) || item.quantity < 1 || item.quantity > 100) {
      throw new AppError('Product quantity is invalid', 400, 'INVALID_QUANTITY');
    }

    if (String(item.variant ?? '').length > 40) {
      throw new AppError('Product variant is too long', 400, 'INVALID_VARIANT');
    }
  }

  const paymentMethods = new Set(['cash', 'card', 'bankTransfer', 'assisted']);
  if (req.body.paymentMethod && !paymentMethods.has(req.body.paymentMethod)) {
    throw new AppError('Payment method is invalid', 400, 'INVALID_PAYMENT_METHOD');
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
    'attachmentUrl'
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

  next();
}

function validateBusinessProductBody(body, { partial }) {
  const allowed = [
    'name',
    'description',
    'price',
    'imageUrl',
    'imageUrls',
    'classification',
    'isService',
    'isActive'
  ];
  const keys = Object.keys(body);
  const invalid = keys.filter((key) => !allowed.includes(key));
  if (invalid.length > 0 || (partial && keys.length === 0)) {
    throw new AppError('Product fields are invalid', 400, 'INVALID_PRODUCT_FIELDS');
  }

  if (!partial || body.name !== undefined) {
    const name = String(body.name ?? '').trim();
    if (name.length < 2 || name.length > 120) {
      throw new AppError('Product name is invalid', 400, 'INVALID_PRODUCT_NAME');
    }
  }
  if (!partial || body.price !== undefined) {
    const price = Number(body.price);
    if (!Number.isFinite(price) || price < 0) {
      throw new AppError('Product price is invalid', 400, 'INVALID_PRODUCT_PRICE');
    }
  }
  if (body.description !== undefined && String(body.description).trim().length > 500) {
    throw new AppError('Product description is too long', 400, 'INVALID_PRODUCT_DESCRIPTION');
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
      body.imageUrls.length > 8 ||
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
  if (
    body.classification !== undefined &&
    !['new', 'bestSelling', 'offers'].includes(body.classification)
  ) {
    throw new AppError('Product classification is invalid', 400, 'INVALID_PRODUCT_CLASSIFICATION');
  }
  for (const field of ['isService', 'isActive']) {
    if (body[field] !== undefined && typeof body[field] !== 'boolean') {
      throw new AppError(`${field} must be boolean`, 400, 'INVALID_PRODUCT_BOOLEAN');
    }
  }
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
  validateBusinessProductBody(req.body, { partial: false });
  next();
}

export function validateBusinessProductPatch(req, _res, next) {
  validateBusinessProductBody(req.body, { partial: true });
  next();
}

export function validateBusinessOrderStatus(req, _res, next) {
  const invalid = Object.keys(req.body).filter(
    (key) => !['status', 'note'].includes(key)
  );
  if (invalid.length > 0) {
    throw new AppError('Order status fields are invalid', 400, 'INVALID_ORDER_STATUS_FIELDS');
  }

  if (
    !['confirmed', 'preparing', 'outForDelivery', 'delivered', 'cancelled'].includes(
      req.body.status
    )
  ) {
    throw new AppError('Order status is invalid', 400, 'INVALID_ORDER_STATUS');
  }
  if (String(req.body.note ?? '').trim().length > 250) {
    throw new AppError('Order status note is too long', 400, 'INVALID_ORDER_STATUS_NOTE');
  }

  next();
}
