import { createHash } from 'node:crypto';

import { AppError } from '../utils/AppError.js';

/**
 * Puts an image somewhere the app can render it from, and takes it away again.
 *
 * The upload happens here rather than in the app on purpose. The host's secret
 * is a secret; a secret compiled into a mobile binary is one anyone with the
 * APK can read, and this repository is public. Keeping it in `.env` and
 * spending it here means the app never holds it.
 *
 * That placement is also what makes deletion possible at all. Cloudinary has
 * no unsigned delete - only its upload accepts an unsigned preset - so a client
 * that uploads directly can never remove what it uploaded. Uploading from the
 * server means the secret is here, and so a replaced picture can actually be
 * thrown away instead of accumulating for ever.
 *
 * The host is confined to this file: everything above it deals in a URL and an
 * id, so changing hosts again is a change here alone.
 */
const API = 'https://api.cloudinary.com/v1_1';

/** Where avatars are filed, so a bucket of them can be found and managed. */
export const AVATAR_FOLDER = 'merzox/avatars';

function credentials() {
  const cloudName = process.env.CLOUDINARY_CLOUD_NAME;
  const apiKey = process.env.CLOUDINARY_API_KEY;
  const apiSecret = process.env.CLOUDINARY_API_SECRET;

  if (!cloudName || !apiKey || !apiSecret) {
    throw new AppError(
      'Image hosting is not configured',
      503,
      'IMAGE_HOST_NOT_CONFIGURED'
    );
  }

  return { cloudName, apiKey, apiSecret };
}

export function imageHostConfigured() {
  return Boolean(
    process.env.CLOUDINARY_CLOUD_NAME &&
      process.env.CLOUDINARY_API_KEY &&
      process.env.CLOUDINARY_API_SECRET
  );
}

/**
 * Cloudinary's request signature.
 *
 * Every parameter except `file`, `api_key` and `resource_type` is signed, in
 * alphabetical order, with the secret appended. Exported so the shape can be
 * stated in a test rather than trusted.
 */
export function signParams(params, apiSecret) {
  const payload = Object.keys(params)
    .filter((key) => params[key] !== undefined && params[key] !== '')
    .sort()
    .map((key) => `${key}=${params[key]}`)
    .join('&');

  return createHash('sha1').update(`${payload}${apiSecret}`).digest('hex');
}

async function call(endpoint, body, fetchImpl) {
  let response;
  try {
    response = await fetchImpl(endpoint, {
      method: 'POST',
      body,
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' }
    });
  } catch {
    // The reason is deliberately not passed on: it can quote the request, and
    // the request carries the signature.
    throw new AppError('The image could not be uploaded', 502, 'IMAGE_UPLOAD_FAILED');
  }

  try {
    return { ok: response.ok, payload: await response.json() };
  } catch {
    return { ok: false, payload: null };
  }
}

/**
 * Uploads a base64 image.
 *
 * Returns the URL to render from and the id the host files it under - the id
 * is what [deleteImage] later needs, and a URL cannot be turned back into one
 * reliably, so the caller is expected to keep both.
 */
export async function uploadImage(
  base64,
  { fetchImpl = fetch, contentType = 'image/png' } = {}
) {
  const { cloudName, apiKey, apiSecret } = credentials();
  const timestamp = Math.floor(Date.now() / 1000);

  const signed = { folder: AVATAR_FOLDER, timestamp };
  const body = new URLSearchParams({
    ...signed,
    file: `data:${contentType};base64,${base64}`,
    api_key: apiKey,
    signature: signParams(signed, apiSecret)
  });

  const { ok, payload } = await call(`${API}/${cloudName}/image/upload`, body, fetchImpl);
  const url = payload?.secure_url ?? payload?.url;
  const publicId = payload?.public_id;

  if (!ok || typeof url !== 'string' || !url || typeof publicId !== 'string') {
    throw new AppError('The image could not be uploaded', 502, 'IMAGE_UPLOAD_FAILED');
  }

  return { url, publicId };
}

/**
 * Removes an image the host is keeping.
 *
 * Returns whether it is gone. A picture that was already missing counts as
 * gone: the point of the call is the absence, not the deleting.
 *
 * This never throws. It is called after a replacement has already been stored,
 * and failing the whole request because a superseded picture could not be
 * tidied away would turn a successful change into an error for the merchant.
 */
export async function deleteImage(publicId, { fetchImpl = fetch } = {}) {
  if (!publicId) return false;

  let cloudName;
  let apiKey;
  let apiSecret;
  try {
    ({ cloudName, apiKey, apiSecret } = credentials());
  } catch {
    return false;
  }

  const timestamp = Math.floor(Date.now() / 1000);
  // Destroying an asset removes it from the account, but copies already
  // handed out sit in the delivery network's edge caches and keep being
  // served from there. `invalidate` purges those too, which is the difference
  // between the picture being unlisted and the picture being gone.
  const signed = { invalidate: true, public_id: publicId, timestamp };
  const body = new URLSearchParams({
    ...signed,
    api_key: apiKey,
    signature: signParams(signed, apiSecret)
  });

  // `call` refuses an unreachable host by throwing, which is right for an
  // upload and wrong here: this promises an answer, not an exception.
  let outcome;
  try {
    outcome = await call(`${API}/${cloudName}/image/destroy`, body, fetchImpl);
  } catch {
    return false;
  }

  const { ok, payload } = outcome;

  return ok && (payload?.result === 'ok' || payload?.result === 'not found');
}
