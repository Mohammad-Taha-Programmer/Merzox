import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/orders/order_status_policy.dart';

/// The client policy exists only to decide what the merchant UI offers, but it
/// must not drift from the server. This mirrors
/// `backend/test/order.transition-matrix.test.js` pair for pair, so a change on
/// one side without the other fails here.
void main() {
  const expectedTransitions = <String, List<String>>{
    'pending': ['confirmed', 'cancelled'],
    'confirmed': ['preparing', 'cancelled'],
    'preparing': ['outForDelivery', 'cancelled'],
    'outForDelivery': ['delivered'],
    'delivered': <String>[],
    'cancelled': <String>[],
  };

  test('every source/destination pair matches the declared matrix', () {
    var allowed = 0;
    var refused = 0;

    for (final from in OrderStatusPolicy.statuses) {
      for (final to in OrderStatusPolicy.statuses) {
        final shouldAllow = expectedTransitions[from]!.contains(to);
        expect(
          OrderStatusPolicy.canMerchantTransition(from, to),
          shouldAllow,
          reason: '$from -> $to',
        );
        shouldAllow ? allowed++ : refused++;
      }
    }

    expect(allowed + refused, 36);
    expect(allowed, 7);
  });

  test('a status never transitions to itself', () {
    for (final status in OrderStatusPolicy.statuses) {
      expect(
        OrderStatusPolicy.canMerchantTransition(status, status),
        isFalse,
        reason: status,
      );
    }
  });

  test('terminal states offer nothing and cannot be reopened', () {
    for (final terminal in ['delivered', 'cancelled']) {
      expect(OrderStatusPolicy.isTerminal(terminal), isTrue);
      expect(OrderStatusPolicy.merchantTransitionsFrom(terminal), isEmpty);

      for (final to in OrderStatusPolicy.statuses) {
        expect(
          OrderStatusPolicy.canMerchantTransition(terminal, to),
          isFalse,
          reason: '$terminal -> $to',
        );
      }
    }
  });

  test('offered transitions keep the design display order', () {
    expect(OrderStatusPolicy.merchantTransitionsFrom('pending'), [
      'confirmed',
      'cancelled',
    ]);
    expect(OrderStatusPolicy.merchantTransitionsFrom('preparing'), [
      'outForDelivery',
      'cancelled',
    ]);
    expect(OrderStatusPolicy.merchantTransitionsFrom('outForDelivery'), [
      'delivered',
    ]);
  });

  test('no status may be skipped on the way to delivered', () {
    expect(
      OrderStatusPolicy.canMerchantTransition('pending', 'delivered'),
      isFalse,
    );
    expect(
      OrderStatusPolicy.canMerchantTransition('pending', 'outForDelivery'),
      isFalse,
    );
    expect(
      OrderStatusPolicy.canMerchantTransition('confirmed', 'delivered'),
      isFalse,
    );
  });

  test('pending is never offered as a destination', () {
    for (final from in OrderStatusPolicy.statuses) {
      expect(
        OrderStatusPolicy.canMerchantTransition(from, 'pending'),
        isFalse,
        reason: from,
      );
    }
    expect(
      OrderStatusPolicy.merchantSelectableStatuses.contains('pending'),
      isFalse,
    );
  });

  test('an unknown status offers nothing rather than throwing', () {
    for (final bogus in ['shipped', '', 'PENDING', 'delivered ']) {
      expect(OrderStatusPolicy.isStatus(bogus), isFalse, reason: bogus);
      expect(
        OrderStatusPolicy.merchantTransitionsFrom(bogus),
        isEmpty,
        reason: bogus,
      );
    }
  });

  test('status groups match the server mapping', () {
    const expected = {
      'pending': 'current',
      'confirmed': 'current',
      'preparing': 'current',
      'outForDelivery': 'current',
      'delivered': 'completed',
      'cancelled': 'cancelled',
    };

    for (final status in OrderStatusPolicy.statuses) {
      expect(
        OrderStatusPolicy.groupFor(status),
        expected[status],
        reason: status,
      );
    }
  });

  test('courier assignment matches the server window', () {
    const expected = {
      'pending': false,
      'confirmed': true,
      'preparing': true,
      'outForDelivery': true,
      'delivered': false,
      'cancelled': false,
    };

    for (final status in OrderStatusPolicy.statuses) {
      expect(
        OrderStatusPolicy.canAssignCourier(status),
        expected[status],
        reason: status,
      );
    }
  });
}
