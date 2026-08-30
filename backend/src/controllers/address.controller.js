import mongoose from 'mongoose';

import { User } from '../models/User.js';
import { AppError } from '../utils/AppError.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import {
  MAX_ADDRESSES,
  buildAddressWrite,
  deliveryRegions,
  normalizeDefaults
} from '../policies/address.policy.js';

/**
 * The customer's address book.
 *
 * Every handler below reaches its data through `req.user._id` and never
 * through an id in the path: the address id selects *within* the caller's own
 * subdocument array, so there is no request shape in which one account can
 * name another account's address.
 */

function addressesOf(user) {
  return user.addresses.map((entry) => ({
    id: entry._id.toString(),
    label: entry.label,
    fullName: entry.fullName,
    phone: entry.phone,
    altPhone: entry.altPhone,
    governorate: entry.governorate,
    city: entry.city,
    details: entry.details,
    isDefault: entry.isDefault
  }));
}

function respond(res, user, status = 200) {
  return res.status(status).json({
    success: true,
    data: { addresses: addressesOf(user) }
  });
}

async function loadOwner(req) {
  const user = await User.findById(req.user._id);
  if (!user) throw new AppError('User was not found', 404, 'USER_NOT_FOUND');

  return user;
}

function ownedAddress(user, addressId) {
  if (!mongoose.isValidObjectId(addressId)) {
    throw new AppError('Address id is invalid', 400, 'INVALID_ADDRESS_ID');
  }

  const address = user.addresses.id(addressId);
  // Not found and not yours are the same answer on purpose: a different one
  // would let a caller learn which ids exist on other accounts.
  if (!address) {
    throw new AppError('Address was not found', 404, 'ADDRESS_NOT_FOUND');
  }

  return address;
}

/** Where delivery is available, and which governorates are closed. */
export const listDeliveryRegions = asyncHandler(async (_req, res) => {
  res.json({ success: true, data: { regions: deliveryRegions() } });
});

export const listMyAddresses = asyncHandler(async (req, res) => {
  const user = await loadOwner(req);

  return respond(res, user);
});

export const createMyAddress = asyncHandler(async (req, res) => {
  const user = await loadOwner(req);

  if (user.addresses.length >= MAX_ADDRESSES) {
    throw new AppError(
      `An account may keep at most ${MAX_ADDRESSES} addresses`,
      409,
      'ADDRESS_LIMIT_REACHED'
    );
  }

  const write = buildAddressWrite(req.body);
  const created = user.addresses.create(write);
  user.addresses.push(created);

  // The first address is the default whether or not it asked to be, because a
  // book with no default sends the customer back to the form every checkout.
  normalizeDefaults(
    user.addresses,
    write.isDefault || user.addresses.length === 1 ? created._id : null
  );
  await user.save();

  return respond(res, user, 201);
});

export const updateMyAddress = asyncHandler(async (req, res) => {
  const user = await loadOwner(req);
  const address = ownedAddress(user, req.params.addressId);

  const write = buildAddressWrite(req.body);
  for (const [field, value] of Object.entries(write)) {
    if (field === 'isDefault') continue;
    address[field] = value;
  }

  normalizeDefaults(user.addresses, write.isDefault ? address._id : null);
  await user.save();

  return respond(res, user);
});

/** Promotes one address without touching anything else about it. */
export const setMyDefaultAddress = asyncHandler(async (req, res) => {
  const user = await loadOwner(req);
  const address = ownedAddress(user, req.params.addressId);

  normalizeDefaults(user.addresses, address._id);
  await user.save();

  return respond(res, user);
});

export const deleteMyAddress = asyncHandler(async (req, res) => {
  const user = await loadOwner(req);
  const address = ownedAddress(user, req.params.addressId);

  address.deleteOne();
  // Deleting the default promotes another one rather than leaving the book
  // without a default.
  normalizeDefaults(user.addresses);
  await user.save();

  return respond(res, user);
});
