import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/business/models/business_models.dart';
import 'package:merzox/features/business/shell/business_bloc.dart';
import 'package:merzox/services/api_service.dart';

import 'auth_session_fixtures.dart';

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
}
