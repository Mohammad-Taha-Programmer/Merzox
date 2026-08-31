import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/services/device_location_service.dart';
import 'package:merzox/services/location_permission_service.dart';
import 'package:merzox/features/business/models/business_models.dart';
import 'package:merzox/features/business/shell/business_bloc.dart';
import 'package:merzox/features/business/shell/business_shell_page.dart';
import 'package:merzox/features/favorites/bloc/favorites_bloc.dart';
import 'package:merzox/features/favorites/bloc/favorites_event.dart';
import 'package:merzox/features/favorites/bloc/favorites_state.dart';
import 'package:merzox/features/favorites/pages/favorites_page.dart';
import 'package:merzox/features/home/home_screen.dart';
import 'package:merzox/features/home/presentation/bloc/home_bloc.dart';
import 'package:merzox/features/home/presentation/bloc/home_event.dart';
import 'package:merzox/features/home/presentation/bloc/home_state_.dart';
import 'package:merzox/features/messages/bloc/messages_bloc.dart';
import 'package:merzox/features/messages/bloc/messages_event.dart';
import 'package:merzox/features/messages/bloc/messages_state.dart';
import 'package:merzox/features/messages/pages/messages_inbox_view.dart';
import 'package:merzox/features/notifications/bloc/notifications_bloc.dart';
import 'package:merzox/features/notifications/bloc/notifications_event.dart';
import 'package:merzox/features/notifications/bloc/notifications_state.dart';
import 'package:merzox/features/notifications/pages/notifications_page.dart';
import 'package:merzox/features/orders/bloc/orders_bloc.dart';
import 'package:merzox/features/orders/bloc/orders_event.dart';
import 'package:merzox/features/orders/bloc/orders_state.dart';
import 'package:merzox/features/orders/pages/orders_page.dart';
import 'package:merzox/features/search/bloc/search_bloc.dart';
import 'package:merzox/features/search/bloc/search_event.dart';
import 'package:merzox/features/search/bloc/search_state.dart';
import 'package:merzox/features/search/pages/search_page.dart';
import 'package:merzox/services/api_service.dart';

import 'auth_session_fixtures.dart';
import 'localization_test_harness.dart';

/// What the app shows when the database holds nothing.
///
/// A fresh deployment has no shops, no products, no orders, no conversations
/// and no notifications, and the server answers every one of those with `200`
/// and an empty list. That is the moment the first real customer meets, so
/// every surface has to say something in Arabic rather than show a blank page,
/// a spinner that never stops, or an error meant for a developer.

/// Answers every read the way an untouched database does: successfully, with
/// nothing in it.
class _EmptyApi extends ApiService {
  @override
  Future<BusinessListApiResponse> businesses({
    int page = 1,
    int limit = 100,
    String? search,
    String? sort,
    bool? discounted,
    double? latitude,
    double? longitude,
    int? radiusMeters,
  }) async => BusinessListApiResponse.fromJson(const <String, dynamic>{
    'businesses': <Map<String, dynamic>>[],
    'pagination': <String, dynamic>{
      'page': 1,
      'limit': 20,
      'total': 0,
      'hasMore': false,
    },
  });

  @override
  Future<OrderListApiResponse> orders({
    required String token,
    required String status,
    int page = 1,
    int limit = 20,
  }) async => OrderListApiResponse.fromJson(const <String, dynamic>{
    'orders': <Map<String, dynamic>>[],
    'counts': <String, dynamic>{},
    'pagination': <String, dynamic>{
      'page': 1,
      'limit': 20,
      'total': 0,
      'hasMore': false,
    },
  });

  @override
  Future<ConversationListApiResponse> conversations({
    required String token,
    bool unreadOnly = false,
    int page = 1,
    int limit = 20,
  }) async => ConversationListApiResponse.fromJson(const <String, dynamic>{
    'conversations': <Map<String, dynamic>>[],
    'unreadConversationCount': 0,
    'pagination': <String, dynamic>{
      'page': 1,
      'limit': 20,
      'total': 0,
      'hasMore': false,
    },
  });

  @override
  Future<NotificationListApiResponse> notifications({
    required String token,
    bool businessAudience = false,
    bool unreadOnly = false,
    int page = 1,
    int limit = 20,
  }) async => NotificationListApiResponse.fromJson(const <String, dynamic>{
    'notifications': <Map<String, dynamic>>[],
    'unreadCount': 0,
    'pagination': <String, dynamic>{
      'page': 1,
      'limit': 20,
      'total': 0,
      'hasMore': false,
    },
  });

  @override
  Future<int> notificationUnreadCount({
    required String token,
    bool businessAudience = false,
  }) async => 0;

  @override
  Future<FavoriteBusinessListApiResponse> favoriteBusinesses({
    required String token,
    int page = 1,
    int limit = 20,
  }) async => FavoriteBusinessListApiResponse.fromJson(const <String, dynamic>{
    'businesses': <Map<String, dynamic>>[],
    'pagination': <String, dynamic>{
      'page': 1,
      'limit': 20,
      'total': 0,
      'hasMore': false,
    },
  });

  @override
  Future<FavoriteProductListApiResponse> favoriteProducts({
    required String token,
    int page = 1,
    int limit = 20,
  }) async => FavoriteProductListApiResponse.fromJson(const <String, dynamic>{
    'products': <Map<String, dynamic>>[],
    'pagination': <String, dynamic>{
      'page': 1,
      'limit': 20,
      'total': 0,
      'hasMore': false,
    },
  });

  @override
  Future<SearchApiResponse> searchCatalog({
    required String query,
    int limit = 30,
  }) async => SearchApiResponse.fromJson(const <String, dynamic>{
    'query': '',
    'products': <Map<String, dynamic>>[],
    'businesses': <Map<String, dynamic>>[],
  });

  @override
  Future<List<SavedAddressApiModel>> myAddresses({
    required String token,
  }) async => const <SavedAddressApiModel>[];

  // -- merchant ------------------------------------------------------------

  @override
  Future<OwnerBusiness> ownerBusiness({required String token}) async =>
      OwnerBusiness.fromJson(const <String, dynamic>{
        'id': '64b000000000000000000001',
        'name': 'متجر الياسمين',
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
  }) async => OwnerOrderList.fromJson(const <String, dynamic>{});

  @override
  Future<List<OwnerProduct>> ownerProducts({required String token}) async =>
      const <OwnerProduct>[];

  @override
  Future<ConversationListApiResponse> merchantConversations({
    required String token,
    bool unreadOnly = false,
    int page = 1,
    int limit = 20,
  }) async => conversations(token: token, unreadOnly: unreadOnly);
}

/// A device that will not answer, which is what a test device does. Without
/// these the bloc waits on a platform channel that never replies.
final class _NoLocationPermission extends LocationPermissionService {
  @override
  Future<bool> isLocationGranted() async => false;
}

final class _NoDeviceLocation extends DeviceLocationService {
  @override
  Future<bool> isServiceEnabled() async => false;
}

/// Every string the surface actually drew, for reading back in a failure.
List<String> _visibleText(WidgetTester tester) {
  return tester
      .widgetList<Text>(find.byType(Text))
      .map((Text text) => text.data ?? '')
      .where((String value) => value.trim().isNotEmpty)
      .toList();
}

/// The two failures worth naming: a page that drew nothing a reader can use,
/// and a page still spinning after everything has settled.
void expectSpeaks(WidgetTester tester, String surface) {
  final List<String> texts = _visibleText(tester);

  expect(
    find.byType(CircularProgressIndicator),
    findsNothing,
    reason: '$surface is still loading after its empty answer arrived',
  );
  expect(
    texts,
    isNotEmpty,
    reason: '$surface drew no text at all on an empty database',
  );
}

/// The storefront of a shop with no products is covered next door, in
/// `empty_storefront_test.dart`: it needs the app's own font and theme to lay
/// its filter row out at 375, which only the golden harness provides.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(loadAppTranslations);

  late _EmptyApi api;

  setUp(() {
    api = _EmptyApi();
    useAuthenticatedSession();
  });

  testWidgets('the home catalogue says the shops are not there yet', (
    WidgetTester tester,
  ) async {
    final HomeBloc bloc = HomeBloc(
      apiService: api,
      deviceLocationService: _NoDeviceLocation(),
      locationPermissionService: _NoLocationPermission(),
    );
    addTearDown(bloc.close);

    final Future<HomeState> ready = bloc.stream.firstWhere(
      (HomeState state) =>
          state.newBusinessesStatus == HomeSectionStatus.ready &&
          state.discountedBusinessesStatus == HomeSectionStatus.ready,
    );
    bloc.add(const HomeStarted(isGuest: false));
    await ready;

    await pumpLocalized(
      tester,
      BlocProvider<HomeBloc>.value(
        value: bloc,
        child: HomeScreen(isGuest: false, apiService: api),
      ),
    );

    expectSpeaks(tester, 'home catalogue');
    expect(find.text('لا توجد نتائج في متاجر جديدة'), findsOneWidget);
  });

  testWidgets('the orders list says there are no orders', (
    WidgetTester tester,
  ) async {
    final OrdersBloc bloc = OrdersBloc(apiService: api);
    addTearDown(bloc.close);

    final Future<OrdersState> ready = bloc.stream.firstWhere(
      (OrdersState state) => state.status != OrdersStatus.loading,
    );
    bloc.add(const OrdersStarted());
    await ready;

    await pumpLocalized(
      tester,
      BlocProvider<OrdersBloc>.value(value: bloc, child: const OrdersPage()),
    );

    expectSpeaks(tester, 'orders');
    expect(find.text('عذراً، لا يوجد لديك طلبات'), findsOneWidget);
  });

  testWidgets('favourites says nothing has been saved', (
    WidgetTester tester,
  ) async {
    final FavoritesBloc bloc = FavoritesBloc(apiService: api);
    addTearDown(bloc.close);

    final Future<FavoritesState> ready = bloc.stream.firstWhere(
      (FavoritesState state) => state.status != FavoritesStatus.loading,
    );
    bloc.add(const FavoritesStarted());
    await ready;

    await pumpLocalized(
      tester,
      BlocProvider<FavoritesBloc>.value(
        value: bloc,
        child: const FavoritesPage(),
      ),
    );

    expectSpeaks(tester, 'favourites');
    expect(find.text('لا توجد متاجر مفضلة حتى الآن'), findsOneWidget);
  });

  testWidgets('the inbox says there are no conversations', (
    WidgetTester tester,
  ) async {
    final MessagesBloc bloc = MessagesBloc(apiService: api);
    addTearDown(bloc.close);

    final Future<MessagesState> ready = bloc.stream.firstWhere(
      (MessagesState state) => state.status != MessagesStatus.loading,
    );
    bloc.add(const MessagesStarted());
    await ready;

    await pumpLocalized(
      tester,
      BlocProvider<MessagesBloc>.value(
        value: bloc,
        // The inbox is drawn inside the shell's messages tab, so it expects a
        // Scaffold above it the way its own golden gives it one.
        child: const Scaffold(
          body: SafeArea(child: MessagesInboxView(title: 'الرسائل')),
        ),
      ),
    );

    expectSpeaks(tester, 'inbox');
    expect(find.text('عذرًا ، الرسائل فارغة'), findsOneWidget);
  });

  testWidgets('notifications says there are none', (WidgetTester tester) async {
    final NotificationsBloc bloc = NotificationsBloc(apiService: api);
    addTearDown(bloc.close);

    final Future<NotificationsState> ready = bloc.stream.firstWhere(
      (NotificationsState state) => state.status != NotificationsStatus.loading,
    );
    bloc.add(const NotificationsStarted());
    await ready;

    await pumpLocalized(
      tester,
      BlocProvider<NotificationsBloc>.value(
        value: bloc,
        child: const NotificationsPage(),
      ),
    );

    expectSpeaks(tester, 'notifications');
    expect(find.text('لا يوجد إشعارات'), findsOneWidget);
  });

  testWidgets('the merchant shell opens on an empty store', (
    WidgetTester tester,
  ) async {
    useAuthenticatedSession(business: true);

    final BusinessBloc bloc = BusinessBloc(apiService: api);
    addTearDown(bloc.close);

    final Future<BusinessState> ready = bloc.stream.firstWhere(
      (BusinessState state) => state.status != BusinessStatus.loading,
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

    expectSpeaks(tester, 'merchant dashboard');
    expect(find.text('لا توجد طلبات حديثة'), findsOneWidget);
  });

  testWidgets('the stores tab says the catalogue is empty', (
    WidgetTester tester,
  ) async {
    final HomeBloc bloc = HomeBloc(
      apiService: api,
      deviceLocationService: _NoDeviceLocation(),
      locationPermissionService: _NoLocationPermission(),
    );
    addTearDown(bloc.close);

    final Future<HomeState> ready = bloc.stream.firstWhere(
      (HomeState state) =>
          state.newBusinessesStatus == HomeSectionStatus.ready &&
          state.discountedBusinessesStatus == HomeSectionStatus.ready,
    );
    bloc.add(const HomeStarted(isGuest: false));
    await ready;
    bloc.add(const HomeTabChanged(2));

    await pumpLocalized(
      tester,
      BlocProvider<HomeBloc>.value(
        value: bloc,
        child: HomeScreen(isGuest: false, apiService: api),
      ),
    );

    expectSpeaks(tester, 'stores tab');
    expect(find.text('لم يُسجَّل أي متجر بعد. عد قريباً.'), findsOneWidget);
  });

  testWidgets('the basket says it is empty', (WidgetTester tester) async {
    final HomeBloc bloc = HomeBloc(
      apiService: api,
      deviceLocationService: _NoDeviceLocation(),
      locationPermissionService: _NoLocationPermission(),
    );
    addTearDown(bloc.close);

    final Future<HomeState> ready = bloc.stream.firstWhere(
      (HomeState state) => state.newBusinessesStatus == HomeSectionStatus.ready,
    );
    bloc.add(const HomeStarted(isGuest: false));
    await ready;
    bloc.add(const HomeTabChanged(1));

    await pumpLocalized(
      tester,
      BlocProvider<HomeBloc>.value(
        value: bloc,
        child: HomeScreen(isGuest: false, apiService: api),
      ),
    );

    expectSpeaks(tester, 'basket');
    expect(find.text('عذراً، السلة فارغة'), findsOneWidget);
  });

  testWidgets('a search that finds nothing says so', (
    WidgetTester tester,
  ) async {
    final SearchBloc bloc = SearchBloc(apiService: api);
    addTearDown(bloc.close);

    bloc.add(const SearchStarted());
    final Future<SearchState> answered = bloc.stream.firstWhere(
      (SearchState state) => state.status == SearchStatus.success,
    );
    bloc.add(const SearchSubmitted('أساس'));
    await answered;

    await pumpLocalized(
      tester,
      BlocProvider<SearchBloc>.value(value: bloc, child: const SearchPage()),
    );

    expectSpeaks(tester, 'search');
    expect(find.text('لا توجد نتائج'), findsOneWidget);
  });

  testWidgets('the merchant orders tab says there are none', (
    WidgetTester tester,
  ) async {
    useAuthenticatedSession(business: true);

    final BusinessBloc bloc = BusinessBloc(apiService: api);
    addTearDown(bloc.close);

    final Future<BusinessState> ready = bloc.stream.firstWhere(
      (BusinessState state) => state.status == BusinessStatus.ready,
    );
    bloc.add(const BusinessStarted());
    await ready;
    bloc.add(const BusinessTabChanged(1));

    await pumpLocalized(
      tester,
      BlocProvider<BusinessBloc>.value(
        value: bloc,
        child: BusinessShellPage(onLoggedOut: () {}),
      ),
    );

    expectSpeaks(tester, 'merchant orders');
    expect(find.text('لا توجد طلبات في هذه القائمة'), findsOneWidget);
  });

  testWidgets('the merchant products tab says the shelf is bare', (
    WidgetTester tester,
  ) async {
    useAuthenticatedSession(business: true);

    final BusinessBloc bloc = BusinessBloc(apiService: api);
    addTearDown(bloc.close);

    final Future<BusinessState> ready = bloc.stream.firstWhere(
      (BusinessState state) => state.status == BusinessStatus.ready,
    );
    bloc.add(const BusinessStarted());
    await ready;
    bloc.add(const BusinessTabChanged(3));

    await pumpLocalized(
      tester,
      BlocProvider<BusinessBloc>.value(
        value: bloc,
        child: BusinessShellPage(onLoggedOut: () {}),
      ),
    );

    expectSpeaks(tester, 'merchant products');
    expect(find.text('لم تضف منتجات بعد'), findsOneWidget);
  });
}
