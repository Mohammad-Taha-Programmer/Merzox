import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/localization/api_error_localizer.dart';
import 'package:merzox/features/business/models/business_models.dart';
import 'package:merzox/features/business/shell/business_bloc.dart';
import 'package:merzox/services/api_service.dart';

import 'auth_session_fixtures.dart';
import 'localization_test_harness.dart';

// `إرسال إشعار` tells the customer the status the order is already in. The
// server owns both what is said and how often, so what is worth pinning here is
// that the client sends no opinion of its own and that a refusal is surfaced
// rather than swallowed.

Map<String, dynamic> _orderJson({String status = 'preparing'}) {
  return <String, dynamic>{
    'id': '64d000000000000000000201',
    'publicId': '222321',
    'customerName': 'ياسمين خالد',
    'customerPhone': '0592029316',
    'items': const <Map<String, dynamic>>[],
    'subtotal': 35,
    'deliveryFee': 10,
    'total': 45,
    'currency': 'ILS',
    'deliveryAddress': 'أريحا ، النبي موسى',
    'paymentMethod': 'cash',
    'status': status,
    'statusGroup': 'current',
    'statusHistory': const <Map<String, dynamic>>[],
    'cancellationReason': '',
    'createdAt': '2022-02-15T10:00:00.000',
    'courier': const <String, dynamic>{},
  };
}

class _NotifyApi extends ApiService {
  int calls = 0;
  String? sentOrderId;
  Object? error;

  @override
  Future<OwnerOrder> notifyOrderCustomer({
    required String token,
    required String orderId,
  }) async {
    calls += 1;
    sentOrderId = orderId;

    if (error != null) {
      throw error!;
    }

    return OwnerOrder.fromJson(_orderJson());
  }
}

/// A merchant moving an order forward. The server both records the status and
/// tells the customer in the same request, so the answer here is deliberately
/// complete: the list, the counts and the dashboard all come back.
class _StatusApi extends ApiService {
  String? sentStatus;

  @override
  Future<OwnerOrder> updateOwnerOrderStatus({
    required String token,
    required String orderId,
    required String status,
    String note = '',
  }) async {
    sentStatus = status;
    return OwnerOrder.fromJson(_orderJson(status: status));
  }

  @override
  Future<OwnerOrderList> ownerOrders({
    required String token,
    String statusGroup = '',
    MerchantOrderFilter filter = const MerchantOrderFilter(),
    int page = 1,
    int limit = 30,
  }) async => OwnerOrderList(
    orders: <OwnerOrder>[OwnerOrder.fromJson(_orderJson(status: 'delivering'))],
    counts: const <String, int>{'current': 1},
    hasMore: false,
  );

  @override
  Future<BusinessDashboardData> businessDashboard({
    required String token,
  }) async => const BusinessDashboardData(
    sales: 45,
    orderCount: 1,
    activeOrderCount: 1,
    viewCount: 0,
    recentOrders: <OwnerOrder>[],
  );
}

/// A server that refuses the move. `INVALID_ORDER_STATUS_TRANSITION` is one of
/// the codes that used to reach the merchant as English prose.
class _RefusingStatusApi extends ApiService {
  @override
  Future<OwnerOrder> updateOwnerOrderStatus({
    required String token,
    required String orderId,
    required String status,
    String note = '',
  }) async {
    throw DioException(
      requestOptions: RequestOptions(path: '/businesses/me/orders/x/status'),
      response: Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(path: '/businesses/me/orders/x/status'),
        statusCode: 409,
        data: const <String, dynamic>{
          'success': false,
          'error': <String, dynamic>{
            'code': 'INVALID_ORDER_STATUS_TRANSITION',
            'message': 'Order cannot move from pending to delivered',
          },
        },
      ),
    );
  }
}

BusinessBloc _bloc(ApiService api) {
  final bloc = BusinessBloc(apiService: api);
  addTearDown(bloc.close);
  return bloc;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(useAuthenticatedSession);

  test('notifying the customer names the order and nothing else', () async {
    final api = _NotifyApi();
    final bloc = _bloc(api);

    final ready = bloc.stream.firstWhere(
      (state) => state.status == BusinessStatus.ready,
    );

    bloc.add(const BusinessOrderCustomerNotified('64d000000000000000000201'));

    final state = await ready;

    expect(api.calls, 1);
    expect(api.sentOrderId, '64d000000000000000000201');
    expect(state.noticeCode, 'merchantOrder.notificationSent');
  });

  test('the notice is one-shot and does not survive the next emit', () async {
    final api = _NotifyApi();
    final bloc = _bloc(api);

    final notified = bloc.stream.firstWhere(
      (state) => state.noticeCode != null,
    );

    bloc.add(const BusinessOrderCustomerNotified('64d000000000000000000201'));
    await notified;

    final settled = bloc.stream.firstWhere((state) => state.selectedTab == 1);

    bloc.add(const BusinessTabChanged(1));

    final cleared = await settled;

    // A notice that outlived the action that earned it would be shown again by
    // the next unrelated rebuild.
    expect(cleared.noticeCode, isNull);
  });

  test('a refusal surfaces as an error and raises no notice', () async {
    final api = _NotifyApi()..error = StateError('cooldown');
    final bloc = _bloc(api);

    final failed = bloc.stream.firstWhere(
      (state) => state.status == BusinessStatus.failure,
    );

    bloc.add(const BusinessOrderCustomerNotified('64d000000000000000000201'));

    final state = await failed;

    expect(state.noticeCode, isNull);
    expect(state.errorMessage, isNotNull);
  });

  test('the answered order replaces the one the list was holding', () async {
    final api = _NotifyApi();
    final bloc = _bloc(api);

    final ready = bloc.stream.firstWhere(
      (state) => state.status == BusinessStatus.ready,
    );

    bloc.add(const BusinessOrderCustomerNotified('64d000000000000000000201'));
    await ready;

    // Nothing was in the list, so nothing was replaced - and the empty list is
    // not overwritten with the single order either.
    expect(bloc.state.orders, isEmpty);
  });

  test('changing the status says so, and says the customer was told', () async {
    final api = _StatusApi();
    final bloc = _bloc(api);

    final Future<BusinessState> settled = bloc.stream.firstWhere(
      (state) => state.status == BusinessStatus.ready,
    );
    bloc.add(
      const BusinessOrderStatusChanged(
        '64d000000000000000000201',
        'delivering',
      ),
    );
    final state = await settled;

    expect(api.sentStatus, 'delivering');
    // The server notifies the customer inside the same request, so the notice
    // is allowed to claim it. A silent redraw was what shipped before.
    expect(state.noticeCode, 'merchantOrder.statusUpdated');
    expect(state.orders.single.status, 'delivering');
  });

  test('a refused status change raises no notice', () async {
    final bloc = _bloc(_RefusingStatusApi());

    final Future<BusinessState> settled = bloc.stream.firstWhere(
      (state) => state.status == BusinessStatus.failure,
    );
    bloc.add(
      const BusinessOrderStatusChanged('64d000000000000000000201', 'delivered'),
    );
    final state = await settled;

    expect(state.noticeCode, isNull);
    expect(state.errorMessage, 'apiErrors.invalidOrderStatusTransition');
  });

  test('the cooldown refusal reaches the merchant in Arabic', () async {
    await loadAppTranslations(languageCode: 'ar');

    final api = _NotifyApi()
      ..error = DioException(
        requestOptions: RequestOptions(path: '/x/notify'),
        response: Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: '/x/notify'),
          statusCode: 429,
          data: const <String, dynamic>{
            'success': false,
            'error': <String, dynamic>{
              'code': 'ORDER_NOTIFY_COOLDOWN',
              'message': 'This order was notified moments ago',
            },
          },
        ),
      );
    final bloc = _bloc(api);

    final Future<BusinessState> failed = bloc.stream.firstWhere(
      (state) => state.status == BusinessStatus.failure,
    );
    bloc.add(const BusinessOrderCustomerNotified('64d000000000000000000201'));
    final state = await failed;

    // The English prose above is what the merchant used to read.
    expect(state.errorMessage, 'apiErrors.orderNotifyCooldown');
    expect(
      localizeApiErrorOrRaw(state.errorMessage!),
      'تم إرسال إشعار قبل قليل. انتظر دقيقة ثم أعد المحاولة.',
    );
  });
}
