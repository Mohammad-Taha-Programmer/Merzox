/// The client-side mirror of `backend/src/policies/order-status.policy.js`.
///
/// The merchant transition map previously existed twice in the Flutter layer
/// (the shell list tile and the order detail screen) and a third time on the
/// server. This is the single client copy; it exists only to decide what to
/// offer in the UI. The backend remains the authority and re-validates every
/// transition, so a stale client can never widen what is actually permitted.
final class OrderStatusPolicy {
  const OrderStatusPolicy._();

  /// Every status the server can persist.
  static const List<String> statuses = [
    'pending',
    'confirmed',
    'preparing',
    'outForDelivery',
    'delivered',
    'cancelled',
  ];

  /// Statuses a merchant may move an order to, in the order the design lists
  /// them. `pending` is the arrival state and is never a target.
  static const List<String> merchantSelectableStatuses = [
    'confirmed',
    'preparing',
    'outForDelivery',
    'delivered',
    'cancelled',
  ];

  static const Map<String, Set<String>> _merchantTransitions = {
    'pending': {'confirmed', 'cancelled'},
    'confirmed': {'preparing', 'cancelled'},
    'preparing': {'outForDelivery', 'cancelled'},
    'outForDelivery': {'delivered'},
    'delivered': <String>{},
    'cancelled': <String>{},
  };

  static const List<String> _terminal = ['delivered', 'cancelled'];

  static bool isStatus(String status) => statuses.contains(status);

  static bool isTerminal(String status) => _terminal.contains(status);

  static bool canMerchantTransition(String from, String to) =>
      _merchantTransitions[from]?.contains(to) ?? false;

  /// The transitions to offer for [from], kept in the design's display order.
  static List<String> merchantTransitionsFrom(String from) {
    final allowed = _merchantTransitions[from] ?? const <String>{};
    return merchantSelectableStatuses
        .where(allowed.contains)
        .toList(growable: false);
  }

  static String groupFor(String status) {
    if (status == 'delivered') return 'completed';
    if (status == 'cancelled') return 'cancelled';
    return 'current';
  }

  static bool canAssignCourier(String status) =>
      const ['confirmed', 'preparing', 'outForDelivery'].contains(status);
}
