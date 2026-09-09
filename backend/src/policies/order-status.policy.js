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
 *
 * Status is only half the rule - see [ORDER_CANCELLATION_WINDOW_MS]. Read this
 * list on its own and an order placed a week ago still looks cancellable.
 */
export const customerCancellableStatuses = ['pending', 'confirmed', 'preparing'];

/**
 * How long after it was placed a customer may still call an order off.
 *
 * The checkout screen has promised this window to every customer who ever
 * ordered, while the server enforced status alone - so an order could be
 * refused an hour after it was placed, against a written promise of a day.
 * The promise is the rule now.
 */
export const ORDER_CANCELLATION_WINDOW_MS = 24 * 60 * 60 * 1000;

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

/**
 * Why this customer may not call this order off, or `null` if they may.
 *
 * It answers with a code rather than a boolean so the refusal can say which
 * of the two gates closed - a reader told only "no" reasonably concludes the
 * app is broken, especially when the button was offered to them.
 *
 * It takes the order rather than its status because the rule needs both
 * halves. A `canCustomerCancel(status)` that read the status alone was exactly
 * how the window could be added to one caller and silently left out of the
 * next, which is the failure this whole module exists to prevent.
 */
export function customerCancellationRefusal({ status, createdAt }, now = Date.now()) {
  if (status === 'outForDelivery') return 'ORDER_ALREADY_DISPATCHED';
  if (!customerCancellableStatuses.includes(status)) return 'ORDER_NOT_CANCELLABLE';

  // An order that has not been saved has no timestamp yet, and no elapsed time
  // either - nothing about it is outside the window.
  const placedAt =
    createdAt instanceof Date ? createdAt.getTime() : Date.parse(createdAt ?? '');

  if (Number.isFinite(placedAt) && now - placedAt >= ORDER_CANCELLATION_WINDOW_MS) {
    return 'ORDER_CANCELLATION_WINDOW_CLOSED';
  }

  return null;
}

export function canCustomerCancel(order, now = Date.now()) {
  return customerCancellationRefusal(order, now) === null;
}

/**
 * The earliest an order can have been placed and still be cancellable now.
 *
 * Handed to a query so the window is enforced in the same atomic write that
 * checks the status, rather than being read and then acted on.
 */
export function earliestCancellableOrderDate(now = Date.now()) {
  return new Date(now - ORDER_CANCELLATION_WINDOW_MS);
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
