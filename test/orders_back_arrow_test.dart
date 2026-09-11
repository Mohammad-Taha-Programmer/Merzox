import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:merzox/core/widgets/merzox_back_chevron.dart';
import 'package:merzox/features/orders/bloc/orders_bloc.dart';
import 'package:merzox/features/orders/bloc/orders_event.dart';
import 'package:merzox/features/orders/pages/orders_page.dart';
import 'package:merzox/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'localization_test_harness.dart';

/// The way out of `طلباتي`.
///
/// The board draws a thin chevron at the reading edge, and it has to leave the
/// screen when it is pressed. Both were reported wrong, and both are held here.

class _OrdersApi extends ApiService {
  @override
  Future<OrderListApiResponse> orders({
    required String token,
    required String status,
    int page = 1,
    int limit = 20,
  }) async => OrderListApiResponse.fromJson(const <String, dynamic>{
    'orders': <dynamic>[],
    'pagination': <String, dynamic>{
      'page': 1,
      'limit': 20,
      'total': 0,
      'hasMore': false,
    },
  });
}

Future<void> _pumpOrders(
  WidgetTester tester, {
  TextDirection direction = TextDirection.rtl,
}) async {
  SharedPreferences.setMockInitialValues(const <String, Object>{});

  final OrdersBloc bloc = OrdersBloc(apiService: _OrdersApi());
  addTearDown(bloc.close);
  bloc.add(const OrdersStarted());

  final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('elsewhere')),
        routes: <RouteBase>[
          GoRoute(
            path: 'orders',
            builder: (_, _) => BlocProvider<OrdersBloc>.value(
              value: bloc,
              child: const OrdersPage(),
            ),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);

  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp.router(
      routerConfig: router,
      builder: (BuildContext context, Widget? child) => Directionality(
        textDirection: direction,
        child: child ?? const SizedBox.shrink(),
      ),
    ),
  );
  await settleFrames(tester);

  router.push('/orders');
  await settleFrames(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadAppTranslations();
  });

  testWidgets('the screen opens on my orders', (tester) async {
    await _pumpOrders(tester);

    expect(find.text('orders.title'.tr()), findsOneWidget);
    expect(find.byType(OrdersPage), findsOneWidget);
  });

  testWidgets('the way back is the artboard mark, not a Material arrow', (
    tester,
  ) async {
    await _pumpOrders(tester);

    expect(find.byType(MerzoxBackChevron), findsOneWidget);
    expect(
      find.byType(BackButton),
      findsNothing,
      reason: 'the shafted arrow is not the mark the board draws',
    );
  });

  testWidgets('the title lies over the mark and does not take its presses', (
    tester,
  ) async {
    // This is the fault itself: the title spans the band so it can be centred
    // in it, a paragraph answers every hit test put to it, and so it took the
    // presses meant for the way back. The overlap is asserted as well as the
    // press - without it, moving the title would quietly retire this test
    // instead of failing it.
    await _pumpOrders(tester);

    final Rect title = tester.getRect(find.text('orders.title'.tr()));
    final Rect mark = tester.getRect(find.byType(MerzoxBackChevron));
    expect(
      title.overlaps(mark),
      isTrue,
      reason: 'the title is still laid over the mark',
    );

    await tester.tap(find.byType(MerzoxBackChevron));
    await settleFrames(tester);

    expect(find.byType(OrdersPage), findsNothing);
    expect(find.text('elsewhere'), findsOneWidget);
  });

  testWidgets('the mark points the way back in each reading order', (
    tester,
  ) async {
    // The chevron is one drawing mirrored, so which way it leans is the only
    // thing that says whether it reads as a way back or a way on.
    for (final (TextDirection direction, bool rightward)
        in <(TextDirection, bool)>[
          (TextDirection.rtl, true),
          (TextDirection.ltr, false),
        ]) {
      await _pumpOrders(tester, direction: direction);

      final CustomPaint paint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byType(MerzoxBackChevron),
          matching: find.byType(CustomPaint),
        ),
      );
      final MerzoxBackChevronPainter painter =
          paint.painter! as MerzoxBackChevronPainter;

      expect(painter.rightward, rightward, reason: 'leaning under $direction');
    }
  });
}
