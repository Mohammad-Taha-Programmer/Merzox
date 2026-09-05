import 'package:merzox/services/api_service.dart';

/// Where tapping a notification takes the reader.
///
/// This was a `switch` buried in the page's tap handler, and it sent every
/// order notification to the customer's tracking screen whoever was reading
/// it. That screen looks an order up among the reader's own purchases, and a
/// merchant has none - so a merchant tapping "you have a new order" was told
/// their own shop's order did not exist, while it sat in their order list the
/// whole time. It was being asked for from the wrong side.
///
/// Pulled out here because the destination is a decision, not a side effect,
/// and a decision can be stated and checked. Returns null when a notification
/// has nowhere to go, which is not a failure: some are read where they are.
String? notificationDestination(
  AppNotificationApiModel notification, {
  required bool businessAudience,
}) {
  switch (notification.type) {
    case 'newMessage':
      if (notification.conversationId.isEmpty) return null;

      return Uri(
        path: '/chat',
        queryParameters: <String, String>{
          'conversationId': notification.conversationId,
          'title': notification.title,
        },
      ).toString();

    case 'orderPlaced':
    case 'orderStatus':
    case 'orderCancelled':
      if (notification.orderId.isEmpty) return null;

      // The same order has two screens, and which one a reader wants depends
      // on which side of it they are on.
      return businessAudience
          ? '/business/orders/${notification.orderId}'
          : '/orders/${notification.orderId}/tracking';

    default:
      return null;
  }
}
