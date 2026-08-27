/**
 * Provider-neutral payment capability truth.
 *
 * `paymentMethods` is the stable API / historical vocabulary. Keeping a method
 * in this list does NOT mean Merzox can process it today.
 *
 * `operationalPaymentMethods` is intentionally narrower. A method may enter
 * this set only when its real processing lifecycle is implemented and reviewed.
 *
 * GAP-020A deliberately enables cash only. No gateway, card SDK, merchant
 * credential, webhook, capture, refund, or external payment call is introduced
 * here.
 */
export const paymentMethods = Object.freeze([
  'cash',
  'card',
  'bankTransfer',
  'assisted'
]);

export const operationalPaymentMethods = Object.freeze([
  'cash'
]);

export const PAYMENT_ERRORS = Object.freeze({
  unavailable: 'PAYMENT_METHOD_UNAVAILABLE'
});

const knownPaymentMethodSet = new Set(paymentMethods);
const operationalPaymentMethodSet = new Set(
  operationalPaymentMethods
);

/**
 * Recognized contract vocabulary.
 *
 * No trimming/coercion is performed. The request validator owns input syntax,
 * so malformed values such as an empty string or " cash " remain invalid.
 */
export function isKnownPaymentMethod(paymentMethod) {
  return (
    typeof paymentMethod === 'string' &&
    knownPaymentMethodSet.has(paymentMethod)
  );
}

/**
 * True only when Merzox can actually complete this payment mode today.
 */
export function isOperationalPaymentMethod(paymentMethod) {
  return (
    typeof paymentMethod === 'string' &&
    operationalPaymentMethodSet.has(paymentMethod)
  );
}
