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

/// Product photos are kept apart from profile pictures: a merchant
/// browsing their media should not have to tell one from the other, and
/// the two have different lifetimes.
export const PRODUCT_FOLDER = 'merzox/products';

/**
 * What the host is told to keep, rather than what it was sent.
 *
 * Applied on the way in, so there is one file and it is the smaller one - the
 * original is not filed beside it. `c_limit` never enlarges, so a picture
 * already inside these bounds is stored as it is, and `q_auto:good` picks the
 * compression that keeps it looking the same to the eye.
 *
 * This is here rather than in the app because it has to hold for every way a
 * picture arrives: a camera, a gallery, or a link the merchant pasted, which
 * the app never resized at all.
 */
export const STORED_IMAGE_TRANSFORMATION = 'c_limit,w_1600,h_1600';

/**
 * How the stored picture is asked for when it is rendered.
 *
 * The two halves of "smaller" are not the same job. Bounding the dimensions
 * has to happen on the way in, or the host keeps the twelve-megapixel
 * original for ever. Bounding the *bytes* has to happen on the way out: asked
 * to re-encode a picture on the way in, the host can only answer in the
 * format it arrived as, and a PNG re-encoded as a PNG comes back bigger - a
 * three-thousand pixel test image went in at 2.4MB and was stored at 4.0MB
 * before this was split in two.
 *
 * On the way out it may choose the format, so a phone that understands WebP
 * or AVIF is sent one of those and everything else still gets the PNG or the
 * JPEG. `q_auto:good` picks the compression that keeps it looking the same.
 * Transparency survives, which a blanket conversion to JPEG would not, and a
 * logo is the one picture most likely to have any.
 */
export const DELIVERED_IMAGE_TRANSFORMATION = 'f_auto,q_auto:good';

/**
 * Rewrites an upload URL into the one to render from.
 *
 * Cloudinary reads the transformation out of the path, so this is a text edit
 * on a URL rather than a second request. Anything that is not one of its
 * upload URLs is handed back untouched: this is not the place to decide a
 * foreign address is wrong.
 */
export function deliveryUrl(url) {
  if (typeof url !== 'string') return url;

  const marker = '/image/upload/';
  const at = url.indexOf(marker);
  if (at === -1) return url;

  const after = at + marker.length;
  // Already carrying it - an upload answered twice, or a URL that has been
  // through here before. Adding it again would not be wrong, but it would be
  // a longer URL saying the same thing twice.
  if (url.slice(after).startsWith(`${DELIVERED_IMAGE_TRANSFORMATION}/`)) {
    return url;
  }

  return `${url.slice(0, after)}${DELIVERED_IMAGE_TRANSFORMATION}/${url.slice(after)}`;
}

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
  { fetchImpl = fetch, contentType = 'image/png', folder = AVATAR_FOLDER } = {}
) {
  const { cloudName, apiKey, apiSecret } = credentials();
  const timestamp = Math.floor(Date.now() / 1000);

  // The folder is part of what is signed: an unsigned one would let a caller
  // choose where somebody else's pictures land. So is the transformation - it
  // is what makes the stored file the small one, and a caller who could drop
  // it could fill the account with originals.
  const signed = {
    folder,
    timestamp,
    transformation: STORED_IMAGE_TRANSFORMATION
  };
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

  // What is handed back is the address to render from, not the address the
  // master sits at. The id is the master, and that is what deletion needs.
  return { url: deliveryUrl(url), publicId };
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
