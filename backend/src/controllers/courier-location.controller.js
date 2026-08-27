import mongoose from 'mongoose';

import { Order } from '../models/Order.js';
import {
  COURIER_LOCATION_ERRORS,
  courierLocationMonotonicFilter,
  courierLocationTokenFromAuthorization,
  hashCourierLocationToken
} from '../policies/courier-location.policy.js';
import {
  publishOrderTrackingChanged
} from '../realtime/realtime.publisher.js';
import { AppError } from '../utils/AppError.js';
import { asyncHandler } from '../utils/asyncHandler.js';

function invalidCapability() {
  return new AppError(
    'Courier location capability is invalid or inactive',
    401,
    COURIER_LOCATION_ERRORS.capabilityInvalid
  );
}

/**
 * Capability-authenticated courier write.
 *
 * The raw secret never enters MongoDB. The route hashes the credential and
 * atomically requires the order to still be out for delivery, unrevoked and
 * unexpired before replacing the single latest location snapshot.
 */
export const updateCourierLocationByCapability =
  asyncHandler(async (req, res) => {
    const authorization =
      req.get('authorization');

    if (!authorization) {
      throw new AppError(
        'Courier location capability is required',
        401,
        COURIER_LOCATION_ERRORS.authRequired
      );
    }

    const token =
      courierLocationTokenFromAuthorization(
        authorization
      );

    const tokenHash =
      token
        ? hashCourierLocationToken(token)
        : null;

    if (
      !tokenHash ||
      !mongoose.isValidObjectId(req.params.id)
    ) {
      throw invalidCapability();
    }

    const location =
      req.courierLocationPayload;

    if (!location) {
      throw new AppError(
        'Courier location payload is invalid',
        400,
        COURIER_LOCATION_ERRORS.invalidFields
      );
    }

    const receivedAt = new Date();

    const order =
      await Order.findOneAndUpdate(
        {
          _id: req.params.id,
          status: 'outForDelivery',
          'courierLocationCapability.tokenHash':
            tokenHash,
          'courierLocationCapability.revokedAt':
            null,
          'courierLocationCapability.expiresAt':
            { $gt: receivedAt },
          ...courierLocationMonotonicFilter(
            location.capturedAt
          )
        },
        {
          $set: {
            courierLocation: {
              latitude: location.latitude,
              longitude: location.longitude,
              accuracy: location.accuracy,
              capturedAt: location.capturedAt,
              receivedAt
            }
          }
        },
        {
          new: true,
          runValidators: true
        }
      );

    if (!order) {
      const activeCapability =
        await Order.exists({
          _id: req.params.id,
          status: 'outForDelivery',
          'courierLocationCapability.tokenHash':
            tokenHash,
          'courierLocationCapability.revokedAt':
            null,
          'courierLocationCapability.expiresAt':
            { $gt: receivedAt }
        });

      if (activeCapability) {
        throw new AppError(
          'Courier location sample is not newer than the stored location',
          409,
          COURIER_LOCATION_ERRORS.staleSample
        );
      }

      throw invalidCapability();
    }

    publishOrderTrackingChanged({
      recipientIds: [order.user],
      orderId: order._id,
      reason: 'courier-location-updated'
    });

    res.json({
      success: true,
      data: {
        accepted: true,
        receivedAt:
          order.courierLocation?.receivedAt ??
          receivedAt
      }
    });
  });
