import { AppError } from '../utils/AppError.js';

/**
 * Where Merzox delivers, and how a saved address is shaped.
 *
 * The regions are server-owned for a reason the design makes explicit: the
 * city picker of `تفاصيل المتجر – 28` marks some governorates «مغلق». Whether
 * a place can be delivered to is an operational fact that changes without an
 * app release, so the list and its closed flags are served rather than
 * shipped, and an address in a closed governorate is refused here rather than
 * accepted and disappointed later.
 */

/** Governorates, each with the towns `تفاصيل المتجر – 27` lists under it. */
const REGIONS = Object.freeze([
  {
    governorate: 'رام الله والبيرة',
    open: true,
    cities: [
      'رام الله',
      'البيرة',
      'بيرزيت',
      'الجلزون',
      'أم الشرايط',
      'بيت سيرا',
      'تل الماصيون',
      'جمالا',
      'بدرس',
      'النبي موسى'
    ]
  },
  { governorate: 'أريحا', open: true, cities: ['أريحا', 'الطيبة'] },
  { governorate: 'سلفيت', open: true, cities: ['سلفيت', 'بديا'] },
  { governorate: 'طولكرم', open: true, cities: ['طولكرم'] },
  { governorate: 'الخليل', open: true, cities: ['الخليل'] },
  { governorate: 'بيت لحم', open: true, cities: ['بيت لحم'] },
  { governorate: 'طوباس', open: true, cities: ['طوباس'] },
  { governorate: 'جنين', open: true, cities: ['جنين'] },
  { governorate: 'قلقيلية', open: true, cities: ['قلقيلية'] },
  // Marked «مغلق» in the artboard: listed so a customer can see the place
  // exists and is not served, rather than wondering why it is missing.
  { governorate: 'الناصرة', open: false, cities: ['الناصرة'] },
  { governorate: 'عكا', open: false, cities: ['عكا'] },
  { governorate: 'الجولان', open: false, cities: ['الجولان'] }
]);

/** How many addresses one account may keep. */
export const MAX_ADDRESSES = 10;

export const ADDRESS_LIMITS = Object.freeze({
  labelMax: 40,
  fullNameMin: 2,
  fullNameMax: 80,
  detailsMax: 250
});

/** Matches the phone rule the User model already enforces. */
const PHONE = /^\+?[0-9]{7,15}$/;

export function deliveryRegions() {
  return REGIONS.map((region) => ({
    governorate: region.governorate,
    open: region.open,
    cities: [...region.cities]
  }));
}

export function findRegion(governorate) {
  const wanted = String(governorate ?? '').trim();

  return REGIONS.find((region) => region.governorate === wanted) ?? null;
}

function text(value) {
  return String(value ?? '').trim();
}

function refuse(message, code) {
  throw new AppError(message, 400, code);
}

/**
 * The exact fields a client may write on an address, validated.
 *
 * Deliberately a whitelist that rebuilds the object rather than a filter over
 * the request: anything the caller invented — an id, an owner, a flag it does
 * not own — cannot survive a rebuild, so no field can be smuggled in by being
 * unlisted.
 */
export function buildAddressWrite(body = {}) {
  const fullName = text(body.fullName);
  if (
    fullName.length < ADDRESS_LIMITS.fullNameMin ||
    fullName.length > ADDRESS_LIMITS.fullNameMax
  ) {
    refuse('Address full name is invalid', 'INVALID_ADDRESS_NAME');
  }

  const phone = text(body.phone);
  if (!PHONE.test(phone)) {
    refuse('Address phone is invalid', 'INVALID_ADDRESS_PHONE');
  }

  // Optional, and held to the same rule as the required one when present: a
  // second number that cannot be dialled is worse than no second number.
  const altPhone = text(body.altPhone);
  if (altPhone && !PHONE.test(altPhone)) {
    refuse('Address alternate phone is invalid', 'INVALID_ADDRESS_PHONE');
  }

  const region = findRegion(body.governorate);
  if (!region) {
    refuse('Governorate is not served', 'INVALID_ADDRESS_GOVERNORATE');
  }
  if (!region.open) {
    refuse('Governorate is not open for delivery', 'ADDRESS_GOVERNORATE_CLOSED');
  }

  const city = text(body.city);
  if (!region.cities.includes(city)) {
    refuse('City does not belong to that governorate', 'INVALID_ADDRESS_CITY');
  }

  const label = text(body.label).slice(0, ADDRESS_LIMITS.labelMax);
  const details = text(body.details);
  if (details.length > ADDRESS_LIMITS.detailsMax) {
    refuse('Address details are too long', 'INVALID_ADDRESS_DETAILS');
  }

  return {
    label,
    fullName,
    phone,
    altPhone,
    governorate: region.governorate,
    city,
    details,
    isDefault: body.isDefault === true
  };
}

/**
 * The one-line form an order's `deliveryAddress` takes.
 *
 * An order snapshots the address as text at purchase time, so editing or
 * deleting a saved address later cannot rewrite where a past order went.
 */
export function formatAddressLine(address) {
  const governorate = text(address.governorate);
  const city = text(address.city);

  return [governorate, city === governorate ? '' : city, text(address.details)]
    .filter(Boolean)
    .join(' ، ');
}

/**
 * Applies the "exactly one default" invariant to a whole list.
 *
 * Called after every write, so the rule holds no matter which path got here:
 * the newest default wins, and if nothing claims the flag the first address
 * takes it, because an address book with no default silently sends a customer
 * back to the form on every checkout.
 */
export function normalizeDefaults(addresses, preferredId = null) {
  if (addresses.length === 0) return addresses;

  const wanted = preferredId ? String(preferredId) : null;
  let chosen = wanted
    ? addresses.find((entry) => String(entry._id) === wanted)
    : null;

  chosen ??= addresses.find((entry) => entry.isDefault) ?? addresses[0];

  for (const entry of addresses) {
    entry.isDefault = entry === chosen;
  }

  return addresses;
}
