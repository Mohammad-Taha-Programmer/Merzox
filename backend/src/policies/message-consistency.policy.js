import { AppError } from '../utils/AppError.js';
import { formatErrorCode, safeErrorName } from '../utils/safe-log.js';

/**
 * What to do when a message was written but its conversation summary was not.
 *
 * The controller compensates by deleting the orphaned message. This module
 * decides what the caller then reports, and the important case is the one
 * where the compensating delete ALSO fails: at that point a message exists
 * that no conversation summary accounts for, and the response must say so
 * rather than reporting the original, now-misleading cause.
 */

/**
 * Builds the failure log for a compensation that could not complete. Only a
 * fixed event code and two bounded primitives are emitted - never the message
 * body, sender, conversation, or the raw error.
 */
export function messageCompensationLog(error) {
  return [
    '[messaging] MESSAGE_COMPENSATION_FAILED',
    `errorName=${safeErrorName(error)}`,
    `errorCode=${formatErrorCode(error)}`
  ];
}

/**
 * Chooses the error a failed send must surface.
 *
 * - compensation succeeded, and the summary update threw  -> the original cause
 * - compensation succeeded, and the summary was simply gone -> not found
 * - compensation failed -> a distinct 500, because the two documents now
 *   disagree and no other error would convey that
 *
 * A 201 is never reachable from here.
 */
export function resolveSendFailure({ compensated, originalError = null }) {
  if (!compensated) {
    return new AppError(
      'The message could not be stored consistently',
      500,
      'MESSAGE_STATE_INCONSISTENT'
    );
  }

  if (originalError) {
    return originalError;
  }

  return new AppError(
    'Conversation was not found',
    404,
    'CONVERSATION_NOT_FOUND'
  );
}
