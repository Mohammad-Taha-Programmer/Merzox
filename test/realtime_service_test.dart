import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:merzox/services/realtime_service.dart';

class FakeAuthSessionService extends AuthSessionService {
  AuthSessionSnapshot snapshot;

  FakeAuthSessionService(this.snapshot);

  @override
  Future<AuthSessionSnapshot> read() async => snapshot;
}

class FakeRealtimeSocketClient implements RealtimeSocketClient {
  @override
  bool connected = false;

  int connectCalls = 0;
  int disconnectCalls = 0;
  int disposeCalls = 0;

  void Function(dynamic)? _connectHandler;
  void Function(dynamic)? _disconnectHandler;
  void Function(dynamic)? _connectErrorHandler;

  final Map<String, void Function(dynamic)> _eventHandlers = {};

  @override
  void onConnect(void Function(dynamic data) handler) {
    _connectHandler = handler;
  }

  @override
  void onDisconnect(void Function(dynamic data) handler) {
    _disconnectHandler = handler;
  }

  @override
  void onConnectError(void Function(dynamic data) handler) {
    _connectErrorHandler = handler;
  }

  @override
  void onEvent(String event, void Function(dynamic data) handler) {
    _eventHandlers[event] = handler;
  }

  @override
  void connect() {
    connectCalls += 1;
  }

  @override
  void disconnect() {
    disconnectCalls += 1;
    connected = false;
  }

  @override
  void dispose() {
    disposeCalls += 1;
  }

  void emitConnected() {
    connected = true;
    _connectHandler?.call(null);
  }

  void emitDisconnected() {
    connected = false;
    _disconnectHandler?.call(null);
  }

  void emitConnectError() {
    connected = false;
    _connectErrorHandler?.call('failed');
  }

  void emitEvent(String event, dynamic data) {
    _eventHandlers[event]?.call(data);
  }
}

class SocketFactoryRecord {
  final String serverUrl;
  final String token;
  final FakeRealtimeSocketClient client;

  const SocketFactoryRecord({
    required this.serverUrl,
    required this.token,
    required this.client,
  });
}

void main() {
  test('derives the realtime origin from the REST API base URL', () {
    expect(
      RealtimeService.serverUrlFromApiBaseUrl('http://127.0.0.1:4000/api/v1'),
      'http://127.0.0.1:4000',
    );

    expect(
      RealtimeService.serverUrlFromApiBaseUrl(
        'https://api.merzox.example/api/v1?x=1',
      ),
      'https://api.merzox.example',
    );

    expect(
      () => RealtimeService.serverUrlFromApiBaseUrl('not-a-url'),
      throwsArgumentError,
    );
  });

  test('an unauthenticated session never opens a socket', () async {
    final sessionService = FakeAuthSessionService(
      const AuthSessionSnapshot(type: AuthSessionType.unauthenticated),
    );

    var factoryCalls = 0;

    final service = RealtimeService(
      authSessionService: sessionService,
      serverUrl: 'http://127.0.0.1:4000',
      clientFactory: ({required serverUrl, required token}) {
        factoryCalls += 1;
        return FakeRealtimeSocketClient();
      },
    );

    addTearDown(service.close);

    await service.syncWithSession();

    expect(factoryCalls, 0);
    expect(service.connectionStatus, RealtimeConnectionStatus.disconnected);
  });

  test(
    'authenticated session connects with exactly its stored token',
    () async {
      final sessionService = FakeAuthSessionService(
        const AuthSessionSnapshot(
          type: AuthSessionType.customer,
          token: 'customer-token',
        ),
      );

      final records = <SocketFactoryRecord>[];

      final service = RealtimeService(
        authSessionService: sessionService,
        serverUrl: 'http://127.0.0.1:4000',
        clientFactory: ({required serverUrl, required token}) {
          final client = FakeRealtimeSocketClient();

          records.add(
            SocketFactoryRecord(
              serverUrl: serverUrl,
              token: token,
              client: client,
            ),
          );

          return client;
        },
      );

      addTearDown(service.close);

      await service.syncWithSession();

      expect(records, hasLength(1));
      expect(records.single.serverUrl, 'http://127.0.0.1:4000');
      expect(records.single.token, 'customer-token');
      expect(records.single.client.connectCalls, 1);
      expect(service.connectionStatus, RealtimeConnectionStatus.connecting);

      records.single.client.emitConnected();

      expect(service.connectionStatus, RealtimeConnectionStatus.connected);
      expect(service.isConnected, isTrue);
    },
  );

  test('same authenticated token reuses the current client', () async {
    final sessionService = FakeAuthSessionService(
      const AuthSessionSnapshot(
        type: AuthSessionType.customer,
        token: 'same-token',
      ),
    );

    final clients = <FakeRealtimeSocketClient>[];

    final service = RealtimeService(
      authSessionService: sessionService,
      serverUrl: 'http://127.0.0.1:4000',
      clientFactory: ({required serverUrl, required token}) {
        final client = FakeRealtimeSocketClient();
        clients.add(client);
        return client;
      },
    );

    addTearDown(service.close);

    await service.syncWithSession();

    clients.single.emitConnected();

    await service.syncWithSession();

    expect(clients, hasLength(1));
    expect(clients.single.connectCalls, 1);
  });

  test('token rotation disposes the old authenticated client', () async {
    final sessionService = FakeAuthSessionService(
      const AuthSessionSnapshot(
        type: AuthSessionType.customer,
        token: 'token-1',
      ),
    );

    final clients = <FakeRealtimeSocketClient>[];
    final tokens = <String>[];

    final service = RealtimeService(
      authSessionService: sessionService,
      serverUrl: 'http://127.0.0.1:4000',
      clientFactory: ({required serverUrl, required token}) {
        tokens.add(token);

        final client = FakeRealtimeSocketClient();
        clients.add(client);
        return client;
      },
    );

    addTearDown(service.close);

    await service.syncWithSession();

    final first = clients.single;

    sessionService.snapshot = const AuthSessionSnapshot(
      type: AuthSessionType.business,
      token: 'token-2',
    );

    await service.syncWithSession();

    expect(tokens, ['token-1', 'token-2']);
    expect(clients, hasLength(2));
    expect(first.disconnectCalls, 1);
    expect(first.disposeCalls, 1);
    expect(clients.last.connectCalls, 1);
  });

  test('logout disconnects and destroys authenticated transport', () async {
    final sessionService = FakeAuthSessionService(
      const AuthSessionSnapshot(type: AuthSessionType.customer, token: 'token'),
    );

    late FakeRealtimeSocketClient client;

    final service = RealtimeService(
      authSessionService: sessionService,
      serverUrl: 'http://127.0.0.1:4000',
      clientFactory: ({required serverUrl, required token}) {
        client = FakeRealtimeSocketClient();
        return client;
      },
    );

    addTearDown(service.close);

    await service.syncWithSession();

    sessionService.snapshot = const AuthSessionSnapshot(
      type: AuthSessionType.unauthenticated,
    );

    await service.syncWithSession();

    expect(client.disconnectCalls, 1);
    expect(client.disposeCalls, 1);
    expect(service.connectionStatus, RealtimeConnectionStatus.disconnected);
  });

  test('events from an obsolete token cannot change current status', () async {
    final sessionService = FakeAuthSessionService(
      const AuthSessionSnapshot(
        type: AuthSessionType.customer,
        token: 'token-1',
      ),
    );

    final clients = <FakeRealtimeSocketClient>[];

    final service = RealtimeService(
      authSessionService: sessionService,
      serverUrl: 'http://127.0.0.1:4000',
      clientFactory: ({required serverUrl, required token}) {
        final client = FakeRealtimeSocketClient();
        clients.add(client);
        return client;
      },
    );

    addTearDown(service.close);

    await service.syncWithSession();

    final obsolete = clients.single;

    sessionService.snapshot = const AuthSessionSnapshot(
      type: AuthSessionType.customer,
      token: 'token-2',
    );

    await service.syncWithSession();

    final current = clients.last;
    current.emitConnected();

    obsolete.emitConnectError();
    obsolete.emitDisconnected();

    expect(service.connectionStatus, RealtimeConnectionStatus.connected);
  });

  test('message invalidation parses the stable backend payload', () {
    final event = RealtimeMessageInvalidation.tryParse({
      'conversationId': 'conversation-1',
      'businessId': 'business-1',
      'messageId': 'message-1',
      'reason': 'message-created',
    });

    expect(event, isNotNull);
    expect(event!.conversationId, 'conversation-1');
    expect(event.businessId, 'business-1');
    expect(event.messageId, 'message-1');
    expect(event.reason, 'message-created');
  });

  test('conversation-read invalidation does not require a message id', () {
    final event = RealtimeMessageInvalidation.tryParse({
      'conversationId': 'conversation-1',
      'businessId': 'business-1',
      'reason': 'conversation-read',
    });

    expect(event, isNotNull);
    expect(event!.messageId, isNull);
    expect(event.reason, 'conversation-read');
  });

  test('malformed or unknown message invalidations are ignored', () {
    expect(RealtimeMessageInvalidation.tryParse('not-a-map'), isNull);

    expect(
      RealtimeMessageInvalidation.tryParse({
        'conversationId': '',
        'businessId': 'business-1',
        'messageId': 'message-1',
        'reason': 'message-created',
      }),
      isNull,
    );

    expect(
      RealtimeMessageInvalidation.tryParse({
        'conversationId': 'conversation-1',
        'businessId': 'business-1',
        'reason': 'message-created',
      }),
      isNull,
    );

    expect(
      RealtimeMessageInvalidation.tryParse({
        'conversationId': 'conversation-1',
        'businessId': 'business-1',
        'reason': 'unknown-event',
      }),
      isNull,
    );
  });

  test('active client publishes typed message invalidations', () async {
    final sessionService = FakeAuthSessionService(
      const AuthSessionSnapshot(type: AuthSessionType.customer, token: 'token'),
    );

    late FakeRealtimeSocketClient client;

    final service = RealtimeService(
      authSessionService: sessionService,
      serverUrl: 'http://127.0.0.1:4000',
      clientFactory: ({required serverUrl, required token}) {
        client = FakeRealtimeSocketClient();
        return client;
      },
    );

    addTearDown(service.close);

    await service.syncWithSession();

    final next = service.messageInvalidations.first;

    client.emitEvent(RealtimeService.messagesChangedEvent, {
      'conversationId': 'conversation-1',
      'businessId': 'business-1',
      'messageId': 'message-1',
      'reason': 'message-created',
    });

    final event = await next;

    expect(event.conversationId, 'conversation-1');
    expect(event.messageId, 'message-1');
  });

  test('obsolete authenticated client cannot publish message events', () async {
    final sessionService = FakeAuthSessionService(
      const AuthSessionSnapshot(
        type: AuthSessionType.customer,
        token: 'token-1',
      ),
    );

    final clients = <FakeRealtimeSocketClient>[];

    final service = RealtimeService(
      authSessionService: sessionService,
      serverUrl: 'http://127.0.0.1:4000',
      clientFactory: ({required serverUrl, required token}) {
        final client = FakeRealtimeSocketClient();

        clients.add(client);
        return client;
      },
    );

    addTearDown(service.close);

    await service.syncWithSession();

    final obsolete = clients.single;

    sessionService.snapshot = const AuthSessionSnapshot(
      type: AuthSessionType.customer,
      token: 'token-2',
    );

    await service.syncWithSession();

    final received = <RealtimeMessageInvalidation>[];

    final subscription = service.messageInvalidations.listen(received.add);

    addTearDown(subscription.cancel);

    obsolete.emitEvent(RealtimeService.messagesChangedEvent, {
      'conversationId': 'old-conversation',
      'businessId': 'business-1',
      'messageId': 'old-message',
      'reason': 'message-created',
    });

    await Future<void>.delayed(Duration.zero);

    expect(received, isEmpty);
  });

  test('notification invalidation parses the stable backend payload', () {
    final event = RealtimeNotificationInvalidation.tryParse({
      'audience': 'business',
      'reason': 'notification-created',
      'notificationId': 'notification-1',
      'businessId': 'business-1',
    });

    expect(event, isNotNull);
    expect(event!.audience, 'business');
    expect(event.reason, 'notification-created');
    expect(event.notificationId, 'notification-1');
    expect(event.businessId, 'business-1');
  });

  test('notification read-all invalidation needs no notification id', () {
    final event = RealtimeNotificationInvalidation.tryParse({
      'audience': 'customer',
      'reason': 'notifications-read-all',
    });

    expect(event, isNotNull);
    expect(event!.notificationId, isNull);
  });

  test('malformed notification invalidations are rejected', () {
    expect(
      RealtimeNotificationInvalidation.tryParse({
        'audience': 'admin',
        'reason': 'notification-created',
        'notificationId': 'n1',
      }),
      isNull,
    );

    expect(
      RealtimeNotificationInvalidation.tryParse({
        'audience': 'customer',
        'reason': 'unknown',
        'notificationId': 'n1',
      }),
      isNull,
    );

    expect(
      RealtimeNotificationInvalidation.tryParse({
        'audience': 'customer',
        'reason': 'notification-created',
      }),
      isNull,
    );
  });

  test('active client publishes typed notification invalidations', () async {
    final sessionService = FakeAuthSessionService(
      const AuthSessionSnapshot(type: AuthSessionType.customer, token: 'token'),
    );

    late FakeRealtimeSocketClient client;

    final service = RealtimeService(
      authSessionService: sessionService,
      serverUrl: 'http://127.0.0.1:4000',
      clientFactory: ({required serverUrl, required token}) {
        client = FakeRealtimeSocketClient();
        return client;
      },
    );

    addTearDown(service.close);

    await service.syncWithSession();

    final next = service.notificationInvalidations.first;

    client.emitEvent(RealtimeService.notificationsChangedEvent, {
      'audience': 'customer',
      'reason': 'notification-created',
      'notificationId': 'n1',
    });

    final event = await next;

    expect(event.notificationId, 'n1');

    expect(event.audience, 'customer');
  });
}
