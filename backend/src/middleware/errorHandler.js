import mongoose from 'mongoose';

import { AppError } from '../utils/AppError.js';

export function notFoundHandler(req, _res, next) {
  next(new AppError(`Route not found: ${req.method} ${req.originalUrl}`, 404, 'NOT_FOUND'));
}

export function errorHandler(error, _req, res, _next) {
  let normalized = error;

  if (error instanceof mongoose.Error.ValidationError) {
    normalized = new AppError(error.message, 400, 'VALIDATION_ERROR');
  }

  if (error instanceof mongoose.Error.CastError) {
    normalized = new AppError('Invalid resource id', 400, 'INVALID_ID');
  }

  if (error?.code === 11000) {
    normalized = new AppError('A resource with this value already exists', 409, 'DUPLICATE_VALUE');
  }

  const statusCode = normalized.statusCode ?? 500;
  const response = {
    success: false,
    error: {
      code: normalized.code ?? 'INTERNAL_ERROR',
      message: normalized.isOperational ? normalized.message : 'Internal server error'
    }
  };

  if (process.env.NODE_ENV !== 'production') {
    response.error.details = normalized.message;
  }

  res.status(statusCode).json(response);
}
