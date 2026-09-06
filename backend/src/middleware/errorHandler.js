import mongoose from 'mongoose';

import {
  logger
} from '../observability/logger.js';
import {
  safeErrorCode,
  safeErrorName
} from '../utils/safe-log.js';
import { AppError } from '../utils/AppError.js';

export function notFoundHandler(
  req,
  _res,
  next
) {
  next(
    new AppError(
      `Route not found: ${req.method} ${req.originalUrl}`,
      404,
      'NOT_FOUND'
    )
  );
}

export function errorLogFields({
  error,
  normalized,
  requestId,
  statusCode
}) {
  return {
    requestId,
    statusCode,
    appCode:
      normalized?.code ??
      'INTERNAL_ERROR',
    errorName:
      safeErrorName(error),
    errorCode:
      safeErrorCode(error)
  };
}

export function errorHandler(
  error,
  req,
  res,
  _next
) {
  let normalized =
    error;

  if (
    error instanceof
    mongoose.Error.ValidationError
  ) {
    normalized =
      new AppError(
        error.message,
        400,
        'VALIDATION_ERROR'
      );
  }

  if (
    error instanceof
    mongoose.Error.CastError
  ) {
    normalized =
      new AppError(
        'Invalid resource id',
        400,
        'INVALID_ID'
      );
  }

  // body-parser refuses an oversized body before any route sees it. Left
  // unnamed it reaches the reader as "an unexpected error", which is both
  // wrong and unactionable - the one thing they could do about it is send a
  // smaller picture.
  if (
    error?.type ===
      'entity.too.large' ||
    error?.statusCode ===
      413
  ) {
    normalized =
      new AppError(
        'That upload is too large',
        413,
        'PAYLOAD_TOO_LARGE'
      );
  }

  if (error?.code === 11000) {
    normalized =
      new AppError(
        'A resource with this value already exists',
        409,
        'DUPLICATE_VALUE'
      );
  }

  const statusCode =
    normalized.statusCode ??
    500;

  const logFields =
    errorLogFields({
      error,
      normalized,
      requestId:
        req.requestId,
      statusCode
    });

  if (statusCode >= 500) {
    logger.error(
      'http_request_error',
      logFields
    );
  } else {
    logger.warn(
      'http_request_error',
      logFields
    );
  }

  const response = {
    success: false,
    error: {
      code:
        normalized.code ??
        'INTERNAL_ERROR',
      message:
        normalized.isOperational
          ? normalized.message
          : 'Internal server error'
    }
  };

  if (
    process.env.NODE_ENV !==
    'production'
  ) {
    response.error.details =
      normalized.message;
  }

  res
    .status(statusCode)
    .json(response);
}
