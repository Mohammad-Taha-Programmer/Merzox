import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/orders/bloc/orders_bloc.dart';
import 'package:merzox/features/orders/bloc/orders_event.dart';
import 'package:merzox/features/orders/bloc/orders_state.dart';
import 'package:merzox/features/orders/pages/orders_page.dart';
import 'package:merzox/services/api_service.dart';

import 'auth_session_fixtures.dart';
import 'localization_test_harness.dart';

// `تفاصيل المتجر – 22` and `– 37` draw the first current-order card slid aside
// over an orange `الغاء الطلب`, which is a swipe caught mid-gesture. Cancelling
// is therefore reachable only by dragging, so these tests exist: an action
// behind a gesture is the kind that stops working without anyone noticing.

Map<String, dynamic> _order({required String statusGroup}) {
  return <String, dynamic>{
    'id': '64d000000000000000000101',
    'publicId': '222321',
    'business': <String, dynamic>{
      'id': '64b000000000000000000009',
      'name': 'متجر الياسمين',
    },
    'items': <Map<String, dynamic>>[
      <String, dynamic>{
        'productId': '64c000000000000000000101',
        'variantId': 'v1',
        'name': 'أساس فت مي',
        'imageUrl': '',
        'unitPrice': 35,
        'quantity': 1,
        'variant': '',
      },
    ],
    'subtotal': 35,
    'deliveryFee': 10,
    'total': 45,
    'currency': 'ILS',
    'deliveryAddress': 'رام الله ، المصيون',
    'paymentMethod': 'cash',
    'status': statusGroup == 'current' ? 'preparing' : 'delivered',
    'statusGroup': statusGroup,
    'statusHistory': const <Map<String, dynamic>>[],
    'cancellationReason': '',
    'createdAt': '2022-01-30T10:00:00.000',
    'courier': const <String, dynamic>{},
    'tracking': <String, dynamic>{
      'isCancelled': false,
      'currentStep': 'placed',
      'currentIndex': 0,
      'steps': const <Map<String, dynamic>>[],
      'courier': const <String, dynamic>{},
      'courierLocation': null,
      'canCancel': statusGroup == 'current',
      'canChangeAddress': statusGroup == 'current',
      'canReview': false,
    },
  };
}

class _OrdersApi extends ApiService {
  @override
  Future<OrderListApiResponse> orders({
    required String token,
    required String status,
    int page = 1,
    int limit = 20,
  }) async {
    return OrderListApiResponse.fromJson(<String, dynamic>{
      'orders': <Map<String, dynamic>>[_order(statusGroup: status)],
      'pagination': <String, dynamic>{
        'page': 1,
        'limit': limit,
        'total': 1,
        'hasMore': false,
      },
      'counts': const <String, dynamic>{'total': 3},
    });
  }
}

Future<OrdersBloc> _readyBloc(OrdersGroup group) async {
  useAuthenticatedSession();

  final bloc = OrdersBloc(apiService: _OrdersApi());
  addTearDown(bloc.close);

  final ready = bloc.stream.firstWhere(
    (state) => state.status == OrdersStatus.ready,
  );
  bloc.add(const OrdersStarted());
  await ready;

  if (group != OrdersGroup.current) {
    bloc.add(OrdersGroupChanged(group));
    await bloc.stream.firstWhere(
      (state) =>
          state.status == OrdersStatus.ready && state.selectedGroup == group,
    );
  }

  return bloc;
}

Future<void> _pump(WidgetTester tester, OrdersBloc bloc) {
  return pumpLocalized(
    tester,
    BlocProvider<OrdersBloc>.value(value: bloc, child: const OrdersPage()),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadAppTranslations();
  });

  testWidgets('the cancel action stays covered until the card is dragged', (
    tester,
  ) async {
    final bloc = await _readyBloc(OrdersGroup.current);
    await _pump(tester, bloc);

    final title = find.text('أساس فت مي');
    expect(title, findsOneWidget);

    // The action is in the tree from the start - underneath, not absent.
    final cancel = find.text('إلغاء الطلب');
    expect(cancel, findsOneWidget);

    final Offset spot = tester.getCenter(cancel);

    // Tapping where it sits does nothing, because the card is over it.
    await tester.tapAt(spot);
    await settleFrames(tester);
    expect(find.text('إلغاء الطلب؟'), findsNothing);

    // In Arabic the card travels towards the right, which is the logical
    // start, and stops at the width of the panel it uncovers.
    final double before = tester.getTopLeft(title).dx;
    await tester.drag(title, const Offset(140, 0));
    await settleFrames(tester);

    expect(tester.getTopLeft(title).dx - before, 120);
    expect(tester.getCenter(cancel), spot);
  });

  testWidgets('the revealed action opens the cancellation dialog', (
    tester,
  ) async {
    final bloc = await _readyBloc(OrdersGroup.current);
    await _pump(tester, bloc);

    await tester.drag(find.text('أساس فت مي'), const Offset(140, 0));
    await settleFrames(tester);

    await tester.tap(find.text('إلغاء الطلب'));
    await settleFrames(tester);

    expect(find.text('إلغاء الطلب؟'), findsOneWidget);
    expect(find.text('سبب الإلغاء (اختياري)'), findsOneWidget);
  });

  testWidgets('a completed order carries no cancel action at all', (
    tester,
  ) async {
    final bloc = await _readyBloc(OrdersGroup.completed);
    await _pump(tester, bloc);

    expect(find.text('أساس فت مي'), findsOneWidget);
    expect(find.text('إلغاء الطلب'), findsNothing);
    // Nothing to track once it has arrived.
    expect(find.text('تتبع الطلب'), findsNothing);
  });
}
