import { AppError } from '../utils/AppError.js';

/**
 * Telling the operator about somebody.
 *
 * Whom it names is read from the conversation, exactly as a block is: there
 * is no id in the request and so none to forge.
 *
 * What a block deliberately does not keep - a reason - is the whole of this.
 * A block only has to change what the app does; a report has to be read by a
 * person afterwards, and a row that said only "somebody complained" would be
 * unactionable. The reason is a closed list rather than free text so that the
 * pile can be sorted, with room for words beside it when the list does not
 * fit what happened.
 */

export const USER_REPORT_CODES = Object.freeze({
  invalidReason: 'INVALID_REPORT_REASON',
  invalidNote: 'INVALID_REPORT_NOTE',
  self: 'CANNOT_REPORT_SELF'
});

/**
 * What a report can be about.
 *
 * Short on purpose: a list nobody reads to the end sorts nothing. `other`
 * exists so that a reader with something real to say is never forced to
 * mislabel it, and the note beside it is where they say it.
 */
export const USER_REPORT_REASONS = Object.freeze([
  'spam',
  'harassment',
  'scam',
  'inappropriate',
  'other'
]);

/// As much of a note as is worth carrying. Long enough for what happened,
/// short enough that the row stays readable.
export const REPORT_NOTE_MAX = 500;

/**
 * Reads a report out of a request body.
 *
 * The reason is required and must be one of the listed ones: a report whose
 * reason the operator cannot sort by is a row they will never act on. The
 * note is optional and trimmed, and an over-long one is refused rather than
 * silently cut - a complaint that arrives half-said is worse than one that
 * was sent back to be shortened.
 */
export function readReport(body = {}) {
  const reason = body.reason;

  if (typeof reason !== 'string' || !USER_REPORT_REASONS.includes(reason)) {
    throw new AppError(
      'A report reason is required',
      400,
      USER_REPORT_CODES.invalidReason
    );
  }

  const raw = body.note;

  if (raw !== undefined && raw !== null && typeof raw !== 'string') {
    throw new AppError(
      'The report note is invalid',
      400,
      USER_REPORT_CODES.invalidNote
    );
  }

  const note = String(raw ?? '').trim();

  if (note.length > REPORT_NOTE_MAX) {
    throw new AppError(
      'The report note is too long',
      400,
      USER_REPORT_CODES.invalidNote
    );
  }

  return { reason, note };
}

/**
 * Refuses a report that names the reader themselves.
 *
 * It cannot happen through a conversation - a shop may not open one with
 * itself - but the rule is stated here rather than trusted to that.
 */
export function assertReportableCounterpart(readerId, counterpartId) {
  if (!counterpartId) {
    throw new AppError(
      'There is nobody to report in this conversation',
      404,
      'CONVERSATION_NOT_FOUND'
    );
  }

  if (String(readerId) === String(counterpartId)) {
    throw new AppError(
      'An account cannot report itself',
      400,
      USER_REPORT_CODES.self
    );
  }

  return counterpartId;
}
