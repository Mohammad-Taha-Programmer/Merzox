import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:merzox/features/notifications/bloc/notifications_bloc.dart';
import 'package:merzox/features/notifications/bloc/notifications_event.dart';
import 'package:merzox/features/notifications/bloc/notifications_state.dart';
import 'package:merzox/features/notifications/notifications_session_store.dart';
import 'package:merzox/services/api_service.dart';

/// What the bell costs the second time it is pressed.
///
/// Reported from a phone: the list is built again on every press. It was - the
/// bell builds a new bloc each time, and that bloc asked the server for page
/// one and showed a spinner while it waited, for a list that had not changed
/// since the press before.
///
/// The feed is held for as long as the app is open now. In memory, not on
/// disk: the rule is that nothing about notifications outlives the app, and a
/// process that has ended has already forgotten. A file would need a cleanup
/// that a crash or a force-stop could skip, and what it left behind would be
/// one account's notifications on a shared phone.

AppNotificationApiModel _item(String id, {bool read = false}) =>
    AppNotificationApiModel(
      id: id,
      type: 'orderPlaced',
      title: 'طلب $id',
      body: '',
      data: <String, dynamic>{'orderId': id},
      isRead: read,
      createdAt: DateTime(2026, 9, 12),
    );

class _Session implements AuthSessionService {
  const _Session();

  @override
  Future<AuthSessionSnapshot> read() async =>
      const AuthSessionSnapshot(type: AuthSessionType.business, token: 'token');

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Counts what it is asked for, and answers a page at a time.
class _CountingApi extends ApiService {
  final List<int> pagesAsked = <int>[];
  final List<int> limitsAsked = <int>[];

  /// Page number to what that page holds.
  final Map<int, List<AppNotificationApiModel>> pages;

  final int unreadCount;

  _CountingApi(this.pages) : unreadCount = 1;

  @override
  Future<NotificationListApiResponse> notifications({
    required String token,
    bool businessAudience = false,
    bool unreadOnly = false,
    int page = 1,
    int limit = 20,
  }) async {
    pagesAsked.add(page);
    limitsAsked.add(limit);

    return NotificationListApiResponse(
      notifications: pages[page] ?? const <AppNotificationApiModel>[],
      unreadCount: unreadCount,
      page: page,
      hasMore: pages.containsKey(page + 1),
    );
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Says no, the way a phone with no signal does.
class _RefusingApi extends ApiService {
  @override
  Future<NotificationListApiResponse> notifications({
    required String token,
    bool businessAudience = false,
    bool unreadOnly = false,
    int page = 1,
    int limit = 20,
  }) async {
    throw StateError('offline');
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

NotificationsBloc _bloc(_CountingApi api, {NotificationsSessionStore? store}) =>
    NotificationsBloc(
      apiService: api,
      authSessionService: const _Session(),
      sessionStore: store,
      businessAudience: true,
    );

void main() {
  test('the first press fetches, the second press does not', () async {
    final _CountingApi api = _CountingApi(<int, List<AppNotificationApiModel>>{
      1: <AppNotificationApiModel>[_item('a'), _item('b')],
    });
    final NotificationsSessionStore store = NotificationsSessionStore();

    final NotificationsBloc first = _bloc(api, store: store);
    first.add(const NotificationsStarted());
    await first.stream.firstWhere(
      (NotificationsState s) => s.status == NotificationsStatus.ready,
    );
    await first.close();

    expect(api.pagesAsked, <int>[1]);

    // The bell is pressed again: a new bloc, the same run of the app.
    final NotificationsBloc second = _bloc(api, store: store);
    second.add(const NotificationsStarted());
    final NotificationsState opened = await second.stream.first;

    expect(
      api.pagesAsked,
      <int>[1],
      reason: 'the second press asked the server for a list it already had',
    );
    expect(opened.status, NotificationsStatus.ready);
    expect(
      opened.notifications.map((AppNotificationApiModel n) => n.id),
      <String>['a', 'b'],
      reason: 'and it opened on what was already fetched, not on a spinner',
    );

    await second.close();
  });

  test('with no store every press pays, which is how it was', () async {
    final _CountingApi api = _CountingApi(<int, List<AppNotificationApiModel>>{
      1: <AppNotificationApiModel>[_item('a')],
    });

    for (int press = 0; press < 2; press += 1) {
      final NotificationsBloc bloc = _bloc(api);
      bloc.add(const NotificationsStarted());
      await bloc.stream.firstWhere(
        (NotificationsState s) => s.status == NotificationsStatus.ready,
      );
      await bloc.close();
    }

    expect(api.pagesAsked, <int>[1, 1]);
  });

  test('it asks for fifty at a time, not twenty', () async {
    final _CountingApi api = _CountingApi(<int, List<AppNotificationApiModel>>{
      1: <AppNotificationApiModel>[_item('a')],
    });

    final NotificationsBloc bloc = _bloc(api);
    bloc.add(const NotificationsStarted());
    await bloc.stream.firstWhere(
      (NotificationsState s) => s.status == NotificationsStatus.ready,
    );
    await bloc.close();

    expect(
      api.limitsAsked,
      <int>[kNotificationsFetchSize],
      reason:
          'the screen shows fifty before it offers more, so twenty made the '
          'first screenful three round trips instead of one',
    );
    expect(kNotificationsFetchSize, 50);
  });

  test('a refused fetch is not remembered as an empty list', () async {
    // Remembering a failure would hand the next press of the bell an empty
    // list wearing the face of a loaded one, and the reader would have to
    // close the app to be shown their notifications again.
    final NotificationsSessionStore store = NotificationsSessionStore();

    final NotificationsBloc bloc = NotificationsBloc(
      apiService: _RefusingApi(),
      authSessionService: const _Session(),
      sessionStore: store,
      businessAudience: true,
    );

    bloc.add(const NotificationsStarted());
    await bloc.stream.firstWhere(
      (NotificationsState s) => s.status == NotificationsStatus.failure,
    );
    await bloc.close();

    expect(store.isEmpty, isTrue);
  });

  test('an empty answer is remembered, because it is an answer', () async {
    final _CountingApi api = _CountingApi(
      const <int, List<AppNotificationApiModel>>{},
    );
    final NotificationsSessionStore store = NotificationsSessionStore();

    final NotificationsBloc bloc = _bloc(api, store: store);
    bloc.add(const NotificationsStarted());
    await bloc.stream.firstWhere(
      (NotificationsState s) => s.status == NotificationsStatus.ready,
    );
    await bloc.close();

    expect(store.read(true)?.notifications, isEmpty);
    expect(
      store.isEmpty,
      isFalse,
      reason: 'a reader with no notifications should not refetch nothing',
    );
  });

  test('signing out empties it', () {
    final NotificationsSessionStore store = NotificationsSessionStore();

    store.write(
      true,
      NotificationsSessionSnapshot(
        notifications: <AppNotificationApiModel>[_item('a')],
        unreadCount: 1,
        page: 1,
        hasMore: false,
      ),
    );
    expect(store.isEmpty, isFalse);

    store.clear();

    expect(
      store.isEmpty,
      isTrue,
      reason:
          'the next person to sign in on a shared phone must not open the bell '
          'onto the last one notifications',
    );
  });

  test('the two audiences are held apart', () {
    final NotificationsSessionStore store = NotificationsSessionStore();

    store.write(
      true,
      NotificationsSessionSnapshot(
        notifications: <AppNotificationApiModel>[_item('shop')],
        unreadCount: 3,
        page: 1,
        hasMore: false,
      ),
    );

    expect(store.read(true)?.notifications.single.id, 'shop');
    expect(
      store.read(false),
      isNull,
      reason: 'a shop owner own inbox is a different list with its own count',
    );
  });

  group('a notification arriving', () {
    test('goes on top of the pages already scrolled through', () {
      final List<AppNotificationApiModel> held = <AppNotificationApiModel>[
        _item('b'),
        _item('c'),
        _item('d'),
      ];

      final List<AppNotificationApiModel> merged = mergeNotificationPageOne(
        held: held,
        fresh: <AppNotificationApiModel>[_item('new'), _item('b', read: true)],
      );

      expect(
        merged.map((AppNotificationApiModel n) => n.id),
        <String>['new', 'b', 'c', 'd'],
        reason:
            'replacing the list with page one threw away everything below it '
            'and sent a reader four pages deep back to the top',
      );
      expect(
        merged[1].isRead,
        isTrue,
        reason: 'and the server is the authority on what has been read',
      );
    });

    test('does not send the reader back to page one', () async {
      final _CountingApi api = _CountingApi(
        <int, List<AppNotificationApiModel>>{
          1: <AppNotificationApiModel>[_item('a')],
          2: <AppNotificationApiModel>[_item('b')],
        },
      );

      final NotificationsBloc bloc = _bloc(api);
      bloc.add(const NotificationsStarted());
      await bloc.stream.firstWhere(
        (NotificationsState s) => s.status == NotificationsStatus.ready,
      );

      bloc.add(const NotificationsLoadMoreRequested());
      await bloc.stream.firstWhere(
        (NotificationsState s) =>
            s.status == NotificationsStatus.ready && s.page == 2,
      );

      expect(bloc.state.notifications.length, 2);

      bloc.add(const NotificationsRealtimeSyncRequested());
      await bloc.stream.firstWhere(
        (NotificationsState s) => s.status == NotificationsStatus.ready,
      );

      expect(
        bloc.state.page,
        2,
        reason: 'the next load more has to ask for three, not for two again',
      );
      expect(
        bloc.state.notifications.map((AppNotificationApiModel n) => n.id),
        <String>['a', 'b'],
      );

      await bloc.close();
    });
  });
}
