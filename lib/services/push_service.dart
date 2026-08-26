import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/auth/auth_session_service.dart';
import '../core/config/firebase_readiness.dart';
import 'api_service.dart';

enum PushClientPlatform { android, ios, unsupported }

enum PushAuthorizationStatus { authorized, provisional, denied, notDetermined }

enum PushTapRouteKind { conversation, order, notifications }

final class PushTapIntent {
  final String notificationId;
  final String audience;
  final PushTapRouteKind routeKind;
  final String? conversationId;
  final String? orderId;

  const PushTapIntent({
    required this.notificationId,
    required this.audience,
    required this.routeKind,
    this.conversationId,
    this.orderId,
  });

  String get location {
    return switch (routeKind) {
      PushTapRouteKind.conversation => Uri(
        path: '/chat',
        queryParameters: {'conversationId': conversationId!},
      ).toString(),
      PushTapRouteKind.order =>
        '/orders/${Uri.encodeComponent(orderId!)}/tracking',
      PushTapRouteKind.notifications =>
        audience == 'business'
            ? '/notifications?audience=business'
            : '/notifications',
    };
  }
}

String? _pushDataValue(
  Map<String, dynamic> data,
  String key, {
  int maxLength = 512,
}) {
  final value = data[key];

  if (value is! String) {
    return null;
  }

  final normalized = value.trim();

  if (normalized.isEmpty ||
      normalized.length > maxLength ||
      normalized.contains('\u0000')) {
    return null;
  }

  return normalized;
}

PushTapIntent? parsePushTapIntent(Map<String, dynamic> data) {
  final notificationId = _pushDataValue(data, 'notificationId', maxLength: 256);

  final audience = _pushDataValue(data, 'audience', maxLength: 32);

  final routeKind = _pushDataValue(data, 'routeKind', maxLength: 32);

  if (notificationId == null ||
      audience == null ||
      (audience != 'customer' && audience != 'business') ||
      routeKind == null) {
    return null;
  }

  switch (routeKind) {
    case 'conversation':
      final conversationId = _pushDataValue(
        data,
        'conversationId',
        maxLength: 256,
      );

      if (conversationId == null) {
        return null;
      }

      return PushTapIntent(
        notificationId: notificationId,
        audience: audience,
        routeKind: PushTapRouteKind.conversation,
        conversationId: conversationId,
      );

    case 'order':
      final orderId = _pushDataValue(data, 'orderId', maxLength: 256);

      if (orderId == null) {
        return null;
      }

      return PushTapIntent(
        notificationId: notificationId,
        audience: audience,
        routeKind: PushTapRouteKind.order,
        orderId: orderId,
      );

    case 'notifications':
      return PushTapIntent(
        notificationId: notificationId,
        audience: audience,
        routeKind: PushTapRouteKind.notifications,
      );

    default:
      return null;
  }
}

abstract interface class PushSessionController {
  Future<void> prepareForStartup();

  Future<void> syncWithSession();

  Future<void> unregisterCurrentTarget();
}

abstract interface class PushMessagingClient {
  Future<PushAuthorizationStatus> requestPermission();

  Future<String?> getToken();

  Future<String?> getApnsToken();

  Stream<String> get tokenRefreshes;

  Future<Map<String, dynamic>?> getInitialMessageData();

  Stream<Map<String, dynamic>> get openedMessageData;
}

abstract interface class PushRegistrationStore {
  Future<String?> readTarget();

  Future<void> writeTarget(String target);

  Future<void> clearTarget();
}

class SharedPreferencesPushRegistrationStore implements PushRegistrationStore {
  static const String targetKey = 'push_registered_fcm_token';

  const SharedPreferencesPushRegistrationStore();

  @override
  Future<String?> readTarget() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(targetKey)?.trim();

    return value == null || value.isEmpty ? null : value;
  }

  @override
  Future<void> writeTarget(String target) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(targetKey, target);
  }

  @override
  Future<void> clearTarget() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(targetKey);
  }
}

typedef PushMessagingClientFactory = Future<PushMessagingClient> Function();
typedef PushPlatformResolver = PushClientPlatform Function();

PushClientPlatform _defaultPlatformResolver() {
  if (kIsWeb) {
    return PushClientPlatform.unsupported;
  }

  return switch (defaultTargetPlatform) {
    TargetPlatform.android => PushClientPlatform.android,
    TargetPlatform.iOS => PushClientPlatform.ios,
    _ => PushClientPlatform.unsupported,
  };
}

final class FirebasePushMessagingClient implements PushMessagingClient {
  final FirebaseMessaging _messaging;

  FirebasePushMessagingClient._(this._messaging);

  static Future<FirebasePushMessagingClient> create() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }

    return FirebasePushMessagingClient._(FirebaseMessaging.instance);
  }

  @override
  Future<PushAuthorizationStatus> requestPermission() async {
    final settings = await _messaging.requestPermission();

    return switch (settings.authorizationStatus) {
      AuthorizationStatus.authorized => PushAuthorizationStatus.authorized,
      AuthorizationStatus.provisional => PushAuthorizationStatus.provisional,
      AuthorizationStatus.denied => PushAuthorizationStatus.denied,
      AuthorizationStatus.notDetermined =>
        PushAuthorizationStatus.notDetermined,
    };
  }

  @override
  Future<String?> getToken() => _messaging.getToken();

  @override
  Future<String?> getApnsToken() => _messaging.getAPNSToken();

  @override
  Stream<String> get tokenRefreshes => _messaging.onTokenRefresh;

  @override
  Future<Map<String, dynamic>?> getInitialMessageData() async {
    final message = await _messaging.getInitialMessage();

    if (message == null) {
      return null;
    }

    return Map<String, dynamic>.from(message.data);
  }

  @override
  Stream<Map<String, dynamic>> get openedMessageData => FirebaseMessaging
      .onMessageOpenedApp
      .map((message) => Map<String, dynamic>.from(message.data));
}

class PushService implements PushSessionController {
  final AuthSessionService _authSessionService;
  final ApiService _apiService;
  final PushRegistrationStore _store;
  final PushMessagingClientFactory _clientFactory;
  final PushPlatformResolver _platformResolver;
  final bool _enabled;

  PushMessagingClient? _client;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<Map<String, dynamic>>? _openedMessageSubscription;

  final StreamController<PushTapIntent> _tapController =
      StreamController<PushTapIntent>.broadcast();

  final Set<String> _handledTapNotificationIds = <String>{};

  bool _tapConsumerAttached = false;
  bool _initialTapConsumed = false;

  String? _activeTarget;
  String? _activeSessionToken;

  Future<void> _operationTail = Future<void>.value();
  bool _closed = false;

  PushService({
    AuthSessionService authSessionService = const AuthSessionService(),
    ApiService? apiService,
    PushRegistrationStore store =
        const SharedPreferencesPushRegistrationStore(),
    PushMessagingClientFactory? clientFactory,
    PushPlatformResolver? platformResolver,
    bool? enabled,
  }) : _authSessionService = authSessionService,
       _apiService = apiService ?? ApiService(),
       _store = store,
       _clientFactory = clientFactory ?? FirebasePushMessagingClient.create,
       _platformResolver = platformResolver ?? _defaultPlatformResolver,
       _enabled = enabled ?? firebasePushRuntimeEnabled;
  bool get isEnabled => _enabled;

  Stream<PushTapIntent> get tapIntents => _tapController.stream;

  Future<void> startTapHandling() {
    return _serialize(_startTapHandlingUnsafe);
  }

  @override
  Future<void> prepareForStartup() {
    return _serialize(_prepareForStartupUnsafe);
  }

  @override
  Future<void> syncWithSession() {
    return _serialize(_syncWithSessionUnsafe);
  }

  @override
  Future<void> unregisterCurrentTarget() {
    return _serialize(_unregisterCurrentTargetUnsafe);
  }

  Future<void> _startTapHandlingUnsafe() async {
    if (_closed || !_enabled) {
      return;
    }

    _tapConsumerAttached = true;

    if (_platformResolver() == PushClientPlatform.unsupported) {
      return;
    }

    final session = await _authSessionService.read();

    if (!session.isAuthenticated) {
      return;
    }

    final client = await _ensureClient();

    if (client == null || _closed) {
      return;
    }

    _ensureOpenedMessageListening(client);
    await _consumeInitialMessage(client);
  }

  void _ensureOpenedMessageListening(PushMessagingClient client) {
    if (_openedMessageSubscription != null || _closed) {
      return;
    }

    _openedMessageSubscription = client.openedMessageData.listen(
      (data) {
        final intent = parsePushTapIntent(data);

        if (intent != null) {
          _emitTapIntent(intent);
        }
      },
      onError: (_) {
        // Tap transport is best-effort. REST-backed routes remain truth.
      },
    );
  }

  Future<void> _consumeInitialMessage(PushMessagingClient client) async {
    if (_initialTapConsumed || !_tapConsumerAttached || _closed) {
      return;
    }

    _initialTapConsumed = true;

    Map<String, dynamic>? data;

    try {
      data = await client.getInitialMessageData();
    } catch (_) {
      return;
    }

    if (data == null || _closed) {
      return;
    }

    final intent = parsePushTapIntent(data);

    if (intent != null) {
      _emitTapIntent(intent);
    }
  }

  void _emitTapIntent(PushTapIntent intent) {
    if (_closed) {
      return;
    }

    if (!_handledTapNotificationIds.add(intent.notificationId)) {
      return;
    }

    // Bound per-process dedupe memory while retaining the newest event.
    if (_handledTapNotificationIds.length > 256) {
      final newestId = intent.notificationId;

      _handledTapNotificationIds
        ..clear()
        ..add(newestId);
    }

    _tapController.add(intent);
  }

  Future<void> _prepareForStartupUnsafe() async {
    if (_closed || !_enabled) {
      return;
    }

    final shouldUnregister = await _authSessionService
        .hasUnrememberedAuthenticatedSession();

    if (!shouldUnregister) {
      return;
    }

    // This must happen before StartupService/readForStartup purges the JWT.
    await _unregisterCurrentTargetUnsafe();
  }

  Future<void> _syncWithSessionUnsafe() async {
    if (_closed || !_enabled) {
      return;
    }

    final platform = _platformResolver();

    if (platform == PushClientPlatform.unsupported) {
      return;
    }

    final session = await _authSessionService.read();
    final sessionToken = session.isAuthenticated ? session.token?.trim() : null;

    if (sessionToken == null || sessionToken.isEmpty) {
      await _stopRefreshListening();
      await _stopOpenedMessageListening();
      _activeTarget = null;
      _activeSessionToken = null;
      return;
    }

    final client = await _ensureClient();

    if (client == null || _closed) {
      return;
    }

    // App root subscribes first. If it is already attached, login/session sync
    // also restores background-open listening after a prior logout.
    if (_tapConsumerAttached) {
      _ensureOpenedMessageListening(client);
      await _consumeInitialMessage(client);
    }

    final authorization = await client.requestPermission();

    if (authorization != PushAuthorizationStatus.authorized &&
        authorization != PushAuthorizationStatus.provisional) {
      return;
    }

    if (platform == PushClientPlatform.ios) {
      final apnsToken = (await client.getApnsToken())?.trim();

      // Firebase requires the APNs token before FCM token API calls on Apple
      // platforms. A later authenticated sync may try again.
      if (apnsToken == null || apnsToken.isEmpty) {
        return;
      }
    }

    final target = (await client.getToken())?.trim();

    if (target == null || target.isEmpty) {
      return;
    }

    await _registerTarget(
      sessionToken: sessionToken,
      target: target,
      platform: platform,
    );

    _ensureRefreshListening(client);
  }

  Future<PushMessagingClient?> _ensureClient() async {
    final existing = _client;

    if (existing != null) {
      return existing;
    }

    try {
      final created = await _clientFactory();

      if (_closed) {
        return null;
      }

      _client = created;
      return created;
    } catch (_) {
      // Firebase config can intentionally be absent in development and tests.
      // Push must never block app startup or authentication.
      return null;
    }
  }

  void _ensureRefreshListening(PushMessagingClient client) {
    if (_tokenRefreshSubscription != null || _closed) {
      return;
    }

    _tokenRefreshSubscription = client.tokenRefreshes.listen(
      (target) {
        unawaited(_serialize(() => _handleTokenRefreshUnsafe(target)));
      },
      onError: (_) {
        // Token refresh is best-effort; the next authenticated app sync
        // re-registers the current token and refreshes lastSeenAt.
      },
    );
  }

  Future<void> _handleTokenRefreshUnsafe(String rawTarget) async {
    if (_closed || !_enabled) {
      return;
    }

    final target = rawTarget.trim();

    if (target.isEmpty) {
      return;
    }

    final platform = _platformResolver();

    if (platform == PushClientPlatform.unsupported) {
      return;
    }

    final session = await _authSessionService.read();
    final sessionToken = session.isAuthenticated ? session.token?.trim() : null;

    if (sessionToken == null || sessionToken.isEmpty) {
      return;
    }

    await _registerTarget(
      sessionToken: sessionToken,
      target: target,
      platform: platform,
    );
  }

  Future<void> _registerTarget({
    required String sessionToken,
    required String target,
    required PushClientPlatform platform,
  }) async {
    final oldTarget = _activeTarget ?? await _store.readTarget();
    final oldSessionToken = _activeSessionToken;

    try {
      await _apiService.registerPushTarget(
        token: sessionToken,
        target: target,
        platform: switch (platform) {
          PushClientPlatform.android => 'android',
          PushClientPlatform.ios => 'ios',
          PushClientPlatform.unsupported => throw StateError(
            'Unsupported push platform',
          ),
        },
      );
    } catch (_) {
      return;
    }

    _activeTarget = target;
    _activeSessionToken = sessionToken;
    await _store.writeTarget(target);

    // Register the fresh token first. Only after the server accepts it do we
    // attempt to retire the previous token for this same authenticated session.
    if (oldTarget != null &&
        oldTarget != target &&
        (oldSessionToken == null || oldSessionToken == sessionToken)) {
      try {
        await _apiService.unregisterPushTarget(
          token: sessionToken,
          target: oldTarget,
        );
      } catch (_) {
        // The backend can eventually remove a stale target after a terminal FCM
        // response. Never roll back the newly accepted registration.
      }
    }
  }

  Future<void> _unregisterCurrentTargetUnsafe() async {
    if (_closed || !_enabled) {
      return;
    }

    await _stopRefreshListening();
    await _stopOpenedMessageListening();

    final session = await _authSessionService.read();
    final sessionToken = session.isAuthenticated ? session.token?.trim() : null;

    if (sessionToken == null || sessionToken.isEmpty) {
      _activeTarget = null;
      _activeSessionToken = null;
      return;
    }

    final target = _activeTarget ?? await _store.readTarget();

    if (target == null || target.isEmpty) {
      _activeTarget = null;
      _activeSessionToken = null;
      return;
    }

    try {
      await _apiService.unregisterPushTarget(
        token: sessionToken,
        target: target,
      );

      await _store.clearTarget();
      _activeTarget = null;
      _activeSessionToken = null;
    } catch (_) {
      // Logout must continue even when unregister cannot reach the backend.
      // Keep the locally remembered target so a future authenticated session
      // can reconcile it rather than pretending cleanup succeeded.
    }
  }

  Future<void> _stopRefreshListening() async {
    final subscription = _tokenRefreshSubscription;
    _tokenRefreshSubscription = null;

    await subscription?.cancel();
  }

  Future<void> _stopOpenedMessageListening() async {
    final subscription = _openedMessageSubscription;
    _openedMessageSubscription = null;

    await subscription?.cancel();
  }

  Future<void> _serialize(Future<void> Function() operation) {
    final previous = _operationTail;

    final next = () async {
      try {
        await previous;
      } catch (_) {
        // One best-effort push operation must never poison the queue.
      }

      await operation();
    }();

    _operationTail = next;
    return next;
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }

    await _operationTail;

    _closed = true;
    await _stopRefreshListening();
    await _stopOpenedMessageListening();
    await _tapController.close();

    _client = null;
    _activeTarget = null;
    _activeSessionToken = null;
  }
}
