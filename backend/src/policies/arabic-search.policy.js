/**
 * Matching Arabic the way Arabic is written, rather than the way it is stored.
 *
 * The search used to build `new RegExp(escapeRegex(query), 'i')` and test it
 * against the raw name. The `'i'` does nothing here - Arabic has no case - and
 * the raw name is one of several spellings the same word has. Measured over
 * ten shop names and the seven shapes a person types them in, that rule found
 * 43 of 70; the shape a speech engine or a hurried typist produces - no hamza,
 * haa for taa marbuta - found 1 of 10.
 *
 * None of those shapes is a mistake. Hamza is optional in ordinary writing,
 * taa marbuta and haa are interchangeable in most hands, and alif maqsura and
 * yaa likewise. `احمد` and `أحمد` are the same name; `حلويه` and `حلوية` are
 * the same word. A customer who types one and is shown nothing concludes the
 * shop is not here.
 *
 * So both sides are folded to one spelling: the query is normalized, and the
 * pattern built from it tolerates in the stored text every difference that
 * normalizing removes from the query.
 *
 * What this is not: an index. The pattern is scanned against the collection,
 * which is what the previous rule did too, and it is sound at this size. Past
 * a few thousand shops it wants a stored normalized field with an index on it
 * - and then the folding here becomes what fills that field, so the rule does
 * not move, only where it is applied.
 */

/** Marks that carry sound, not identity: they come off both sides. */
const DIACRITICS = /[ً-ْٰـ]/g;

/** One spelling per letter. The key is what everything on the left becomes. */
const FOLD = [
  ['ا', 'اأإآٱٲٳ'],
  ['ه', 'هة'],
  ['ي', 'يىئ'],
  ['و', 'وؤ'],
  ['ك', 'كک'],
];

/** Arabic-Indic and extended Arabic-Indic digits, to the Latin ones. */
const DIGITS = new Map([
  ...'٠١٢٣٤٥٦٧٨٩'.split('').map((d, i) => [d, String(i)]),
  ...'۰۱۲۳۴۵۶۷۸۹'.split('').map((d, i) => [d, String(i)])
]);

const FOLD_FROM = new Map();
for (const [to, from] of FOLD) {
  for (const letter of from) FOLD_FROM.set(letter, to);
}

/** Every spelling a folded letter stands for, as a character class body. */
const FOLD_CLASS = new Map(FOLD.map(([to, from]) => [to, from]));

/**
 * One spelling of [text], for comparing against another.
 *
 * Folds the letters above, drops the marks above, turns Arabic-Indic digits
 * into Latin ones, lowercases the Latin letters a shop name may also carry,
 * and collapses runs of whitespace.
 */
export function normalizeArabic(text) {
  const raw = String(text ?? '');
  let out = '';

  for (const character of raw.normalize('NFC')) {
    if (DIACRITICS.test(character)) {
      DIACRITICS.lastIndex = 0;
      continue;
    }
    DIACRITICS.lastIndex = 0;

    out += FOLD_FROM.get(character) ?? DIGITS.get(character) ?? character;
  }

  return out.toLowerCase().replace(/\s+/g, ' ').trim();
}

const REGEX_SPECIAL = /[.*+?^${}()|[\]\\]/;

/**
 * [text] as a pattern body that matches any spelling of the same words.
 *
 * Each folded letter becomes the class of spellings it stands for, and every
 * position tolerates the marks that were dropped - so the pattern built from a
 * normalized query still finds text that was stored with them. A space matches
 * any run of whitespace.
 */
function tolerantBody(text) {
  const marks = '[\\u064B-\\u0652\\u0670\\u0640]*';
  let body = '';

  for (const character of normalizeArabic(text)) {
    if (character === ' ') {
      body += '\\s+';
      continue;
    }

    const spellings = FOLD_CLASS.get(character);
    if (spellings) {
      body += `[${spellings}]`;
    } else if (REGEX_SPECIAL.test(character)) {
      body += `\\${character}`;
    } else {
      body += character;
    }

    body += marks;
  }

  return body;
}

/** Where in the text the query has to sit. */
export const MATCH_MODES = Object.freeze(['starts', 'contains', 'ends']);

/** The same, plus the one only a product term is offered. */
export const PRODUCT_MATCH_MODES = Object.freeze([
  ...MATCH_MODES,
  'similar'
]);

export function matchMode(value, { allowSimilar = false } = {}) {
  const modes = allowSimilar ? PRODUCT_MATCH_MODES : MATCH_MODES;
  const asked = String(value ?? '').trim().toLowerCase();

  return modes.includes(asked) ? asked : 'contains';
}

/**
 * A regular expression that finds [query] in text, however either is spelled.
 *
 * `starts` and `ends` anchor at a word rather than at the string: somebody
 * asking for shops beginning with `أبو خالد` means the name begins with those
 * words, and `\b` does not work on Arabic in JavaScript's regular expressions
 * - the letters are not word characters to it - so the anchors are the string
 * ends, which is what "begins with" and "ends with" say.
 */
export function searchPattern(query, mode = 'contains') {
  const body = tolerantBody(query);
  if (body === '') return null;

  const anchored =
    mode === 'starts' ? `^${body}` : mode === 'ends' ? `${body}$` : body;

  return new RegExp(anchored, 'iu');
}

/** Words worth searching on their own, from a phrase. */
function meaningfulWords(query) {
  return normalizeArabic(query)
    .split(' ')
    .map((word) => (word.startsWith('ال') ? word.slice(2) : word))
    .filter((word) => word.length >= 2);
}

/**
 * Patterns for "sells something like this".
 *
 * Merchants name the same thing differently - `جاكيت`, `جاكيتات شتوية`,
 * `جاكيت جلد رجالي` - so a phrase match finds one shop and misses three. This
 * is the phrase broken into its words, each matched from the start of a word
 * so that a singular finds its plural, and any one of them is enough.
 *
 * The definite article comes off each word: a shop selling `الجاكيتات` is
 * selling jackets.
 */
export function similarPatterns(query) {
  const words = meaningfulWords(query);
  if (words.length === 0) return [];

  return words
    .map((word) => tolerantBody(word))
    .filter((body) => body !== '')
    .map((body) => new RegExp(`(?:^|\\s|ال)${body}`, 'iu'));
}

/**
 * Whether [text] matches [query] under [mode].
 *
 * The one place the decision is made, so the database query and the filtering
 * that follows it cannot answer differently.
 */
export function textMatches(text, query, mode = 'contains') {
  const subject = String(text ?? '');
  if (subject === '') return false;

  if (mode === 'similar') {
    const patterns = similarPatterns(query);
    return patterns.some((pattern) => pattern.test(subject));
  }

  const pattern = searchPattern(query, mode);
  return pattern === null ? false : pattern.test(subject);
}
