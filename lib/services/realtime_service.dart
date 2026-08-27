import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import '../core/auth/auth_session_service.dart';
import 'api_service.dart';

enum RealtimeConnectionStatus { disconnected, connecting, connected }

final class RealtimeMessageInvalidation {
  final String conversationId;
  final String businessId;
  final String? messageId;
  final String reason;

  const RealtimeMessageInvalidation({
    required this.conversationId,
    required this.businessId,
    required this.reason,
    this.messageId,
  });

  static RealtimeMessageInvalidation? tryParse(dynamic data) {
    if (data is! Map) {
      return null;
    }

    String value(String key) => data[key]?.toString().trim() ?? '';

    final conversationId = value('conversationId');
    final businessId = value('businessId');
    final messageId = value('messageId');
    final reason = value('reason');

    if (conversationId.isEmpty || businessId.isEmpty || reason.isEmpty) {
      return null;
    }

    if (reason != 'message-created' && reason != 'conversation-read') {
      return null;
    }

    if (reason == 'message-created' && messageId.isEmpty) {
      return null;
    }

    return RealtimeMessageInvalidation(
      conversationId: conversationId,
      businessId: businessId,
      reason: reason,
      messageId: messageId.isEmpty ? null : messageId,
    );
  }
}

final class RealtimeNotificationInvalidation {
  final String audience;
  final String reason;
  final String? notificationId;
  final String? businessId;

  const RealtimeNotificationInvalidation({
    required this.audience,
    required this.reason,
    this.notificationId,
    this.businessId,
  });

  static RealtimeNotificationInvalidation? tryParse(dynamic data) {
    if (data is! Map) {
      return null;
    }

    String value(String key) => data[key]?.toString().trim() ?? '';

    final audience = value('audience');
    final reason = value('reason');
    final notificationId = value('notificationId');
    final businessId = value('businessId');

    if (audience != 'customer' && audience != 'business') {
      return null;
    }

    if (reason != 'notification-created' &&
        reason != 'notification-read' &&
        reason != 'notifications-read-all') {
      return null;
    }

    if ((reason == 'notification-created' || reason == 'notification-read') &&
        notificationId.isEmpty) {
      return null;
    }

    return RealtimeNotificationInvalidation(
      audience: audience,
      reason: reason,
      notificationId: notificationId.isEmpty ? null : notificationId,
      businessId: businessId.isEmpty ? null : businessId,
    );
  }
}

final class RealtimeOrderTrackingInvalidation {
  final String orderId;
  final String reason;

  const RealtimeOrderTrackingInvalidation({
    required this.orderId,
    required this.reason,
  });

  static RealtimeOrderTrackingInvalidation? tryParse(dynamic data) {
    if (data is! Map) {
      return null;
    }

    final orderId = data['orderId']?.toString().trim() ?? '';

    final reason = data['reason']?.toString().trim() ?? '';

    if (data.length != 2 ||
        !data.containsKey('orderId') ||
        !data.containsKey('reason') ||
        data.keys.any((key) => key != 'orderId' && key != 'reason') ||
        orderId.isEmpty ||
        orderId.length > 256 ||
        (reason != 'courier-location-updated' &&
            reason != 'courier-location-cleared' &&
            reason != 'order-status-changed')) {
      return null;
    }

    return RealtimeOrderTrackingInvalidation(orderId: orderId, reason: reason);
  }
}

abstract interface class RealtimeSessionController {
  Future<void> syncWithSession();

  Future<void> disconnect();
}

abstract interface class RealtimeSocketClient {
  bool get connected;

  void onConnect(void Function(dynamic data) handler);

  void onDisconnect(void Function(dynamic data) handler);

  void onConnectError(void Function(dynamic data) handler);

  void onEvent(String event, void Function(dynamic data) handler);

  void connect();

  void disconnect();

  void dispose();
}

typedef RealtimeSocketFactory =
    RealtimeSocketClient Function({
      required String serverUrl,
      required String token,
    });

RealtimeSocketClient _createSocketIoClient({
  required String serverUrl,
  required String token,
}) {
  return SocketIoRealtimeClient(serverUrl: serverUrl, token: token);
}

class SocketIoRealtimeClient implements RealtimeSocketClient {
  final io.Socket _socket;

  SocketIoRealtimeClient({required String serverUrl, required String token})
    : _socket = io.io(
        serverUrl,
        io.OptionBuilder()
            .setTransports(['websocket'])
            .disableAutoConnect()
            .enableReconnection()
            // socket_io_client caches managers by host. A new authenticated
            // session must never inherit the previous session's handshake.
            .enableForceNew()
            .setAuth({'token': token})
            .build(),
      );

  @override
  bool get connected => _socket.connected;

  @override
  void onConnect(void Function(dynamic data) handler) {
    _socket.onConnect(handler);
  }

  @override
  void onDisconnect(void Function(dynamic data) handler) {
    _socket.onDisconnect(handler);
  }

  @override
  void onConnectError(void Function(dynamic data) handler) {
    _socket.onConnectError(handler);
  }

  @override
  void onEvent(String event, void Function(dynamic data) handler) {
    _socket.on(event, handler);
  }

  @override
  void connect() {
    _socket.connect();
  }

  @override
  void disconnect() {
    _socket.disconnect();
  }

  @override
  void dispose() {
    _socket.dispose();
  }
}

class RealtimeService implements RealtimeSessionController {
  static const messagesChangedEvent = 'merzox:messages-changed';
  static const notificationsChangedEvent = 'merzox:notifications-changed';
  static const orderTrackingChangedEvent = 'merzox:order-tracking-changed';

  final AuthSessionService _authSessionService;
  final RealtimeSocketFactory _clientFactory;
  final String _serverUrl;

  final StreamController<RealtimeConnectionStatus> _connectionStatusController =
      StreamController<RealtimeConnectionStatus>.broadcast();

  final StreamController<RealtimeMessageInvalidation>
  _messageInvalidationController =
      StreamController<RealtimeMessageInvalidation>.broadcast();

  final StreamController<RealtimeNotificationInvalidation>
  _notificationInvalidationController =
      StreamController<RealtimeNotificationInvalidation>.broadcast();

  final StreamController<RealtimeOrderTrackingInvalidation>
  _orderTrackingInvalidationController =
      StreamController<RealtimeOrderTrackingInvalidation>.broadcast();

  RealtimeSocketClient? _client;
  String? _activeToken;

  RealtimeConnectionStatus _connectionStatus =
      RealtimeConnectionStatus.disconnected;

  RealtimeService({
    AuthSessionService authSessionService = const AuthSessionService(),
    RealtimeSocketFactory? clientFactory,
    String? serverUrl,
  }) : _authSessionService = authSessionService,
       _clientFactory = clientFactory ?? _createSocketIoClient,
       _serverUrl =
           serverUrl ?? serverUrlFromApiBaseUrl(ApiService.defaultBaseUrl);

  RealtimeConnectionStatus get connectionStatus => _connectionStatus;

  Stream<RealtimeConnectionStatus> get connectionStatuses =>
      _connectionStatusController.stream;

  Stream<RealtimeMessageInvalidation> get messageInvalidations =>
      _messageInvalidationController.stream;

  Stream<RealtimeNotificationInvalidation> get notificationInvalidations =>
      _notificationInvalidationController.stream;

  Stream<RealtimeOrderTrackingInvalidation> get orderTrackingInvalidations =>
      _orderTrackingInvalidationController.stream;

  bool get isConnected =>
      _connectionStatus == RealtimeConnectionStatus.connected;

  String get serverUrl => _serverUrl;

  static String serverUrlFromApiBaseUrl(String apiBaseUrl) {
    final value = apiBaseUrl.trim();
    final uri = Uri.tryParse(value);

    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw ArgumentError.value(
        apiBaseUrl,
        'apiBaseUrl',
        'A valid HTTP(S) API base URL is required',
      );
    }

    return uri.origin;
  }

  @override
  Future<void> syncWithSession() async {
    final session = await _authSessionService.read();

    final token = session.isAuthenticated ? session.token?.trim() : null;

    if (token == null || token.isEmpty) {
      await disconnect();
      return;
    }

    await connectWithToken(token);
  }

  Future<void> connectWithToken(String token) async {
    final normalizedToken = token.trim();

    if (normalizedToken.isEmpty) {
      await disconnect();
      return;
    }

    final existingClient = _client;

    if (_activeToken == normalizedToken && existingClient != null) {
      if (existingClient.connected) {
        _setConnectionStatus(RealtimeConnectionStatus.connected);
        return;
      }

      _setConnectionStatus(RealtimeConnectionStatus.connecting);
      existingClient.connect();
      return;
    }

    _disposeCurrentClient();

    _activeToken = normalizedToken;

    final client = _clientFactory(
      serverUrl: _serverUrl,
      token: normalizedToken,
    );

    _client = client;
    _bindLifecycle(client);

    _setConnectionStatus(RealtimeConnectionStatus.connecting);

    client.connect();
  }

  void _bindLifecycle(RealtimeSocketClient client) {
    client.onEvent(messagesChangedEvent, (data) {
      if (!identical(_client, client)) {
        return;
      }

      final invalidation = RealtimeMessageInvalidation.tryParse(data);

      if (invalidation == null || _messageInvalidationController.isClosed) {
        return;
      }

      _messageInvalidationController.add(invalidation);
    });

    client.onEvent(notificationsChangedEvent, (data) {
      if (!identical(_client, client)) {
        return;
      }

      final invalidation = RealtimeNotificationInvalidation.tryParse(data);

      if (invalidation == null ||
          _notificationInvalidationController.isClosed) {
        return;
      }

      _notificationInvalidationController.add(invalidation);
    });

    client.onEvent(orderTrackingChangedEvent, (data) {
      if (!identical(_client, client)) {
        return;
      }

      final invalidation = RealtimeOrderTrackingInvalidation.tryParse(data);

      if (invalidation == null ||
          _orderTrackingInvalidationController.isClosed) {
        return;
      }

      _orderTrackingInvalidationController.add(invalidation);
    });

    client.onConnect((_) {
      if (!identical(_client, client)) {
        return;
      }

      _setConnectionStatus(RealtimeConnectionStatus.connected);
    });

    client.onDisconnect((_) {
      if (!identical(_client, client)) {
        return;
      }

      _setConnectionStatus(RealtimeConnectionStatus.disconnected);
    });

    client.onConnectError((_) {
      if (!identical(_client, client)) {
        return;
      }

      _setConnectionStatus(RealtimeConnectionStatus.disconnected);
    });
  }

  @override
  Future<void> disconnect() async {
    _activeToken = null;
    _disposeCurrentClient();
    _setConnectionStatus(RealtimeConnectionStatus.disconnected);
  }

  void _disposeCurrentClient() {
    final client = _client;

    _client = null;

    if (client == null) {
      return;
    }

    client.disconnect();
    client.dispose();
  }

  void _setConnectionStatus(RealtimeConnectionStatus value) {
    if (_connectionStatus == value) {
      return;
    }

    _connectionStatus = value;

    if (!_connectionStatusController.isClosed) {
      _connectionStatusController.add(value);
    }
  }

  Future<void> close() async {
    await disconnect();
    await _connectionStatusController.close();
    await _messageInvalidationController.close();
    await _notificationInvalidationController.close();
    await _orderTrackingInvalidationController.close();
  }
}
