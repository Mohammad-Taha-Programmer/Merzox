import { AppError } from '../utils/AppError.js';

/**
 * What an uploaded picture may be.
 *
 * Two things upload images now - a profile picture and a product photo - and
 * the rules are the same for both: the same ceiling, the same formats, the
 * same two encodings a client might send. Only the error codes differ, so the
 * caller passes the set it wants and everything else is shared.
 *
 * The image arrives base64-encoded in a JSON body rather than as multipart,
 * because that is the one shape every client here already speaks. The cost is
 * that a body is a third larger than the file it carries, so the ceiling below
 * is on the decoded bytes, not on the string.
 */
export const UPLOAD_MAX_BYTES = 5 * 1024 * 1024;

/**
 * How large a request body carrying one of those images has to be allowed to
 * be.
 *
 * Base64 is four bytes out for every three in, and the JSON envelope adds a
 * little more. A limit set to the image ceiling itself rejects every image at
 * the ceiling - which is what happened: the body parser refused anything over
 * 32kb, so a photo from a phone camera never reached the rule that would have
 * accepted it, and came back as an unexplained failure.
 */
/**
 * The routes a picture arrives on.
 *
 * Listed here rather than guessed at the mount point: a route added without
 * its entry here goes back to the 32kb limit and fails the same silent way.
 */
export const IMAGE_UPLOAD_PATHS = Object.freeze([
  '/api/v1/users/me/avatar',
  '/api/v1/businesses/me/product-images'
]);

export const UPLOAD_BODY_LIMIT_BYTES = Math.ceil(UPLOAD_MAX_BYTES * 4 / 3) + 64 * 1024;

/**
 * Formats a phone camera or gallery actually produces, and that imgbb accepts.
 * The list is deliberately short: an image this app will render in a 40-pixel
 * circle has no reason to be a TIFF.
 */
export const UPLOAD_CONTENT_TYPES = Object.freeze([
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/gif'
]);

const DATA_URL = /^data:([a-z]+\/[a-z0-9.+-]+);base64,(.*)$/is;
const BASE64 = /^[A-Za-z0-9+/]+={0,2}$/;

/**
 * What a refusal is called, per picture.
 *
 * Spelled out rather than composed from a prefix. A code assembled out of a
 * subject and a suffix is invisible to the check that every code a
 * server can send has an Arabic translation - which is the whole point of that
 * check, and it caught exactly this.
 */
export const AVATAR_IMAGE_CODES = Object.freeze({
  required: 'AVATAR_IMAGE_REQUIRED',
  invalid: 'AVATAR_IMAGE_INVALID',
  unsupported: 'AVATAR_CONTENT_TYPE_UNSUPPORTED',
  tooLarge: 'AVATAR_IMAGE_TOO_LARGE'
});

export const PRODUCT_IMAGE_CODES = Object.freeze({
  required: 'PRODUCT_IMAGE_REQUIRED',
  invalid: 'PRODUCT_IMAGE_INVALID',
  unsupported: 'PRODUCT_CONTENT_TYPE_UNSUPPORTED',
  tooLarge: 'PRODUCT_IMAGE_TOO_LARGE'
});

/**
 * Reads the image out of a request body.
 *
 * Accepts either a bare base64 string or a `data:` URL, because a browser and
 * a phone hand those over differently and neither is wrong. Returns the raw
 * base64 payload with its declared content type, or throws.
 */
export function readUploadedImage(body = {}, { codes = AVATAR_IMAGE_CODES } = {}) {
  const raw = body.image;

  if (typeof raw !== 'string' || raw.trim() === '') {
    throw new AppError('An image is required', 400, codes.required);
  }

  const text = raw.trim();
  const match = DATA_URL.exec(text);

  let contentType = typeof body.contentType === 'string' ? body.contentType.trim() : '';
  let payload = text;

  if (match) {
    contentType = match[1].toLowerCase();
    payload = match[2];
  }

  // Whitespace is legal inside base64 and some encoders wrap at 76 columns,
  // so it is stripped rather than treated as corruption.
  payload = payload.replace(/\s+/g, '');

  if (!payload || !BASE64.test(payload) || payload.length % 4 !== 0) {
    throw new AppError(
      'The image is not valid base64',
      400,
      codes.invalid
    );
  }

  if (contentType && !UPLOAD_CONTENT_TYPES.includes(contentType.toLowerCase())) {
    throw new AppError(
      'That image format is not supported',
      400,
      codes.unsupported
    );
  }

  // The decoded length, computed rather than decoded: rejecting an oversized
  // image should not first cost the memory of holding it.
  const padding = payload.endsWith('==') ? 2 : payload.endsWith('=') ? 1 : 0;
  const bytes = (payload.length / 4) * 3 - padding;

  if (bytes > UPLOAD_MAX_BYTES) {
    throw new AppError(
      'That image is too large',
      400,
      codes.tooLarge
    );
  }

  return { base64: payload, bytes, contentType: contentType.toLowerCase() };
}
