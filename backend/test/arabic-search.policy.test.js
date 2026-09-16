import assert from 'node:assert/strict';
import test from 'node:test';

import {
  matchMode,
  patternIsPortable,
  normalizeArabic,
  searchPattern,
  similarPatterns,
  textMatches
} from '../src/policies/arabic-search.policy.js';

/**
 * The spellings in these cases are not mistakes.
 *
 * Hamza is optional in ordinary Arabic writing, taa marbuta and haa are
 * interchangeable in most hands, and alif maqsura and yaa likewise. A customer
 * types one of them; which one is not a decision they made, and the shop they
 * are looking for was registered under another.
 */

test('the spellings of one name fold together', () => {
  assert.equal(normalizeArabic('أبو خالد'), 'ابو خالد');
  assert.equal(normalizeArabic('إبراهيم'), 'ابراهيم');
  assert.equal(normalizeArabic('حلوية'), 'حلويه');
  assert.equal(normalizeArabic('مصطفى'), 'مصطفي');
  assert.equal(normalizeArabic('مسؤول'), 'مسوول');
});

test('marks that carry sound rather than identity come off', () => {
  assert.equal(normalizeArabic('مَكْتَبَة'), 'مكتبه');
  assert.equal(normalizeArabic('مــكتبة'), 'مكتبه');
});

test('digits are digits whichever way they are drawn', () => {
  assert.equal(normalizeArabic('متجر ٢٤ ساعة'), 'متجر 24 ساعه');
});

test('runs of whitespace are one space, and the edges go', () => {
  assert.equal(normalizeArabic('  حلويات   أبو  خالد '), 'حلويات ابو خالد');
});

test('Latin letters in a shop name are lowercased', () => {
  assert.equal(normalizeArabic('Merzox STORE'), 'merzox store');
});

// ---------------------------------------------------------------------------
// The measurement that started this: 43 of 70 under the old rule.
// ---------------------------------------------------------------------------

const catalogue = [
  'حلويات أبو خالد',
  'مخبز الإخوة',
  'سوبرماركت الأمانة',
  'مطعم الآصالة',
  'بقالة أم عمر',
  'ملابس الرؤية',
  'مكتبة الطالب',
  'عصائر الواحة',
  'جاكيتات الشتاء',
  'مقهى الصفا'
];

/** How the same name arrives from a keyboard or a speech engine. */
function spokenForms(name) {
  const bare = name.replace(/[أإآ]/g, 'ا').replace(/ة/g, 'ه').replace(/ى/g, 'ي');
  const distinctive = name.split(' ').slice(1).join(' ') || name;

  return [
    name,
    name.replace(/[أإآ]/g, 'ا'),
    name.replace(/ة/g, 'ه'),
    name.replace(/ى/g, 'ي'),
    bare,
    distinctive,
    distinctive.replace(/[أإآ]/g, 'ا')
  ];
}

test('every spelling of every name finds it', () => {
  const missed = [];

  for (const name of catalogue) {
    for (const asked of spokenForms(name)) {
      if (!textMatches(name, asked, 'contains')) missed.push([name, asked]);
    }
  }

  assert.deepEqual(missed, [], 'these spellings found nothing');
});

test('and it works the other way, when the shop dropped the hamza', () => {
  // The merchant registered `حلويات ابو خالد`; the customer writes it properly.
  assert.equal(textMatches('حلويات ابو خالد', 'حلويات أبو خالد'), true);
  assert.equal(textMatches('مكتبه الطالب', 'مكتبة الطالب'), true);
});

test('folding brings names together, it does not blur them apart', () => {
  assert.equal(textMatches('حلويات أبو خالد', 'أبو سعيد'), false);
  assert.equal(textMatches('مخبز الإخوة', 'مطعم'), false);
  assert.equal(textMatches('مكتبة الطالب', 'مكتبة الطلاب'), false);
});

// ---------------------------------------------------------------------------
// Where in the name the words have to sit
// ---------------------------------------------------------------------------

test('starts with, contains, ends with', () => {
  const name = 'حلويات أبو خالد';

  assert.equal(textMatches(name, 'حلويات', 'starts'), true);
  assert.equal(textMatches(name, 'ابو خالد', 'starts'), false);

  assert.equal(textMatches(name, 'ابو', 'contains'), true);

  assert.equal(textMatches(name, 'ابو خالد', 'ends'), true);
  assert.equal(textMatches(name, 'حلويات', 'ends'), false);
});

test('the anchors hold through the folding', () => {
  // `أبو` in the query, `ابو` in the name, and still anchored at the end.
  assert.equal(textMatches('حلويات ابو خالد', 'أبو خالد', 'ends'), true);
  assert.equal(textMatches('حلويات ابو خالد', 'أبو', 'ends'), false);
});

test('an empty query is not a pattern that matches everything', () => {
  assert.equal(searchPattern('', 'contains'), null);
  assert.equal(searchPattern('   ', 'contains'), null);
  assert.equal(textMatches('حلويات أبو خالد', ''), false);
  assert.equal(textMatches('', 'حلويات'), false);
});

// ---------------------------------------------------------------------------
// "sells something like this"
// ---------------------------------------------------------------------------

test('a singular finds the plural, and the phrase finds its parts', () => {
  assert.equal(textMatches('جاكيتات شتوية', 'جاكيت', 'similar'), true);
  assert.equal(textMatches('جاكيت جلد رجالي', 'جاكيت', 'similar'), true);
  assert.equal(textMatches('جاكيت', 'جاكيت جلد', 'similar'), true);
  assert.equal(textMatches('الجاكيتات', 'جاكيت', 'similar'), true);
});

test('similar matches a word, not a fragment inside one', () => {
  // Otherwise `تفاح` finds `مفاتيح` and the tab fills with nonsense.
  assert.equal(textMatches('سماعات', 'عات', 'similar'), false);
  assert.equal(textMatches('برتقال', 'قال', 'similar'), false);
});

test('similar drops the words that carry nothing', () => {
  // One letter is not a search term; the definite article is not a product.
  assert.deepEqual(similarPatterns('و'), []);
  assert.deepEqual(similarPatterns('ال'), []);
});

test('similar is any of the words, not all of them', () => {
  assert.equal(textMatches('عصير برتقال', 'جاكيت او عصير', 'similar'), true);
});

// ---------------------------------------------------------------------------
// The mode a request asks for
// ---------------------------------------------------------------------------

test('an unknown or missing mode is contains', () => {
  assert.equal(matchMode(undefined), 'contains');
  assert.equal(matchMode('nonsense'), 'contains');
  assert.equal(matchMode(''), 'contains');
});

test('the modes are taken as given, whatever the casing', () => {
  assert.equal(matchMode('starts'), 'starts');
  assert.equal(matchMode('ENDS'), 'ends');
  assert.equal(matchMode(' Contains '), 'contains');
});

test('similar is offered to a product term and to nothing else', () => {
  assert.equal(matchMode('similar'), 'contains');
  assert.equal(matchMode('similar', { allowSimilar: true }), 'similar');
});

// ---------------------------------------------------------------------------
// The patterns leave here and are read by something that is not JavaScript
// ---------------------------------------------------------------------------

/**
 * These are handed to MongoDB, which reads them as PCRE.
 *
 * The two dialects agree on almost everything and disagree on the escapes, so
 * a pattern can be correct in every test above - they all run in JavaScript -
 * and invalid in the only place it is used. That is not hypothetical: the
 * first version of this file spelled a character class with `\uXXXX`, which
 * PCRE has no such escape for, and a shop called `البتول كوزماتيكس` could not
 * be found by `بتول`. Every test above passed while it was broken.
 *
 * So this reads the source rather than the behaviour.
 */

test('no pattern this file builds carries a JavaScript-only escape', () => {
  const queries = [
    'بتول',
    'البتول كوزماتيكس',
    'حلويات أبو خالد',
    'مكتبة الطالب',
    'متجر ٢٤ ساعة',
    'a.*b',
    'Merzox STORE'
  ];

  for (const query of queries) {
    for (const mode of ['starts', 'contains', 'ends']) {
      const pattern = searchPattern(query, mode);
      assert.ok(
        patternIsPortable(pattern.source),
        `"${query}" (${mode}) built ${pattern.source}`
      );
    }

    for (const pattern of similarPatterns(query)) {
      assert.ok(
        patternIsPortable(pattern.source),
        `"${query}" (similar) built ${pattern.source}`
      );
    }
  }
});

test('the guard knows an unportable pattern when it sees one', () => {
  // Otherwise the test above passes because it is looking for nothing.
  // `String.raw` so these are the escape *text* a pattern source would carry,
  // not the characters they stand for - which is the whole distinction.
  assert.equal(patternIsPortable(String.raw`\u064B`), false);
  assert.equal(patternIsPortable(String.raw`[\u064B-\u0652]`), false);
  assert.equal(patternIsPortable(String.raw`\p{Arabic}`), false);
  assert.equal(patternIsPortable('(?<word>x)'), false);
  assert.equal(patternIsPortable('[ً-ْٰـ]*'), true);
});

test('the shop that was missed is found, in every spelling of it', () => {
  const name = 'البتول كوزماتيكس';

  for (const asked of ['بتول', 'البتول', 'كوزماتيكس', 'البتول كوزماتيكس']) {
    assert.equal(textMatches(name, asked, 'contains'), true, asked);
  }

  assert.equal(textMatches(name, 'البتول', 'starts'), true);
  assert.equal(textMatches(name, 'كوزماتيكس', 'ends'), true);
});
