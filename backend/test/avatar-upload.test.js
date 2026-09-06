import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import test from 'node:test';

import {
  UPLOAD_CONTENT_TYPES,
  UPLOAD_MAX_BYTES,
  readUploadedImage,
  PRODUCT_IMAGE_CODES,
  IMAGE_UPLOAD_PATHS,
  UPLOAD_BODY_LIMIT_BYTES
} from '../src/policies/avatar.policy.js';
import {
  AVATAR_FOLDER,
  deleteImage,
  PRODUCT_FOLDER,
  imageHostConfigured,
  signParams,
  uploadImage
} from '../src/services/image-host.service.js';

/// Profile pictures.
///
/// The account document had nowhere to put one, so the app drew a fixed icon
/// for every merchant. The picture now lives on an image host and the account
/// keeps its URL - and the host's secret stays here rather than in the app,
/// where anyone with the APK could read it out.
///
/// That placement is also what makes deletion possible. Cloudinary has no
/// unsigned delete, only an unsigned upload, so a client that uploads directly
/// can never remove what it uploaded. Uploading from the server means a
/// replaced picture can actually be thrown away.

const PIXEL =
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk' +
  'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

// A payload of at most `count` bytes. Four base64 characters carry three
// bytes, and no padding keeps the arithmetic exact.
function ofBytes(count) {
  return 'A'.repeat(Math.floor(count / 3) * 4);
}

function withCredentials() {
  process.env.CLOUDINARY_CLOUD_NAME = 'test-cloud';
  process.env.CLOUDINARY_API_KEY = '123456789012345';
  process.env.CLOUDINARY_API_SECRET = 'test-secret';
}

function withoutCredentials() {
  delete process.env.CLOUDINARY_CLOUD_NAME;
  delete process.env.CLOUDINARY_API_KEY;
  delete process.env.CLOUDINARY_API_SECRET;
}

test('a bare base64 image is accepted', () => {
  const read = readUploadedImage({ image: PIXEL });

  assert.equal(read.base64, PIXEL);
  assert.ok(read.bytes > 0);
});

test('a data URL is accepted, and declares its own type', () => {
  const read = readUploadedImage({ image: `data:image/png;base64,${PIXEL}` });

  assert.equal(read.base64, PIXEL);
  assert.equal(read.contentType, 'image/png');
});

test('wrapped base64 is read, not treated as corruption', () => {
  // Some encoders break the payload at 76 columns. The newlines are legal.
  const wrapped = PIXEL.replace(/(.{20})/g, '$1\n');

  assert.equal(readUploadedImage({ image: wrapped }).base64, PIXEL);
});

test('a missing image is named as such', () => {
  for (const body of [{}, { image: '' }, { image: '   ' }, { image: 42 }]) {
    assert.throws(
      () => readUploadedImage(body),
      (error) => error.code === 'AVATAR_IMAGE_REQUIRED',
      JSON.stringify(body)
    );
  }
});

test('something that is not base64 is refused', () => {
  for (const image of ['not base64!', 'AAA', '####']) {
    assert.throws(
      () => readUploadedImage({ image }),
      (error) => error.code === 'AVATAR_IMAGE_INVALID',
      image
    );
  }
});

test('a format the app cannot render is refused', () => {
  assert.throws(
    () => readUploadedImage({ image: `data:image/tiff;base64,${PIXEL}` }),
    (error) => error.code === 'AVATAR_CONTENT_TYPE_UNSUPPORTED'
  );

  for (const type of UPLOAD_CONTENT_TYPES) {
    assert.doesNotThrow(() =>
      readUploadedImage({ image: `data:${type};base64,${PIXEL}` })
    );
  }
});

test('an oversized image is refused before it is decoded', () => {
  assert.doesNotThrow(() =>
    readUploadedImage({ image: ofBytes(UPLOAD_MAX_BYTES) })
  );

  assert.throws(
    () => readUploadedImage({ image: ofBytes(UPLOAD_MAX_BYTES + 3) }),
    (error) => error.code === 'AVATAR_IMAGE_TOO_LARGE'
  );
});

test('the signature is over the sorted parameters, secret appended', () => {
  // Stated by hand rather than by calling the same code twice: this is the one
  // thing the host checks, and a signature that agreed only with itself would
  // be rejected there and by nothing here.
  const expected = createHash('sha1')
    .update('folder=merzox/avatars&timestamp=1700000000test-secret')
    .digest('hex');

  assert.equal(
    signParams({ timestamp: 1700000000, folder: AVATAR_FOLDER }, 'test-secret'),
    expected
  );
});

test('empty parameters are left out of the signature', () => {
  assert.equal(
    signParams({ timestamp: 1, public_id: '', folder: undefined }, 's'),
    signParams({ timestamp: 1 }, 's')
  );
});

test('a successful upload returns the URL and the id to delete it by', async () => {
  withCredentials();
  let sent = null;

  const result = await uploadImage(PIXEL, {
    fetchImpl: async (endpoint, options) => {
      sent = { endpoint, body: options.body };
      return {
        ok: true,
        json: async () => ({
          secure_url: 'https://res.cloudinary.com/test-cloud/x.png',
          public_id: 'merzox/avatars/abc123'
        })
      };
    }
  });

  assert.equal(result.url, 'https://res.cloudinary.com/test-cloud/x.png');
  // The id is kept because a URL cannot be turned back into one, and without
  // it a replaced picture could never be removed.
  assert.equal(result.publicId, 'merzox/avatars/abc123');

  assert.equal(
    sent.endpoint,
    'https://api.cloudinary.com/v1_1/test-cloud/image/upload'
  );
  assert.equal(sent.body.get('folder'), AVATAR_FOLDER);
  assert.equal(sent.body.get('api_key'), '123456789012345');
  assert.ok(sent.body.get('file').startsWith('data:image/png;base64,'));

  // The secret itself never goes on the wire - only what it signed.
  assert.ok(!sent.body.toString().includes('test-secret'));
});

test('the file itself is not signed, only the parameters beside it', async () => {
  withCredentials();
  let sent = null;

  await uploadImage(PIXEL, {
    fetchImpl: async (_, options) => {
      sent = options.body;
      return {
        ok: true,
        json: async () => ({ secure_url: 'https://x/y.png', public_id: 'p' })
      };
    }
  });

  assert.equal(
    sent.get('signature'),
    signParams(
      { folder: AVATAR_FOLDER, timestamp: Number(sent.get('timestamp')) },
      'test-secret'
    )
  );
});

test('a host that answers without both is a failure, not a blank picture', async () => {
  withCredentials();

  for (const payload of [
    { ok: true, json: async () => ({}) },
    { ok: true, json: async () => ({ secure_url: 'https://x/y.png' }) },
    { ok: true, json: async () => ({ public_id: 'p' }) },
    {
      ok: false,
      json: async () => ({ secure_url: 'https://x/y.png', public_id: 'p' })
    },
    {
      ok: true,
      json: async () => {
        throw new Error('not json');
      }
    }
  ]) {
    await assert.rejects(
      () => uploadImage(PIXEL, { fetchImpl: async () => payload }),
      (error) => error.code === 'IMAGE_UPLOAD_FAILED'
    );
  }
});

test('a network failure never carries the request back', async () => {
  withCredentials();

  await assert.rejects(
    () =>
      uploadImage(PIXEL, {
        fetchImpl: async () => {
          throw new Error('connect ECONNREFUSED, signature=deadbeef');
        }
      }),
    (error) => {
      // The underlying reason can quote the request, and the request carries
      // the signature. It must not reach a log or a client.
      assert.equal(error.code, 'IMAGE_UPLOAD_FAILED');
      assert.ok(!error.message.includes('deadbeef'));
      return true;
    }
  );
});

test('an unconfigured host says so instead of failing obscurely', async () => {
  withoutCredentials();
  assert.equal(imageHostConfigured(), false);

  await assert.rejects(
    () => uploadImage(PIXEL, { fetchImpl: async () => ({ ok: true }) }),
    (error) => error.code === 'IMAGE_HOST_NOT_CONFIGURED'
  );
});

test('half a configuration is no configuration', async () => {
  withoutCredentials();
  process.env.CLOUDINARY_CLOUD_NAME = 'test-cloud';
  process.env.CLOUDINARY_API_KEY = '123';

  // Without the secret nothing can be signed. Refused here rather than by the
  // host, which would read as an upload failure and send the merchant looking
  // at their picture instead of at the configuration.
  assert.equal(imageHostConfigured(), false);
  await assert.rejects(
    () => uploadImage(PIXEL, { fetchImpl: async () => ({ ok: true }) }),
    (error) => error.code === 'IMAGE_HOST_NOT_CONFIGURED'
  );
});

test('a replaced picture is deleted by its id', async () => {
  withCredentials();
  let sent = null;

  const gone = await deleteImage('merzox/avatars/abc123', {
    fetchImpl: async (endpoint, options) => {
      sent = { endpoint, body: options.body };
      return { ok: true, json: async () => ({ result: 'ok' }) };
    }
  });

  assert.equal(gone, true);
  assert.equal(
    sent.endpoint,
    'https://api.cloudinary.com/v1_1/test-cloud/image/destroy'
  );
  assert.equal(sent.body.get('public_id'), 'merzox/avatars/abc123');

  // Removing the asset is not enough on its own: copies already handed out
  // sit in edge caches and keep being served. Without this the old picture
  // stays reachable at its old URL after it was supposedly deleted.
  assert.equal(sent.body.get('invalidate'), 'true');

  assert.equal(
    sent.body.get('signature'),
    signParams(
      {
        invalidate: true,
        public_id: 'merzox/avatars/abc123',
        timestamp: Number(sent.body.get('timestamp'))
      },
      'test-secret'
    )
  );
});

test('a picture that was already gone counts as gone', async () => {
  withCredentials();

  // The point of the call is the absence, not the deleting.
  assert.equal(
    await deleteImage('p', {
      fetchImpl: async () => ({
        ok: true,
        json: async () => ({ result: 'not found' })
      })
    }),
    true
  );
});

test('a tidy-up that fails is reported, never thrown', async () => {
  withCredentials();

  // It runs after the replacement is already stored. Throwing here would turn
  // a successful change into an error the merchant has to read.
  for (const fetchImpl of [
    async () => ({ ok: true, json: async () => ({ result: 'error' }) }),
    async () => ({ ok: false, json: async () => ({}) }),
    async () => {
      throw new Error('offline');
    }
  ]) {
    assert.equal(await deleteImage('p', { fetchImpl }), false);
  }

  // Nothing to delete is not a failure either, and costs no request.
  assert.equal(
    await deleteImage('', { fetchImpl: async () => ({ ok: true }) }),
    false
  );

  withoutCredentials();
  assert.equal(
    await deleteImage('p', { fetchImpl: async () => ({ ok: true }) }),
    false
  );
});

/// Product photos travel the same road as a profile picture.
///
/// A product's images are stored as URLs, so until this the only way to add one
/// was to already have it hosted somewhere - which asks a shopkeeper to run an
/// image host before they can list a jar of cream. The rules are the same for
/// both pictures; only the folder they land in and the codes a refusal carries
/// are different.

test('a product image is refused by the same rules as a profile picture', () => {
  assert.throws(
    () => readUploadedImage({ image: '   ' }, { codes: PRODUCT_IMAGE_CODES }),
    (error) => error.code === 'PRODUCT_IMAGE_REQUIRED'
  );

  assert.throws(
    () => readUploadedImage({ image: 'not base64!' }, { codes: PRODUCT_IMAGE_CODES }),
    (error) => error.code === 'PRODUCT_IMAGE_INVALID'
  );
});

test('a refusal names the picture it is about', () => {
  // "That avatar is too large" for a product photo would send a merchant
  // looking at the wrong screen.
  assert.throws(
    () =>
      readUploadedImage(
        { image: 'data:image/tiff;base64,AAAA' },
        { codes: PRODUCT_IMAGE_CODES }
      ),
    (error) => error.code === 'PRODUCT_CONTENT_TYPE_UNSUPPORTED'
  );
});

test('the codes default to the picture that had this first', () => {
  assert.throws(
    () => readUploadedImage({ image: '' }),
    (error) => error.code === 'AVATAR_IMAGE_REQUIRED'
  );
});

test('product photos are kept in their own folder', async () => {
  const sent = [];
  const fetchImpl = async (url, init) => {
    sent.push(new URLSearchParams(init.body));
    return {
      ok: true,
      json: async () => ({ secure_url: 'https://cdn/x.jpg', public_id: 'p' })
    };
  };

  process.env.CLOUDINARY_CLOUD_NAME = 'c';
  process.env.CLOUDINARY_API_KEY = 'k';
  process.env.CLOUDINARY_API_SECRET = 's';

  await uploadImage('AAAA', { fetchImpl, folder: PRODUCT_FOLDER });

  assert.equal(sent[0].get('folder'), PRODUCT_FOLDER);
  assert.notEqual(PRODUCT_FOLDER, AVATAR_FOLDER);
});

test('the folder is signed, not merely sent', async () => {
  // An unsigned folder would let a caller choose where somebody else's
  // pictures land.
  const bodies = [];
  const fetchImpl = async (url, init) => {
    bodies.push(new URLSearchParams(init.body));
    return {
      ok: true,
      json: async () => ({ secure_url: 'https://cdn/x.jpg', public_id: 'p' })
    };
  };

  await uploadImage('AAAA', { fetchImpl, folder: AVATAR_FOLDER });
  await uploadImage('AAAA', { fetchImpl, folder: PRODUCT_FOLDER });

  assert.notEqual(bodies[0].get('signature'), bodies[1].get('signature'));
});

/// How large a body carrying a picture is allowed to be.
///
/// The rule said five megabytes and the body parser said thirty-two kilobytes,
/// and the parser wins - it refuses the request before any route sees it. A
/// photo from a phone camera is a few hundred kilobytes even after the picker
/// shrinks it, so every upload came back as "an unexpected error" while the
/// rule that would have accepted it never ran.

test('the body limit clears an image at the ceiling, base64 and all', () => {
  // Four bytes out for every three in, plus the JSON around it. A limit set to
  // the image ceiling itself rejects every image at the ceiling.
  const encoded = Math.ceil(UPLOAD_MAX_BYTES * 4 / 3);

  assert.ok(UPLOAD_BODY_LIMIT_BYTES > encoded);
  assert.ok(UPLOAD_BODY_LIMIT_BYTES < UPLOAD_MAX_BYTES * 2);
});

test('the limit is far past what a camera actually sends', () => {
  // A real photo from the reader's phone, shrunk by the picker to 1600px at
  // quality 85, measured 277 KB - 369 KB once encoded.
  assert.ok(UPLOAD_BODY_LIMIT_BYTES > 400 * 1024);
});

test('both routes that carry a picture are named', () => {
  assert.deepEqual(IMAGE_UPLOAD_PATHS, [
    '/api/v1/users/me/avatar',
    '/api/v1/businesses/me/product-images'
  ]);
});

test('the paths are the ones the app actually posts to', async () => {
  // Named here rather than guessed at the mount point: a route added without
  // its entry goes back to the small limit and fails the same silent way.
  const routes = await readFile(
    new URL('../src/routes/business.routes.js', import.meta.url),
    'utf8'
  );

  assert.ok(routes.includes("'/me/product-images'"));
  assert.ok(IMAGE_UPLOAD_PATHS.some((path) => path.endsWith('/me/product-images')));
});
