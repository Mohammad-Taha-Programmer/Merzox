import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/business/models/business_models.dart';
import 'package:merzox/features/business/shell/business_bloc.dart';
import 'package:merzox/services/api_service.dart';

import 'auth_session_fixtures.dart';

/// The order filter the merchant browse artboard draws.
///
/// `الرئيسية – 9` puts a status chip and a search field over one table holding
/// every status at once, and `الرئيسية – 11` shows the chip's four choices.
/// Two claims are under test: the request carries what the merchant chose, and
/// it never carries a status group alongside a status — the server reads the
/// group first, so sending both would silently drop the chip's choice.

class _OrderApi extends ApiService {
  final List<Map<String, String>> requests = <Map<String, String>>[];

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
  Future<List<OwnerProduct>> ownerProducts({required String token}) async =>
      const <OwnerProduct>[];

  @override
  Future<OwnerOrderList> ownerOrders({
    required String token,
    String statusGroup = '',
    String status = '',
    String query = '',
    int page = 1,
    int limit = 20,
  }) async {
    requests.add(<String, String>{
      'statusGroup': statusGroup,
      'status': status,
      'query': query,
    });

    return OwnerOrderList.fromJson(const <String, dynamic>{});
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _OrderApi api;

  setUp(() {
    api = _OrderApi();
    useAuthenticatedSession(business: true);
  });

  Future<BusinessBloc> started() async {
    final BusinessBloc bloc = BusinessBloc(apiService: api);
    addTearDown(bloc.close);

    final Future<BusinessState> ready = bloc.stream.firstWhere(
      (BusinessState state) => state.status == BusinessStatus.ready,
    );
    bloc.add(const BusinessStarted());
    await ready;

    return bloc;
  }

  test('the first load asks for every order, unfiltered', () async {
    await started();

    expect(api.requests, hasLength(1));
    expect(api.requests.single['statusGroup'], '');
    expect(api.requests.single['status'], '');
    expect(api.requests.single['query'], '');
  });

  test('the chip sends its status and never a status group', () async {
    final BusinessBloc bloc = await started();

    final Future<BusinessState> filtered = bloc.stream.firstWhere(
      (BusinessState state) =>
          state.status == BusinessStatus.ready &&
          state.orderStatusFilter == 'delivered',
    );
    bloc.add(const BusinessOrderFilterChanged(status: 'delivered'));
    await filtered;

    expect(api.requests.last['status'], 'delivered');
    expect(api.requests.last['statusGroup'], '');
  });

  test('clearing the chip drops the status from the request', () async {
    final BusinessBloc bloc = await started();

    bloc.add(const BusinessOrderFilterChanged(status: 'cancelled'));
    await bloc.stream.firstWhere(
      (BusinessState state) => state.orderStatusFilter == 'cancelled',
    );

    bloc.add(const BusinessOrderFilterChanged());
    await bloc.stream.firstWhere(
      (BusinessState state) =>
          state.status == BusinessStatus.ready &&
          state.orderStatusFilter == null,
    );

    expect(api.requests.last['status'], '');
  });

  test(
    'the search field forwards what was typed, keeping the status',
    () async {
      final BusinessBloc bloc = await started();

      final Future<BusinessState> searched = bloc.stream.firstWhere(
        (BusinessState state) =>
            state.status == BusinessStatus.ready &&
            state.orderQuery == '222321',
      );
      bloc.add(
        const BusinessOrderFilterChanged(status: 'preparing', query: '222321'),
      );
      await searched;

      expect(api.requests.last['query'], '222321');
      expect(api.requests.last['status'], 'preparing');
    },
  );

  test('a refresh keeps the filter the merchant already set', () async {
    final BusinessBloc bloc = await started();

    bloc.add(
      const BusinessOrderFilterChanged(status: 'preparing', query: 'ياسمين'),
    );
    await bloc.stream.firstWhere(
      (BusinessState state) =>
          state.status == BusinessStatus.ready && state.orderQuery == 'ياسمين',
    );

    final int before = api.requests.length;
    bloc.add(const BusinessRefreshed());
    await bloc.stream.firstWhere(
      (BusinessState state) =>
          state.status == BusinessStatus.ready && api.requests.length > before,
    );

    expect(api.requests.last['status'], 'preparing');
    expect(api.requests.last['query'], 'ياسمين');
  });
}
