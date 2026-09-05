import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/business/models/business_models.dart';
import 'package:merzox/features/business/shell/business_bloc.dart';
import 'package:merzox/services/api_service.dart';

import 'auth_session_fixtures.dart';

/// The order filter the merchant browse artboards draw.
///
/// `الرئيسية – 9` puts a status chip and a search field over one table holding
/// every status at once, `الرئيسية – 11` shows the chip's four choices, and
/// `الرئيسية – 12` adds a sheet with an order number, a customer name and a
/// date range. Two claims are under test: the request carries what the
/// merchant chose, and it never carries a status group alongside a status —
/// the server reads the group first, so sending both would silently drop the
/// chip's choice.

class _OrderApi extends ApiService {
  final List<Map<String, dynamic>> requests = <Map<String, dynamic>>[];

  /// The dashboard reads orders too, through the same method, and it always
  /// asks for a period. The orders tab asks for one only when the merchant
  /// fills in the sheet's date fields, and no test here does that while also
  /// caring which request it is looking at - so the presence of `from` tells
  /// the two callers apart.
  List<Map<String, dynamic>> get tabRequests => requests
      .where((Map<String, dynamic> request) => !request.containsKey('from'))
      .toList();

  List<Map<String, dynamic>> get dashboardRequests => requests
      .where((Map<String, dynamic> request) => request.containsKey('from'))
      .toList();

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
  }) async => BusinessDashboardData.fromJson(const <String, dynamic>{});

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
    requests.add(<String, dynamic>{
      'statusGroup': statusGroup,
      ...filter.toQueryParameters(),
    });

    return OwnerOrderList.fromJson(const <String, dynamic>{});
  }

  // The shell reads the account for the picture in its bar. Unstubbed, this
  // would be a real request that never answers inside a test.
  @override
  Future<AuthApiUser> me({required String token}) async =>
      AuthApiUser.fromJson(const <String, dynamic>{'id': 'u1', 'name': 'تاجر'});
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

  /// Applies a filter and waits for the list it produced.
  Future<void> apply(BusinessBloc bloc, MerchantOrderFilter filter) async {
    final int before = api.requests.length;
    bloc.add(BusinessOrderFilterChanged(filter));
    await bloc.stream.firstWhere(
      (BusinessState state) =>
          state.status == BusinessStatus.ready && api.requests.length > before,
    );
  }

  /// The tab's own last request, which is what every claim below is about.
  Map<String, dynamic> lastTabRequest() => api.tabRequests.last;

  group('the request the filter builds', () {
    test('the first load asks for every order, unfiltered', () async {
      await started();

      expect(api.tabRequests, hasLength(1));
      expect(api.tabRequests.single, <String, dynamic>{'statusGroup': ''});
    });

    test('the dashboard asks for its own period on the same load', () async {
      await started();

      // The dashboard's table reports on a period, so its request is not the
      // tab's: one load produces both, and they must not be confused.
      expect(api.dashboardRequests, hasLength(1));
      expect(api.dashboardRequests.single.containsKey('to'), isTrue);
      expect(api.dashboardRequests.single['statusGroup'], '');
    });

    test('the chip sends its status and never a status group', () async {
      final BusinessBloc bloc = await started();
      await apply(bloc, const MerchantOrderFilter(status: 'delivered'));

      expect(lastTabRequest()['status'], 'delivered');
      expect(lastTabRequest()['statusGroup'], '');
    });

    test('clearing the chip drops the status from the request', () async {
      final BusinessBloc bloc = await started();
      await apply(bloc, const MerchantOrderFilter(status: 'cancelled'));
      await apply(bloc, const MerchantOrderFilter());

      expect(lastTabRequest().containsKey('status'), isFalse);
    });

    test('the sheet sends its four fields beside the chip', () async {
      final BusinessBloc bloc = await started();
      await apply(
        bloc,
        MerchantOrderFilter(
          status: 'preparing',
          orderNumber: '222321',
          customerName: 'ياسمين',
          from: DateTime(2022, 2, 1),
          to: DateTime(2022, 2, 15),
        ),
      );

      expect(api.requests.last, <String, dynamic>{
        'statusGroup': '',
        'status': 'preparing',
        'orderNumber': '222321',
        'customerName': 'ياسمين',
        'from': '2022-02-01',
        'to': '2022-02-15',
      });
    });

    test('a refresh keeps the filter the merchant already set', () async {
      final BusinessBloc bloc = await started();
      await apply(
        bloc,
        const MerchantOrderFilter(status: 'preparing', query: 'ياسمين'),
      );

      final int before = api.requests.length;
      bloc.add(const BusinessRefreshed());
      await bloc.stream.firstWhere(
        (BusinessState state) =>
            state.status == BusinessStatus.ready &&
            api.requests.length > before,
      );

      expect(lastTabRequest()['status'], 'preparing');
      expect(lastTabRequest()['q'], 'ياسمين');
    });
  });

  group('the filter value object', () {
    test('sends nothing for a field the merchant left alone', () {
      expect(const MerchantOrderFilter().toQueryParameters(), isEmpty);
      expect(
        const MerchantOrderFilter(
          query: '',
          orderNumber: '',
        ).toQueryParameters(),
        isEmpty,
      );
    });

    test('writes a date as the plain calendar day it was picked on', () {
      // 23:30 local on the 9th is still the 9th: the merchant picked a day on
      // a calendar, so no instant and no time zone is implied.
      final MerchantOrderFilter filter = MerchantOrderFilter(
        from: DateTime(2022, 3, 9, 23, 30),
      );

      expect(filter.toQueryParameters()['from'], '2022-03-09');
    });

    test('knows when the sheet in particular is narrowing the list', () {
      expect(const MerchantOrderFilter().hasSheetFields, isFalse);
      // The chip and the search box are not the sheet.
      expect(
        const MerchantOrderFilter(
          status: 'delivered',
          query: 'x',
        ).hasSheetFields,
        isFalse,
      );
      expect(
        const MerchantOrderFilter(customerName: 'ياسمين').hasSheetFields,
        isTrue,
      );
      expect(
        MerchantOrderFilter(to: DateTime(2022, 2, 15)).hasSheetFields,
        isTrue,
      );
    });

    test('copyWith clears a field only when asked to', () {
      const MerchantOrderFilter full = MerchantOrderFilter(
        status: 'delivered',
        orderNumber: '1',
      );

      expect(full.copyWith(orderNumber: '2').status, 'delivered');
      expect(full.copyWith(clearStatus: true).status, isNull);
      expect(full.copyWith(clearStatus: true).orderNumber, '1');
    });
  });
}
