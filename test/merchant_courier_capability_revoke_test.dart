import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/business/models/business_models.dart';
import 'package:merzox/features/business/shell/business_bloc.dart';
import 'package:merzox/features/business/shell/business_shell_page.dart';
import 'package:merzox/services/api_service.dart';

import 'auth_session_fixtures.dart';
import 'localization_test_harness.dart';

/// `تجاهل الرمز` has to reach the server.
///
/// The merchant mints a courier location credential by assigning a courier,
/// and the handoff dialog shows it exactly once. The discard button named what
/// it did not do: it closed the dialog and left the credential live until the
/// order was delivered or cancelled. The server's kill switch had no caller at
/// all, so a merchant who saw the code go to the wrong person had no way back.

const String _orderId = '64d000000000000000000201';

Map<String, dynamic> _orderJson({String courierName = 'سامر'}) =>
    <String, dynamic>{
      'id': _orderId,
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
      'status': 'delivering',
      'statusGroup': 'current',
      'statusHistory': const <Map<String, dynamic>>[],
      'cancellationReason': '',
      'createdAt': '2022-02-15T10:00:00.000',
      'courier': <String, dynamic>{'name': courierName, 'phone': '0599000000'},
    };

class _CapabilityApi extends ApiService {
  final List<String> revoked = <String>[];
  Object? revokeError;

  @override
  Future<OwnerBusiness> ownerBusiness({required String token}) async =>
      OwnerBusiness.fromJson(const <String, dynamic>{
        'id': 'b1',
        'name': 'متجر',
      });

  @override
  Future<BusinessDashboardData> businessDashboard({
    required String token,
  }) async => BusinessDashboardData.fromJson(const <String, dynamic>{});

  @override
  Future<OwnerOrderList> ownerOrders({
    required String token,
    String statusGroup = '',
    MerchantOrderFilter filter = const MerchantOrderFilter(),
    int page = 1,
    int limit = 30,
  }) async => OwnerOrderList(
    orders: <OwnerOrder>[OwnerOrder.fromJson(_orderJson())],
    counts: const <String, int>{'current': 1},
    hasMore: false,
  );

  @override
  Future<List<OwnerProduct>> ownerProducts({required String token}) async =>
      const <OwnerProduct>[];

  @override
  Future<CourierAssignmentApiResult> assignOrderCourier({
    required String token,
    required String orderId,
    required String name,
    String phone = '',
  }) async => CourierAssignmentApiResult(
    order: OwnerOrder.fromJson(_orderJson(courierName: name)),
    capability: CourierLocationCapabilityApiModel(
      token: List<String>.filled(43, 'A').join(),
      expiresAt: DateTime.utc(2026, 9, 1, 12),
    ),
  );

  @override
  Future<OwnerOrder> revokeOrderCourierLocation({
    required String token,
    required String orderId,
  }) async {
    revoked.add(orderId);

    if (revokeError != null) {
      throw revokeError!;
    }

    return OwnerOrder.fromJson(_orderJson());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(loadAppTranslations);

  late _CapabilityApi api;

  setUp(() {
    api = _CapabilityApi();
    useAuthenticatedSession(business: true);
  });

  Future<BusinessBloc> pumpShell(WidgetTester tester) async {
    final BusinessBloc bloc = BusinessBloc(apiService: api);
    addTearDown(bloc.close);

    final Future<BusinessState> ready = bloc.stream.firstWhere(
      (BusinessState state) => state.status == BusinessStatus.ready,
    );
    bloc.add(const BusinessStarted());
    await ready;

    await pumpLocalized(
      tester,
      BlocProvider<BusinessBloc>.value(
        value: bloc,
        child: BusinessShellPage(onLoggedOut: () {}),
      ),
    );

    return bloc;
  }

  testWidgets('discarding the handoff revokes the credential on the server', (
    WidgetTester tester,
  ) async {
    final BusinessBloc bloc = await pumpShell(tester);

    bloc.add(
      const BusinessOrderCourierAssigned(orderId: _orderId, name: 'سامر'),
    );
    await settleFrames(tester);

    expect(find.text('صلاحية موقع المندوب'), findsOneWidget);

    await tester.tap(find.text('تجاهل الرمز'));
    await settleFrames(tester);

    expect(api.revoked, <String>[_orderId]);
    expect(find.text('صلاحية موقع المندوب'), findsNothing);
  });

  test('the revoke raises a notice the merchant can read', () async {
    final BusinessBloc bloc = BusinessBloc(apiService: api);
    addTearDown(bloc.close);

    final Future<BusinessState> settled = bloc.stream.firstWhere(
      (BusinessState state) => state.status == BusinessStatus.ready,
    );
    bloc.add(const BusinessCourierLocationRevoked(_orderId));
    final BusinessState state = await settled;

    expect(api.revoked, <String>[_orderId]);
    expect(state.noticeCode, 'courierLocation.accessRevoked');
  });

  test('a refused revoke surfaces as an error and raises no notice', () async {
    api.revokeError = StateError('refused');

    final BusinessBloc bloc = BusinessBloc(apiService: api);
    addTearDown(bloc.close);

    final Future<BusinessState> settled = bloc.stream.firstWhere(
      (BusinessState state) => state.status == BusinessStatus.failure,
    );
    bloc.add(const BusinessCourierLocationRevoked(_orderId));
    final BusinessState state = await settled;

    expect(state.noticeCode, isNull);
    expect(state.errorMessage, isNotNull);
  });
}
