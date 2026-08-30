import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/business/shell/merchant_alert_bloc.dart';
import 'package:merzox/services/api_service.dart';
import 'package:merzox/services/realtime_service.dart';

import 'auth_session_fixtures.dart';

/// The in-app banner of `الرئيسية – 17`.
///
/// The socket says only that this audience's notifications changed, so the
/// bloc reads the newest unread one to find out what the strip should say.
/// The claims worth holding: opening the shell announces nothing, a genuinely
/// new notification announces once, and a replayed invalidation announces
/// nothing again.

Map<String, dynamic> _notification(String id, {String title = 'عنوان'}) =>
    <String, dynamic>{
      'id': id,
      'type': 'review',
      'title': title,
      'body': 'نص',
      'data': const <String, dynamic>{},
      'isRead': false,
      'createdAt': '2022-02-15T14:40:00.000Z',
    };

class _NotificationApi extends ApiService {
  /// Newest first, as the endpoint returns them.
  List<Map<String, dynamic>> stored = const <Map<String, dynamic>>[];
  int reads = 0;
  bool fail = false;

  @override
  Future<NotificationListApiResponse> notifications({
    required String token,
    bool businessAudience = false,
    bool unreadOnly = false,
    int page = 1,
    int limit = 20,
  }) async {
    reads++;
    if (fail) throw StateError('offline');

    return NotificationListApiResponse.fromJson(<String, dynamic>{
      'notifications': stored.take(limit).toList(),
      'unreadCount': stored.length,
      'pagination': const <String, dynamic>{'page': 1, 'hasMore': false},
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _NotificationApi api;
  late StreamController<RealtimeNotificationInvalidation> socket;

  setUp(() {
    api = _NotificationApi();
    socket = StreamController<RealtimeNotificationInvalidation>.broadcast();
    useAuthenticatedSession(business: true);
  });

  tearDown(() => socket.close());

  MerchantAlertBloc build() {
    final MerchantAlertBloc bloc = MerchantAlertBloc(
      apiService: api,
      realtimeInvalidations: socket.stream,
    );
    addTearDown(bloc.close);
    return bloc;
  }

  Future<void> started(MerchantAlertBloc bloc) async {
    bloc.add(const MerchantAlertStarted());
    await bloc.stream.first.timeout(
      const Duration(seconds: 2),
      onTimeout: () => bloc.state,
    );
  }

  void arrive({String audience = 'business'}) => socket.add(
    RealtimeNotificationInvalidation(audience: audience, reason: 'created'),
  );

  Future<MerchantAlertState> nextState(MerchantAlertBloc bloc) => bloc
      .stream
      .first
      .timeout(const Duration(seconds: 2), onTimeout: () => bloc.state);

  test('opening the shell announces nothing that was already there', () async {
    api.stored = <Map<String, dynamic>>[_notification('n1')];

    final MerchantAlertBloc bloc = build();
    await started(bloc);

    // Yesterday's unread notification is not news.
    expect(bloc.state.message, isNull);
    expect(bloc.state.lastSeenId, 'n1');
  });

  test('a notification that arrives while watching is announced', () async {
    api.stored = <Map<String, dynamic>>[_notification('n1')];
    final MerchantAlertBloc bloc = build();
    await started(bloc);

    api.stored = <Map<String, dynamic>>[
      _notification('n2', title: 'قامت ياسمين خالد بتقييم المتجر'),
      _notification('n1'),
    ];
    arrive();
    await nextState(bloc);

    expect(bloc.state.message, 'قامت ياسمين خالد بتقييم المتجر');
    expect(bloc.state.lastSeenId, 'n2');
  });

  test('a repeated invalidation does not announce twice', () async {
    api.stored = <Map<String, dynamic>>[_notification('n1')];
    final MerchantAlertBloc bloc = build();
    await started(bloc);

    api.stored = <Map<String, dynamic>>[_notification('n2'), ...api.stored];
    arrive();
    await nextState(bloc);
    expect(bloc.state.message, isNotNull);

    bloc.add(const MerchantAlertDismissed());
    await nextState(bloc);

    // A reconnect replays the invalidation; the same notification must not
    // come back as if it were new.
    arrive();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(bloc.state.message, isNull);
  });

  test(
    'a customer-audience invalidation is not this bloc\'s business',
    () async {
      api.stored = <Map<String, dynamic>>[_notification('n1')];
      final MerchantAlertBloc bloc = build();
      await started(bloc);

      final int before = api.reads;
      arrive(audience: 'customer');
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(api.reads, before);
      expect(bloc.state.message, isNull);
    },
  );

  test('a failed read shows no banner rather than an empty one', () async {
    final MerchantAlertBloc bloc = build();
    await started(bloc);

    api.fail = true;
    arrive();
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(bloc.state.message, isNull);
  });

  test('a notification with no title falls back to its body', () async {
    final MerchantAlertBloc bloc = build();
    await started(bloc);

    api.stored = <Map<String, dynamic>>[
      <String, dynamic>{..._notification('n9'), 'title': '', 'body': 'نص بديل'},
    ];
    arrive();
    await nextState(bloc);

    expect(bloc.state.message, 'نص بديل');
  });
}
