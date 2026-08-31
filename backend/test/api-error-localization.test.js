import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const here = path.dirname(fileURLToPath(import.meta.url));
const backendSrc = path.join(here, '..', 'src');
const repoRoot = path.join(here, '..', '..');

/**
 * Directories whose refusals reach an HTTP client.
 *
 * `src/scripts` is deliberately absent: a CLI refusal is read by whoever ran
 * the command, never by the app, so translating it would be theatre.
 */
const CLIENT_FACING = ['controllers', 'middleware', 'policies', 'routes', 'services', 'utils'];

/**
 * Object fields that carry an uppercase constant into a log line rather than
 * onto the wire.
 *
 * `appCode` and `reason` are both log payload: they name what the server did
 * for whoever reads the journal afterwards. A constant that appears only there
 * is never shown to anyone, so it needs no sentence.
 */
const LOG_FIELDS = new Set(['appCode', 'reason']);

function jsFilesUnder(dir) {
  const out = [];

  for (const entry of readdirSync(dir)) {
    const full = path.join(dir, entry);

    if (statSync(full).isDirectory()) {
      out.push(...jsFilesUnder(full));
      continue;
    }

    if (entry.endsWith('.js')) {
      out.push(full);
    }
  }

  return out;
}

/**
 * Every error code the API can put on the wire.
 *
 * Two shapes carry one: the third argument of `new AppError`, and any named
 * field holding an uppercase constant - which covers both the `code` of the
 * objects the policies hand back and the code tables they export. Log fields
 * are skipped, since nothing there reaches a reader.
 */
export function serverErrorCodes() {
  const codes = new Set();

  for (const group of CLIENT_FACING) {
    for (const file of jsFilesUnder(path.join(backendSrc, group))) {
      const source = readFileSync(file, 'utf8');

      for (const match of source.matchAll(
        /new AppError\((?:[^()]|\([^()]*\))*?'([A-Z][A-Z0-9_]{3,})'\s*\)/gs
      )) {
        codes.add(match[1]);
      }

      for (const match of source.matchAll(
        /(\w+):\s*'([A-Z][A-Z0-9_]{3,})'/g
      )) {
        if (!LOG_FIELDS.has(match[1])) codes.add(match[2]);
      }
    }
  }

  return codes;
}

/** The client's code-to-key map, read out of the Dart source it lives in. */
export function clientErrorKeys() {
  const source = readFileSync(
    path.join(repoRoot, 'lib', 'core', 'localization', 'api_error_codes.dart'),
    'utf8'
  );
  const entries = new Map();

  for (const match of source.matchAll(/'([A-Z][A-Z0-9_]+)':\s*'([^']+)'/g)) {
    entries.set(match[1], match[2]);
  }

  return entries;
}

function translations(locale) {
  return JSON.parse(
    readFileSync(
      path.join(repoRoot, 'assets', 'translations', `${locale}.json`),
      'utf8'
    )
  );
}

test('every server error code has a client translation', () => {
  const server = serverErrorCodes();
  const client = clientErrorKeys();

  assert.ok(server.size > 100, `expected a real corpus, found ${server.size}`);

  const untranslated = [...server].filter((code) => !client.has(code)).sort();

  assert.deepEqual(
    untranslated,
    [],
    `these codes would reach an Arabic screen in English: ${untranslated.join(', ')}`
  );
});

test('every mapped key exists in both translation files', () => {
  const client = clientErrorKeys();
  const arabic = translations('ar');
  const english = translations('en');

  const missing = [];

  for (const [code, key] of client) {
    const [section, leaf] = key.split('.');
    assert.equal(section, 'apiErrors', `${code} points outside apiErrors`);

    if (typeof arabic[section]?.[leaf] !== 'string') missing.push(`ar:${key}`);
    if (typeof english[section]?.[leaf] !== 'string') missing.push(`en:${key}`);
  }

  assert.deepEqual(missing, []);
});

test('no mapped Arabic sentence is left in English', () => {
  const client = clientErrorKeys();
  const arabic = translations('ar');
  const arabicLetter = /[؀-ۿ]/;

  const english = [...new Set(client.values())]
    .map((key) => key.split('.')[1])
    .filter((leaf) => !arabicLetter.test(arabic.apiErrors[leaf] ?? ''));

  assert.deepEqual(english, []);
});
