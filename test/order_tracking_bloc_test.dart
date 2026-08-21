import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:merzox/features/notifications/bloc/notifications_bloc.dart';
import 'package:merzox/features/notifications/bloc/notifications_event.dart';
import 'package:merzox/features/notifications/bloc/notifications_state.dart';
import 'package:merzox/features/orders/bloc/order_tracking_bloc.dart';
import 'package:merzox/features/orders/bloc/order_tracking_event.dart';
import 'package:merzox/features/orders/bloc/order_tracking_state.dart';
import 'package:merzox/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

OrderApiModel _order({
  String status = 'preparing',
  String deliveryAddress = 'أريحا ، النبي موسى',
  OrderCourierApiModel courier = const OrderCourierApiModel(
    name: '',
    phone: '',
    assignedAt: null,
  ),
}) {
  return OrderApiModel(
    id: 'o1',
    publicId: 'MX-TEST-0001',
    business: const OrderBusinessApiModel(
      id: 'b1',
      name: 'متجر الياسمين',
      address: 'رام الله',
    ),
    items: const [
      OrderItemApiModel(
        productId: 'p1',
        name: 'أساس فت مي',
        imageUrl: '',
        unitPrice: 35,
        quantity: 1,
        variant: '',
      ),
    ],
    subtotal: 35,
    deliveryFee: 10,
    total: 45,
    currency: 'ILS',
    deliveryAddress: deliveryAddress,
    paymentMethod: 'cash',
    status: status,
    statusGroup: status == 'delivered'
        ? 'completed'
        : status == 'cancelled'
        ? 'cancelled'
        : 'current',
    statusHistory: const [],
    cancellationReason: '',
    createdAt: DateTime.utc(2026, 2, 15, 14, 40),
    courier: courier,
    tracking: OrderTrackingApiModel.fromStatus(status),
  );
}

AppNotificationApiModel _notification({
  String id = 'n1',
  bool isRead = false,
  String type = 'orderStatus',
}) {
  return AppNotificationApiModel(
    id: id,
    type: type,
    title: 'يتم تحضير طلبك',
    body: 'طلبك رقم MX-TEST-0001',
    data: const {'orderId': 'o1'},
    isRead: isRead,
    createdAt: DateTime.utc(2026, 2, 16, 9),
  );
}

class _FakeTrackingApi extends ApiService {
  OrderApiModel current;
  final List<String> addressUpdates = [];
  final List<String> cancellations = [];
  final List<int> submittedRatings = [];
  Object? addressError;

  _FakeTrackingApi(this.current);

  @override
  Future<OrderApiModel> order({
    required String token,
    required String orderId,
  }) async => current;

  @override
  Future<OrderApiModel> updateOrderAddress({
    required String token,
    required String orderId,
    required String deliveryAddress,
  }) async {
    if (addressError != null) throw addressError!;
    addressUpdates.add(deliveryAddress);
    current = _order(deliveryAddress: deliveryAddress);
    return current;
  }

  @override
  Future<OrderApiModel> cancelOrder({
    required String token,
    required String orderId,
    String reason = '',
  }) async {
    cancellations.add(reason);
    current = _order(status: 'cancelled');
    return current;
  }

  @override
  Future<BusinessReviewApiModel> submitBusinessReview({
    required String token,
    required String businessId,
    required int rating,
    required String comment,
  }) async {
    submittedRatings.add(rating);
    return BusinessReviewApiModel(
      id: 'r1',
      userName: 'ياسمين خالد',
      rating: rating.toDouble(),
      comment: comment,
      createdAt: DateTime.utc(2026, 2, 18),
    );
  }
}

class _FakeNotificationsApi extends ApiService {
  final List<bool> audienceFlags = [];
  final List<String> readIds = [];
  int allReadCalls = 0;
  List<AppNotificationApiModel> items = const [];
  int unread = 0;

  @override
  Future<NotificationListApiResponse> notifications({
    required String token,
    bool businessAudience = false,
    bool unreadOnly = false,
    int page = 1,
    int limit = 20,
  }) async {
    audienceFlags.add(businessAudience);
    return NotificationListApiResponse(
      notifications: items,
      unreadCount: unread,
      page: page,
      hasMore: false,
    );
  }

  @override
  Future<void> markNotificationRead({
    required String token,
    required String notificationId,
  }) async {
    readIds.add(notificationId);
  }

  @override
  Future<void> markAllNotificationsRead({
    required String token,
    bool businessAudience = false,
  }) async {
    allReadCalls += 1;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({AuthBloc.tokenKey: 'test-token'});
  });

  test('tracking loads the order and its derived timeline', () async {
    final bloc = OrderTrackingBloc(
      orderId: 'o1',
      apiService: _FakeTrackingApi(_order()),
    );

    bloc.add(const OrderTrackingStarted());
    await bloc.stream.firstWhere(
      (state) => state.status == OrderTrackingStatus.ready,
    );

    expect(bloc.state.tracking!.currentStep, 'preparing');
    expect(bloc.state.tracking!.currentIndex, 1);
    expect(bloc.state.tracking!.canCancel, isTrue);
    // Preparation has started, so the address is locked.
    expect(bloc.state.tracking!.canChangeAddress, isFalse);

    await bloc.close();
  });

  test('a delivered order offers a review and hides cancellation', () async {
    final bloc = OrderTrackingBloc(
      orderId: 'o1',
      apiService: _FakeTrackingApi(_order(status: 'delivered')),
    );

    bloc.add(const OrderTrackingStarted());
    await bloc.stream.firstWhere(
      (state) => state.status == OrderTrackingStatus.ready,
    );

    expect(bloc.state.tracking!.canReview, isTrue);
    expect(bloc.state.tracking!.canCancel, isFalse);

    await bloc.close();
  });

  test(
    'a courier assigned by the merchant reaches the tracking state',
    () async {
      final bloc = OrderTrackingBloc(
        orderId: 'o1',
        apiService: _FakeTrackingApi(
          _order(
            status: 'outForDelivery',
            courier: OrderCourierApiModel(
              name: 'Hamode Hussen',
              phone: '0592029316',
              assignedAt: DateTime.utc(2026, 2, 18),
            ),
          ),
        ),
      );

      bloc.add(const OrderTrackingStarted());
      await bloc.stream.firstWhere(
        (state) => state.status == OrderTrackingStatus.ready,
      );

      expect(bloc.state.order!.courier.isAssigned, isTrue);
      expect(bloc.state.order!.courier.name, 'Hamode Hussen');

      await bloc.close();
    },
  );

  test('changing the address sends the trimmed value', () async {
    final api = _FakeTrackingApi(_order(status: 'pending'));
    final bloc = OrderTrackingBloc(orderId: 'o1', apiService: api);

    bloc.add(const OrderTrackingStarted());
    await bloc.stream.firstWhere(
      (state) => state.status == OrderTrackingStatus.ready,
    );

    bloc.add(const OrderTrackingAddressChanged('  رام الله ، دوار المنارة  '));
    await bloc.stream.firstWhere(
      (state) => state.messageCode == 'tracking.addressUpdated',
    );

    expect(api.addressUpdates, ['رام الله ، دوار المنارة']);

    await bloc.close();
  });

  test('a too-short address is rejected before any request', () async {
    final api = _FakeTrackingApi(_order(status: 'pending'));
    final bloc = OrderTrackingBloc(orderId: 'o1', apiService: api);

    bloc.add(const OrderTrackingStarted());
    await bloc.stream.firstWhere(
      (state) => state.status == OrderTrackingStatus.ready,
    );

    bloc.add(const OrderTrackingAddressChanged('رام'));
    await bloc.stream.firstWhere((state) => state.errorMessage.isNotEmpty);

    expect(api.addressUpdates, isEmpty);
    expect(bloc.state.errorMessage, 'tracking.addressTooShort');

    await bloc.close();
  });

  test('cancelling moves the order onto the cancelled timeline', () async {
    final api = _FakeTrackingApi(_order(status: 'pending'));
    final bloc = OrderTrackingBloc(orderId: 'o1', apiService: api);

    bloc.add(const OrderTrackingStarted());
    await bloc.stream.firstWhere(
      (state) => state.status == OrderTrackingStatus.ready,
    );

    bloc.add(const OrderTrackingCancelRequested(reason: 'تأخر التوصيل'));
    await bloc.stream.firstWhere(
      (state) => state.messageCode == 'orders.cancelSuccess',
    );

    expect(api.cancellations, ['تأخر التوصيل']);
    expect(bloc.state.tracking!.isCancelled, isTrue);
    expect(bloc.state.tracking!.currentIndex, -1);

    await bloc.close();
  });

  test('a submitted review is recorded once', () async {
    final api = _FakeTrackingApi(_order(status: 'delivered'));
    final bloc = OrderTrackingBloc(orderId: 'o1', apiService: api);

    bloc.add(const OrderTrackingStarted());
    await bloc.stream.firstWhere(
      (state) => state.status == OrderTrackingStatus.ready,
    );

    bloc.add(
      const OrderTrackingReviewSubmitted(rating: 5, comment: 'خدمة ممتازة'),
    );
    await bloc.stream.firstWhere((state) => state.reviewSubmitted);

    expect(api.submittedRatings, [5]);

    await bloc.close();
  });

  test('the merchant feed asks for the business audience', () async {
    final api = _FakeNotificationsApi()
      ..items = [_notification()]
      ..unread = 1;
    final bloc = NotificationsBloc(apiService: api, businessAudience: true);

    bloc.add(const NotificationsStarted());
    await bloc.stream.firstWhere(
      (state) => state.status == NotificationsStatus.ready,
    );

    expect(api.audienceFlags, [true]);
    expect(bloc.state.unreadCount, 1);

    await bloc.close();
  });

  test('marking one notification read updates the row and the count', () async {
    final api = _FakeNotificationsApi()
      ..items = [_notification(id: 'n1'), _notification(id: 'n2')]
      ..unread = 2;
    final bloc = NotificationsBloc(apiService: api);

    bloc.add(const NotificationsStarted());
    await bloc.stream.firstWhere(
      (state) => state.status == NotificationsStatus.ready,
    );

    bloc.add(const NotificationMarkedRead('n1'));
    await bloc.stream.firstWhere((state) => state.notifications.first.isRead);

    expect(bloc.state.unreadCount, 1);
    expect(bloc.state.notifications.last.isRead, isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(api.readIds, ['n1']);

    await bloc.close();
  });

  test('an already-read notification is not re-sent', () async {
    final api = _FakeNotificationsApi()
      ..items = [_notification(id: 'n1', isRead: true)]
      ..unread = 0;
    final bloc = NotificationsBloc(apiService: api);

    bloc.add(const NotificationsStarted());
    await bloc.stream.firstWhere(
      (state) => state.status == NotificationsStatus.ready,
    );

    bloc.add(const NotificationMarkedRead('n1'));
    await Future<void>.delayed(Duration.zero);

    expect(api.readIds, isEmpty);

    await bloc.close();
  });

  test('marking all read clears every row', () async {
    final api = _FakeNotificationsApi()
      ..items = [_notification(id: 'n1'), _notification(id: 'n2')]
      ..unread = 2;
    final bloc = NotificationsBloc(apiService: api);

    bloc.add(const NotificationsStarted());
    await bloc.stream.firstWhere(
      (state) => state.status == NotificationsStatus.ready,
    );

    bloc.add(const NotificationsAllMarkedRead());
    await bloc.stream.firstWhere((state) => state.unreadCount == 0);

    expect(
      bloc.state.notifications.every((notification) => notification.isRead),
      isTrue,
    );
    await Future<void>.delayed(Duration.zero);
    expect(api.allReadCalls, 1);

    await bloc.close();
  });
}
