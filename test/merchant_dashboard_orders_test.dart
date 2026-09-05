import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/business/models/business_models.dart';
import 'package:merzox/features/business/models/dashboard_period.dart';
import 'package:merzox/features/business/shell/business_bloc.dart';
import 'package:merzox/services/api_service.dart';

import 'auth_session_fixtures.dart';

/// What the dashboard asks the server for.
///
/// The period control governs both the three figures and the table under them,
/// so the two have to be requested against the same days or the numbers will
/// describe a period the rows do not. A year of orders is thousands of rows,
/// so the table takes them a page at a time.

/// The day every period below is resolved against.
final DateTime _today = DateTime(2026, 9, 16);

class _DashboardApi extends ApiService {
  final List<Map<String, dynamic>> orderRequests = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> figureRequests = <Map<String, dynamic>>[];

  /// How many orders the whole period holds, whatever page is asked for.
  int total = 5;

  @override
  Future<OwnerBusiness> ownerBusiness({required String token}) async =>
      OwnerBusiness.fromJson(const <String, dynamic>{
        'id': 'b1',
        'name': 'متجر',
      });

  @override
  Future<BusinessDashboardData> businessDashboard({
    required String token,
    DateTime? from,
    DateTime? to,
  }) async {
    figureRequests.add(<String, dynamic>{'from': from, 'to': to});
    return BusinessDashboardData.fromJson(const <String, dynamic>{});
  }

  @override
  Future<List<OwnerProduct>> ownerProducts({required String token}) async =>
      const <OwnerProduct>[];

  @override
  Future<OwnerOrderList> ownerOrders({
    required String token,
    String statusGroup = '',
    MerchantOrderFilter filter = const MerchantOrderFilter(),
    int page = 1,
    int limit = 20,
  }) async {
    final Map<String, dynamic> request = <String, dynamic>{
      'page': page,
      'limit': limit,
      ...filter.toQueryParameters(),
    };

    // The orders tab reads this method too and never asks for a period; only
    // the dashboard does, so that is what tells the two callers apart.
    if (filter.from != null) {
      orderRequests.add(request);
    }

    return OwnerOrderList.fromJson(<String, dynamic>{
      'orders': const <Map<String, dynamic>>[],
      'pagination': <String, dynamic>{'page': page, 'total': total},
    });
  }

  // The shell reads the account for the picture in its bar. Unstubbed, this
  // would be a real request that never answers inside a test.
  @override
  Future<AuthApiUser> me({required String token}) async =>
      AuthApiUser.fromJson(const <String, dynamic>{'id': 'u1', 'name': 'تاجر'});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _DashboardApi api;

  setUp(() {
    api = _DashboardApi();
    useAuthenticatedSession(business: true);
  });

  Future<BusinessBloc> started() async {
    final BusinessBloc bloc = BusinessBloc(apiService: api, now: () => _today);
    addTearDown(bloc.close);

    final Future<BusinessState> ready = bloc.stream.firstWhere(
      (BusinessState state) => state.status == BusinessStatus.ready,
    );
    bloc.add(const BusinessStarted());
    await ready;

    return bloc;
  }

  /// Waits for the dashboard to finish whatever it was just asked to do.
  Future<BusinessState> settled(BusinessBloc bloc, BusinessEvent event) {
    final Future<BusinessState> done = bloc.stream.firstWhere(
      (BusinessState state) => !state.dashboardBusy,
    );
    bloc.add(event);
    return done;
  }

  test('it opens on this month, not on everything ever sold', () async {
    final BusinessBloc bloc = await started();

    expect(bloc.state.dashboardPeriod, DashboardPeriod.currentMonth);
    expect(api.orderRequests.single['from'], '2026-09-01');
    expect(api.orderRequests.single['to'], '2026-09-16');
  });

  test('the figures are asked for over the same days as the rows', () async {
    await started();

    expect(api.figureRequests, hasLength(1));
    expect(api.figureRequests.single['from'], DateTime(2026, 9, 1));
    expect(api.figureRequests.single['to'], DateTime(2026, 9, 16));
  });

  test('choosing a period moves both requests onto it', () async {
    final BusinessBloc bloc = await started();
    await settled(
      bloc,
      const BusinessDashboardPeriodChanged(DashboardPeriod.lastWeek),
    );

    expect(api.orderRequests.last['from'], '2026-09-10');
    expect(api.orderRequests.last['to'], '2026-09-16');
    expect(api.figureRequests.last['from'], DateTime(2026, 9, 10));
  });

  test('a custom range is sent as the days the merchant picked', () async {
    final BusinessBloc bloc = await started();
    await settled(
      bloc,
      BusinessDashboardPeriodChanged(
        DashboardPeriod.custom(DateTime(2026, 1, 5), DateTime(2026, 2, 9)),
      ),
    );

    expect(api.orderRequests.last['from'], '2026-01-05');
    expect(api.orderRequests.last['to'], '2026-02-09');
  });

  test('the table takes fifty at a time, the server ceiling', () async {
    await started();

    expect(api.orderRequests.single['limit'], 50);
    expect(BusinessBloc.dashboardPageSize, 50);
  });

  test('a page is asked for by number, over the same period', () async {
    api.total = 130;
    final BusinessBloc bloc = await started();

    await settled(bloc, const BusinessDashboardPageChanged(3));

    expect(api.orderRequests.last['page'], 3);
    expect(api.orderRequests.last['from'], '2026-09-01');
    expect(bloc.state.dashboardPage, 3);
  });

  test('the page count is the period, not the page in hand', () async {
    api.total = 130;
    final BusinessBloc bloc = await started();

    // Three pages: fifty, fifty, thirty.
    expect(bloc.state.dashboardOrderTotal, 130);
    expect(bloc.state.dashboardPageCount, 3);
  });

  test('an empty period still reads as one page, never as none', () async {
    api.total = 0;
    final BusinessBloc bloc = await started();

    expect(bloc.state.dashboardPageCount, 1);
  });

  test('a page beyond the last is pulled back to it', () async {
    api.total = 130;
    final BusinessBloc bloc = await started();

    await settled(bloc, const BusinessDashboardPageChanged(99));

    expect(bloc.state.dashboardPage, 3);
    expect(api.orderRequests.last['page'], 3);
  });

  test('narrowing the period returns the reader to the first page', () async {
    api.total = 130;
    final BusinessBloc bloc = await started();
    await settled(bloc, const BusinessDashboardPageChanged(3));

    await settled(
      bloc,
      const BusinessDashboardPeriodChanged(DashboardPeriod.lastWeek),
    );

    // Page three of the old period is not page three of the new one.
    expect(bloc.state.dashboardPage, 1);
    expect(api.orderRequests.last['page'], 1);
  });

  test('the search needle is sent, and clearing it takes it away', () async {
    final BusinessBloc bloc = await started();

    await settled(bloc, const BusinessDashboardSearchChanged('222321'));
    expect(api.orderRequests.last['q'], '222321');
    expect(api.orderRequests.last['from'], '2026-09-01');

    await settled(bloc, const BusinessDashboardSearchChanged(''));
    expect(api.orderRequests.last.containsKey('q'), isFalse);
  });

  test('searching returns the reader to the first page too', () async {
    api.total = 130;
    final BusinessBloc bloc = await started();
    await settled(bloc, const BusinessDashboardPageChanged(2));

    await settled(bloc, const BusinessDashboardSearchChanged('ياسمين'));

    expect(bloc.state.dashboardPage, 1);
  });

  test('the dashboard says when it is working', () async {
    final BusinessBloc bloc = await started();

    final Future<BusinessState> busy = bloc.stream.firstWhere(
      (BusinessState state) => state.dashboardBusy,
    );
    bloc.add(const BusinessDashboardPeriodChanged(DashboardPeriod.year));

    await busy;
    expect(
      (await bloc.stream.firstWhere(
        (BusinessState s) => !s.dashboardBusy,
      )).dashboardBusy,
      isFalse,
    );
  });
}
