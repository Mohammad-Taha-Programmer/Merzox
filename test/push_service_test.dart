import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:merzox/services/api_service.dart';
import 'package:merzox/services/push_service.dart';

final class _MutableSessionService extends AuthSessionService {
  AuthSessionSnapshot snapshot;
  bool unrememberedAuthenticatedSession = false;

  _MutableSessionService(this.snapshot);

  @override
  Future<AuthSessionSnapshot> read() async => snapshot;

  @override
  Future<bool> hasUnrememberedAuthenticatedSession() async =>
      unrememberedAuthenticatedSession;
}

final class _FakeStore implements PushRegistrationStore {
  String? target;

  @override
  Future<void> clearTarget() async {
    target = null;
  }

  @override
  Future<String?> readTarget() async => target;

  @override
  Future<void> writeTarget(String value) async {
    target = value;
  }
}

final class _RegistrationCall {
  final String token;
  final String target;
  final String? platform;

  const _RegistrationCall({
    required this.token,
    required this.target,
    this.platform,
  });
}

final class _SpyApi extends ApiService {
  final List<_RegistrationCall> registrations = [];
  final List<_RegistrationCall> unregistrations = [];

  bool failRegister = false;
  bool failUnregister = false;

  @override
  Future<void> registerPushTarget({
    required String token,
    required String target,
    required String platform,
  }) async {
    if (failRegister) {
      throw StateError('register failed');
    }

    registrations.add(
      _RegistrationCall(token: token, target: target, platform: platform),
    );
  }

  @override
  Future<void> unregisterPushTarget({
    required String token,
    required String target,
  }) async {
    if (failUnregister) {
      throw StateError('unregister failed');
    }

    unregistrations.add(_RegistrationCall(token: token, target: target));
  }
}

final class _FakeMessagingClient implements PushMessagingClient {
  PushAuthorizationStatus authorization = PushAuthorizationStatus.authorized;

  String? token = 'fcm-token-1';
  String? apnsToken = 'apns-token-1';

  int permissionCalls = 0;
  int tokenCalls = 0;
  int apnsCalls = 0;

  final StreamController<String> refreshController =
      StreamController<String>.broadcast();

  final StreamController<Map<String, dynamic>> openedMessageController =
      StreamController<Map<String, dynamic>>.broadcast();

  Map<String, dynamic>? initialMessageData;

  @override
  Future<String?> getApnsToken() async {
    apnsCalls += 1;
    return apnsToken;
  }

  @override
  Future<String?> getToken() async {
    tokenCalls += 1;
    return token;
  }

  @override
  Future<PushAuthorizationStatus> requestPermission() async {
    permissionCalls += 1;
    return authorization;
  }

  @override
  Stream<String> get tokenRefreshes => refreshController.stream;

  @override
  Future<Map<String, dynamic>?> getInitialMessageData() async =>
      initialMessageData;

  @override
  Stream<Map<String, dynamic>> get openedMessageData =>
      openedMessageController.stream;

  Future<void> close() async {
    await refreshController.close();
    await openedMessageController.close();
  }
}

Future<void> _drainAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  const customerSession = AuthSessionSnapshot(
    type: AuthSessionType.customer,
    token: 'jwt-customer',
  );

  test(
    'disabled push does not construct Firebase client or touch API',
    () async {
      final session = _MutableSessionService(customerSession);
      final api = _SpyApi();

      var factoryCalls = 0;

      final service = PushService(
        authSessionService: session,
        apiService: api,
        store: _FakeStore(),
        enabled: false,
        platformResolver: () => PushClientPlatform.android,
        clientFactory: () async {
          factoryCalls += 1;
          return _FakeMessagingClient();
        },
      );

      await service.syncWithSession();

      expect(factoryCalls, 0);
      expect(api.registrations, isEmpty);

      await service.close();
    },
  );

  test('unsupported platform performs no Firebase or API work', () async {
    final api = _SpyApi();

    var factoryCalls = 0;

    final service = PushService(
      authSessionService: _MutableSessionService(customerSession),
      apiService: api,
      store: _FakeStore(),
      enabled: true,
      platformResolver: () => PushClientPlatform.unsupported,
      clientFactory: () async {
        factoryCalls += 1;
        return _FakeMessagingClient();
      },
    );

    await service.syncWithSession();

    expect(factoryCalls, 0);
    expect(api.registrations, isEmpty);

    await service.close();
  });

  test(
    'unauthenticated session never requests permission or registration',
    () async {
      final client = _FakeMessagingClient();
      final api = _SpyApi();

      final service = PushService(
        authSessionService: _MutableSessionService(
          const AuthSessionSnapshot(type: AuthSessionType.unauthenticated),
        ),
        apiService: api,
        store: _FakeStore(),
        enabled: true,
        platformResolver: () => PushClientPlatform.android,
        clientFactory: () async => client,
      );

      await service.syncWithSession();

      expect(client.permissionCalls, 0);
      expect(api.registrations, isEmpty);

      await service.close();
      await client.close();
    },
  );

  test(
    'authenticated Android session registers FCM token as token target',
    () async {
      final client = _FakeMessagingClient();
      final api = _SpyApi();
      final store = _FakeStore();

      final service = PushService(
        authSessionService: _MutableSessionService(customerSession),
        apiService: api,
        store: store,
        enabled: true,
        platformResolver: () => PushClientPlatform.android,
        clientFactory: () async => client,
      );

      await service.syncWithSession();

      expect(client.permissionCalls, 1);
      expect(client.apnsCalls, 0);
      expect(client.tokenCalls, 1);

      expect(api.registrations, hasLength(1));
      expect(api.registrations.single.token, 'jwt-customer');
      expect(api.registrations.single.target, 'fcm-token-1');
      expect(api.registrations.single.platform, 'android');
      expect(store.target, 'fcm-token-1');

      await service.close();
      await client.close();
    },
  );

  test(
    'denied notification permission prevents token request and registration',
    () async {
      final client = _FakeMessagingClient()
        ..authorization = PushAuthorizationStatus.denied;

      final api = _SpyApi();

      final service = PushService(
        authSessionService: _MutableSessionService(customerSession),
        apiService: api,
        store: _FakeStore(),
        enabled: true,
        platformResolver: () => PushClientPlatform.android,
        clientFactory: () async => client,
      );

      await service.syncWithSession();

      expect(client.permissionCalls, 1);
      expect(client.tokenCalls, 0);
      expect(api.registrations, isEmpty);

      await service.close();
      await client.close();
    },
  );

  test('iOS waits for APNs token before invoking FCM getToken', () async {
    final client = _FakeMessagingClient()..apnsToken = null;
    final api = _SpyApi();

    final service = PushService(
      authSessionService: _MutableSessionService(customerSession),
      apiService: api,
      store: _FakeStore(),
      enabled: true,
      platformResolver: () => PushClientPlatform.ios,
      clientFactory: () async => client,
    );

    await service.syncWithSession();

    expect(client.permissionCalls, 1);
    expect(client.apnsCalls, 1);
    expect(client.tokenCalls, 0);
    expect(api.registrations, isEmpty);

    await service.close();
    await client.close();
  });

  test('iOS registers token after APNs readiness', () async {
    final client = _FakeMessagingClient();
    final api = _SpyApi();

    final service = PushService(
      authSessionService: _MutableSessionService(customerSession),
      apiService: api,
      store: _FakeStore(),
      enabled: true,
      platformResolver: () => PushClientPlatform.ios,
      clientFactory: () async => client,
    );

    await service.syncWithSession();

    expect(client.apnsCalls, 1);
    expect(client.tokenCalls, 1);
    expect(api.registrations.single.platform, 'ios');

    await service.close();
    await client.close();
  });

  test(
    'token refresh registers new token before retiring previous token',
    () async {
      final client = _FakeMessagingClient();
      final api = _SpyApi();
      final store = _FakeStore();

      final service = PushService(
        authSessionService: _MutableSessionService(customerSession),
        apiService: api,
        store: store,
        enabled: true,
        platformResolver: () => PushClientPlatform.android,
        clientFactory: () async => client,
      );

      await service.syncWithSession();

      client.refreshController.add('fcm-token-2');
      await _drainAsync();

      expect(api.registrations.map((call) => call.target).toList(), [
        'fcm-token-1',
        'fcm-token-2',
      ]);

      expect(api.unregistrations, hasLength(1));
      expect(api.unregistrations.single.target, 'fcm-token-1');
      expect(store.target, 'fcm-token-2');

      await service.close();
      await client.close();
    },
  );

  test(
    'failed refreshed registration never removes the previously valid target',
    () async {
      final client = _FakeMessagingClient();
      final api = _SpyApi();
      final store = _FakeStore();

      final service = PushService(
        authSessionService: _MutableSessionService(customerSession),
        apiService: api,
        store: store,
        enabled: true,
        platformResolver: () => PushClientPlatform.android,
        clientFactory: () async => client,
      );

      await service.syncWithSession();

      api.failRegister = true;
      client.refreshController.add('fcm-token-2');

      await _drainAsync();

      expect(api.unregistrations, isEmpty);
      expect(store.target, 'fcm-token-1');

      await service.close();
      await client.close();
    },
  );

  test(
    'logout unregister uses the still-authenticated session token',
    () async {
      final client = _FakeMessagingClient();
      final api = _SpyApi();
      final store = _FakeStore();

      final session = _MutableSessionService(customerSession);

      final service = PushService(
        authSessionService: session,
        apiService: api,
        store: store,
        enabled: true,
        platformResolver: () => PushClientPlatform.android,
        clientFactory: () async => client,
      );

      await service.syncWithSession();
      await service.unregisterCurrentTarget();

      expect(api.unregistrations, hasLength(1));
      expect(api.unregistrations.single.token, 'jwt-customer');
      expect(api.unregistrations.single.target, 'fcm-token-1');
      expect(store.target, isNull);

      await service.close();
      await client.close();
    },
  );

  test(
    'failed logout unregister keeps local target for later reconciliation',
    () async {
      final client = _FakeMessagingClient();
      final api = _SpyApi();
      final store = _FakeStore();

      final service = PushService(
        authSessionService: _MutableSessionService(customerSession),
        apiService: api,
        store: store,
        enabled: true,
        platformResolver: () => PushClientPlatform.android,
        clientFactory: () async => client,
      );

      await service.syncWithSession();

      api.failUnregister = true;
      await service.unregisterCurrentTarget();

      expect(store.target, 'fcm-token-1');

      await service.close();
      await client.close();
    },
  );

  test('Firebase client initialization failure is swallowed', () async {
    final api = _SpyApi();

    final service = PushService(
      authSessionService: _MutableSessionService(customerSession),
      apiService: api,
      store: _FakeStore(),
      enabled: true,
      platformResolver: () => PushClientPlatform.android,
      clientFactory: () async {
        throw StateError('Firebase config unavailable');
      },
    );

    await service.syncWithSession();

    expect(api.registrations, isEmpty);

    await service.close();
  });
  test(
    'prepareForStartup unregisters an unremembered authenticated target before purge',
    () async {
      final session = _MutableSessionService(customerSession)
        ..unrememberedAuthenticatedSession = true;

      final api = _SpyApi();
      final store = _FakeStore()..target = 'old-fcm-target-123456';

      var factoryCalls = 0;

      final service = PushService(
        authSessionService: session,
        apiService: api,
        store: store,
        enabled: true,
        platformResolver: () => PushClientPlatform.android,
        clientFactory: () async {
          factoryCalls += 1;
          return _FakeMessagingClient();
        },
      );

      await service.prepareForStartup();

      expect(factoryCalls, 0);
      expect(api.unregistrations, hasLength(1));
      expect(api.unregistrations.single.token, 'jwt-customer');
      expect(api.unregistrations.single.target, 'old-fcm-target-123456');
      expect(store.target, isNull);

      await service.close();
    },
  );

  test('prepareForStartup leaves a remembered session untouched', () async {
    final session = _MutableSessionService(customerSession)
      ..unrememberedAuthenticatedSession = false;

    final api = _SpyApi();
    final store = _FakeStore()..target = 'remembered-target-123456';

    final service = PushService(
      authSessionService: session,
      apiService: api,
      store: store,
      enabled: true,
      platformResolver: () => PushClientPlatform.android,
    );

    await service.prepareForStartup();

    expect(api.unregistrations, isEmpty);
    expect(store.target, 'remembered-target-123456');

    await service.close();
  });
}
