/**
 * The single authoritative order status policy.
 *
 * Before this module the merchant transition map, the customer cancellation
 * set, the address-mutable set, and the statusGroup mapping each existed in
 * more than one file, which meant a rule could be tightened in one place and
 * silently left open in another. Every caller - controllers, validators, and
 * the Order model's tracking projection - now reads from here.
 */

/** Every status the Order schema can persist. */
export const orderStatuses = [
  'pending',
  'confirmed',
  'preparing',
  'outForDelivery',
  'delivered',
  'cancelled'
];

export const orderStatusGroups = ['current', 'completed', 'cancelled'];

/** Statuses from which no further transition is possible. */
export const terminalOrderStatuses = ['delivered', 'cancelled'];

/**
 * Merchant-driven transitions. `pending` is the arrival state and is never a
 * target; the terminal states map to nothing, so a delivered or cancelled
 * order can never be reopened.
 */
const ownerTransitions = new Map([
  ['pending', new Set(['confirmed', 'cancelled'])],
  ['confirmed', new Set(['preparing', 'cancelled'])],
  ['preparing', new Set(['outForDelivery', 'cancelled'])],
  ['outForDelivery', new Set(['delivered'])],
  ['delivered', new Set()],
  ['cancelled', new Set()]
]);

/** Statuses a merchant is allowed to move an order to. */
export const merchantSelectableStatuses = [
  'confirmed',
  'preparing',
  'outForDelivery',
  'delivered',
  'cancelled'
];

/**
 * Customer-driven cancellation. `preparing` is intentionally included: it
 * matches the tracking screen's cancel affordance and the behaviour that was
 * already approved, so it is preserved rather than quietly narrowed here.
 */
export const customerCancellableStatuses = ['pending', 'confirmed', 'preparing'];

/**
 * The delivery address may only change before the merchant starts preparing -
 * after that the parcel is being assembled against the recorded address.
 */
export const addressMutableStatuses = ['pending', 'confirmed'];

/** A courier is meaningful only once the order is accepted and not yet closed. */
export const courierAssignableStatuses = [
  'confirmed',
  'preparing',
  'outForDelivery'
];

export function canTransitionOwnerOrder(from, to) {
  return ownerTransitions.get(from)?.has(to) ?? false;
}

export function allowedOwnerTransitions(from) {
  return [...(ownerTransitions.get(from) ?? [])];
}

export function isTerminalOrderStatus(status) {
  return terminalOrderStatuses.includes(status);
}

export function statusGroupFor(status) {
  if (status === 'delivered') return 'completed';
  if (status === 'cancelled') return 'cancelled';
  return 'current';
}

export function canCustomerCancel(status) {
  return customerCancellableStatuses.includes(status);
}

export function canChangeDeliveryAddress(status) {
  return addressMutableStatuses.includes(status);
}

export function canAssignCourier(status) {
  return courierAssignableStatuses.includes(status);
}

export function canReviewOrder(status) {
  return status === 'delivered';
}
