import { AppError } from '../utils/AppError.js';

/**
 * What a profile picture may be.
 *
 * The image arrives base64-encoded in a JSON body rather than as multipart,
 * because that is the one shape every client here already speaks. The cost is
 * that a body is a third larger than the file it carries, so the ceiling below
 * is on the decoded bytes, not on the string.
 */
export const AVATAR_MAX_BYTES = 5 * 1024 * 1024;

/**
 * Formats a phone camera or gallery actually produces, and that imgbb accepts.
 * The list is deliberately short: an image this app will render in a 40-pixel
 * circle has no reason to be a TIFF.
 */
export const AVATAR_CONTENT_TYPES = Object.freeze([
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/gif'
]);

const DATA_URL = /^data:([a-z]+\/[a-z0-9.+-]+);base64,(.*)$/is;
const BASE64 = /^[A-Za-z0-9+/]+={0,2}$/;

/**
 * Reads the image out of a request body.
 *
 * Accepts either a bare base64 string or a `data:` URL, because a browser and
 * a phone hand those over differently and neither is wrong. Returns the raw
 * base64 payload with its declared content type, or throws.
 */
export function readAvatarImage(body = {}) {
  const raw = body.image;

  if (typeof raw !== 'string' || raw.trim() === '') {
    throw new AppError('An image is required', 400, 'AVATAR_IMAGE_REQUIRED');
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
    throw new AppError('The image is not valid base64', 400, 'AVATAR_IMAGE_INVALID');
  }

  if (contentType && !AVATAR_CONTENT_TYPES.includes(contentType.toLowerCase())) {
    throw new AppError(
      'That image format is not supported',
      400,
      'AVATAR_CONTENT_TYPE_UNSUPPORTED'
    );
  }

  // The decoded length, computed rather than decoded: rejecting an oversized
  // image should not first cost the memory of holding it.
  const padding = payload.endsWith('==') ? 2 : payload.endsWith('=') ? 1 : 0;
  const bytes = (payload.length / 4) * 3 - padding;

  if (bytes > AVATAR_MAX_BYTES) {
    throw new AppError('That image is too large', 400, 'AVATAR_IMAGE_TOO_LARGE');
  }

  return { base64: payload, bytes, contentType: contentType.toLowerCase() };
}
