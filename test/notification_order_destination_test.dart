import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/notifications/notification_destination.dart';
import 'package:merzox/services/api_service.dart';

/// Where tapping a notification takes the reader.
///
/// Every order notification went to the customer's tracking screen, whoever
/// was reading it. That screen looks the order up among the reader's own
/// purchases, and a merchant has none - so a merchant tapping "you have a new
/// order" was told their own shop's order did not exist, while it sat in their
/// order list the whole time. It was being asked for from the wrong side.

const String _orderId = '64d000000000000000000201';

AppNotificationApiModel _notification({
  required String type,
  Map<String, dynamic> data = const <String, dynamic>{'orderId': _orderId},
  String title = 'طلب جديد',
}) => AppNotificationApiModel(
  id: 'n1',
  type: type,
  title: title,
  body: 'يوجد لديك طلب جديد رقم 222321',
  data: data,
  isRead: false,
  createdAt: DateTime(2026, 9, 5),
);

/// The three an order can raise.
const List<String> _orderTypes = <String>[
  'orderPlaced',
  'orderStatus',
  'orderCancelled',
];

void main() {
  group('an order notification', () {
    test('takes a merchant to their own order screen', () {
      for (final String type in _orderTypes) {
        expect(
          notificationDestination(
            _notification(type: type),
            businessAudience: true,
          ),
          '/business/orders/$_orderId',
          reason: '$type sends the merchant to the wrong side',
        );
      }
    });

    test('takes a customer to tracking', () {
      for (final String type in _orderTypes) {
        // The fix must not cost the customer the screen that was right for
        // them: they are tracking a purchase, not managing a sale.
        expect(
          notificationDestination(
            _notification(type: type),
            businessAudience: false,
          ),
          '/orders/$_orderId/tracking',
          reason: type,
        );
      }
    });

    test('the two sides never share a destination', () {
      for (final String type in _orderTypes) {
        final String? merchant = notificationDestination(
          _notification(type: type),
          businessAudience: true,
        );
        final String? customer = notificationDestination(
          _notification(type: type),
          businessAudience: false,
        );

        expect(merchant, isNot(customer), reason: type);
      }
    });

    test('one carrying no order id goes nowhere', () {
      // Better to stay put than to open a screen for an order nobody named.
      for (final String type in _orderTypes) {
        expect(
          notificationDestination(
            _notification(type: type, data: const <String, dynamic>{}),
            businessAudience: true,
          ),
          isNull,
          reason: type,
        );
      }
    });
  });

  group('the other notifications', () {
    test('a message opens its own conversation, whoever is reading', () {
      for (final bool merchant in <bool>[true, false]) {
        final String? destination = notificationDestination(
          _notification(
            type: 'newMessage',
            title: 'ياسمين خالد',
            data: const <String, dynamic>{'conversationId': 'c1'},
          ),
          businessAudience: merchant,
        );

        expect(destination, startsWith('/chat?'));
        expect(destination, contains('conversationId=c1'));
      }
    });

    test('a message with no conversation goes nowhere', () {
      expect(
        notificationDestination(
          _notification(type: 'newMessage', data: const <String, dynamic>{}),
          businessAudience: false,
        ),
        isNull,
      );
    });

    test('a kind nothing routes is read where it is', () {
      expect(
        notificationDestination(
          _notification(type: 'somethingAddedLater'),
          businessAudience: true,
        ),
        isNull,
      );
    });
  });
}
