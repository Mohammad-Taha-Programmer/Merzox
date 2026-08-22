import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/notifications/bloc/notifications_bloc.dart';
import 'package:merzox/features/notifications/bloc/notifications_event.dart';
import 'package:merzox/features/notifications/bloc/notifications_state.dart';
import 'package:merzox/features/orders/bloc/order_tracking_bloc.dart';
import 'package:merzox/features/orders/bloc/order_tracking_event.dart';
import 'package:merzox/features/orders/bloc/order_tracking_state.dart';
import 'package:merzox/services/api_service.dart';
import 'auth_session_fixtures.dart';

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
    tracking: OrderTrackingApiModel.fromJson(serverTracking(status)),
  );
}

/// Builds the tracking object exactly as the backend emits it.
///
/// This lives in the tests on purpose: production must never derive these
/// values, so the only place a status maps to permissions is a stand-in for
/// the server.
Map<String, dynamic> serverTracking(
  String status, {
  bool? canCancel,
  bool? canChangeAddress,
  bool? canReview,
}) {
  const stepForStatus = {
    'pending': 'placed',
    'confirmed': 'placed',
    'preparing': 'preparing',
    'outForDelivery': 'outForDelivery',
    'delivered': 'delivered',
  };
  const order = ['placed', 'preparing', 'outForDelivery', 'delivered'];

  final isCancelled = status == 'cancelled';
  final currentStep = stepForStatus[status] ?? 'placed';
  final currentIndex = isCancelled ? -1 : order.indexOf(currentStep);

  return {
    'isCancelled': isCancelled,
    'currentStep': isCancelled ? '' : currentStep,
    'currentIndex': currentIndex,
    'steps': [
      for (var i = 0; i < order.length; i++)
        {
          'step': order[i],
          'reachedAt': null,
          'isReached': !isCancelled && i <= currentIndex,
        },
    ],
    'courier': const {'name': '', 'phone': '', 'assignedAt': null},
    'canCancel':
        canCancel ??
        const ['pending', 'confirmed', 'preparing'].contains(status),
    'canChangeAddress':
        canChangeAddress ?? const ['pending', 'confirmed'].contains(status),
    'canReview': canReview ?? status == 'delivered',
  };
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

  setUp(useAuthenticatedSession);

  // R2 §2: the client no longer derives tracking. These assert that a backend
  // payload is preserved verbatim for every persisted status.
  test('CASE A: a backend tracking payload is preserved for every status', () {
    const expected = {
      'pending': ('placed', 0),
      'confirmed': ('placed', 0),
      'preparing': ('preparing', 1),
      'outForDelivery': ('outForDelivery', 2),
      'delivered': ('delivered', 3),
    };

    expected.forEach((status, projection) {
      final tracking = OrderTrackingApiModel.fromJson(serverTracking(status));
      expect(tracking.currentStep, projection.$1, reason: status);
      expect(tracking.currentIndex, projection.$2, reason: status);
      expect(tracking.isCancelled, isFalse, reason: status);
      expect(tracking.steps, hasLength(4), reason: status);
      expect(tracking.steps.map((step) => step.isReached).toList(), [
        for (var i = 0; i < 4; i++) i <= projection.$2,
      ], reason: status);
    });

    final cancelled = OrderTrackingApiModel.fromJson(
      serverTracking('cancelled'),
    );
    expect(cancelled.isCancelled, isTrue);
    expect(cancelled.currentIndex, -1);
    expect(cancelled.currentStep, '');
    expect(cancelled.steps.any((step) => step.isReached), isFalse);
  });

  test('CASE B: an order response without tracking is a contract failure', () {
    expect(
      () => OrderApiModel.fromJson(const {'id': 'o1', 'status': 'pending'}),
      throwsA(isA<ApiContractException>()),
    );
  });

  test('CASE C: malformed or non-object tracking is a contract failure', () {
    for (final tracking in [
      null,
      <String, dynamic>{},
      1,
      'text',
      <dynamic>[],
      true,
    ]) {
      expect(
        () => OrderApiModel.fromJson({
          'id': 'o1',
          'status': 'pending',
          'tracking': tracking,
        }),
        throwsA(isA<ApiContractException>()),
        reason: '$tracking',
      );
    }
  });

  test('CASE D: absent tracking never reconstructs permissions', () {
    // `pending` previously inferred canCancel/canChangeAddress = true. With no
    // tracking object there is now no result at all, rather than a widened one.
    OrderApiModel? parsed;
    try {
      parsed = OrderApiModel.fromJson(const {'id': 'o1', 'status': 'pending'});
    } on ApiContractException {
      parsed = null;
    }

    expect(parsed, isNull);
  });

  test('CASE E: a backend "false" survives a status that once implied true', () {
    // Status is `pending`, which the old client projection read as cancellable
    // and address-changeable. The backend says no, and the backend wins.
    final tracking = OrderTrackingApiModel.fromJson(
      serverTracking(
        'pending',
        canCancel: false,
        canChangeAddress: false,
        canReview: false,
      ),
    );

    expect(tracking.canCancel, isFalse);
    expect(tracking.canChangeAddress, isFalse);
    expect(tracking.canReview, isFalse);

    // And a backend "true" on a status that once implied false is honoured too.
    final permissive = OrderTrackingApiModel.fromJson(
      serverTracking('delivered', canCancel: true),
    );
    expect(permissive.canCancel, isTrue);
  });

  test('missing permission flags default closed, never open', () {
    final tracking = OrderTrackingApiModel.fromJson(const {
      'currentStep': 'placed',
      'currentIndex': 0,
      'steps': <dynamic>[],
    });

    expect(tracking.canCancel, isFalse);
    expect(tracking.canChangeAddress, isFalse);
    expect(tracking.canReview, isFalse);
  });

  test('the server payload is used verbatim', () async {
    // The client must never re-derive a status the server already decided.
    final fromServer = OrderTrackingApiModel.fromJson(const {
      'isCancelled': false,
      'currentStep': 'outForDelivery',
      'currentIndex': 2,
      'steps': [
        {'step': 'placed', 'isReached': true},
        {'step': 'preparing', 'isReached': true},
        {'step': 'outForDelivery', 'isReached': true},
        {'step': 'delivered', 'isReached': false},
      ],
      'canCancel': false,
      'canChangeAddress': false,
      'canReview': false,
    });

    expect(fromServer.currentStep, 'outForDelivery');
    expect(fromServer.currentIndex, 2);
    expect(fromServer.canCancel, isFalse);
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
    // Updated for the FIX2 contract: the business audience now requires a
    // business session, not merely an authenticated one.
    useAuthenticatedSession(business: true);
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

  test('a customer session cannot request the business feed', () async {
    // audience=business is a request parameter, not a role claim.
    final api = _FakeNotificationsApi();
    final bloc = NotificationsBloc(apiService: api, businessAudience: true);

    bloc.add(const NotificationsStarted());
    await bloc.stream.firstWhere(
      (state) => state.status == NotificationsStatus.failure,
    );

    expect(api.audienceFlags, isEmpty);

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
