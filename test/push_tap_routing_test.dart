import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:merzox/services/push_service.dart';

final class _AuthenticatedSessionService extends AuthSessionService {
  const _AuthenticatedSessionService();

  @override
  Future<AuthSessionSnapshot> read() async {
    return const AuthSessionSnapshot(
      type: AuthSessionType.customer,
      token: 'jwt-push-tap',
    );
  }
}

final class _TapMessagingClient implements PushMessagingClient {
  Map<String, dynamic>? initialData;
  int initialReads = 0;

  final StreamController<Map<String, dynamic>> openedController =
      StreamController<Map<String, dynamic>>.broadcast();

  @override
  Future<String?> getApnsToken() async => 'apns-token';

  @override
  Future<Map<String, dynamic>?> getInitialMessageData() async {
    initialReads += 1;
    return initialData;
  }

  @override
  Future<String?> getToken() async => 'fcm-token';

  @override
  Stream<Map<String, dynamic>> get openedMessageData => openedController.stream;

  @override
  Future<PushAuthorizationStatus> requestPermission() async =>
      PushAuthorizationStatus.authorized;

  @override
  Stream<String> get tokenRefreshes => const Stream<String>.empty();

  Future<void> close() => openedController.close();
}

Map<String, dynamic> _data({
  required String notificationId,
  required String audience,
  required String routeKind,
  String? conversationId,
  String? orderId,
}) {
  return {
    'notificationId': notificationId,
    'audience': audience,
    'type': 'newMessage',
    'routeKind': routeKind,
    if (conversationId != null) 'conversationId': conversationId,
    if (orderId != null) 'orderId': orderId,
  };
}

Future<void> _drain() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  test('conversation push tap maps to existing chat route', () {
    final intent = parsePushTapIntent(
      _data(
        notificationId: 'notification-1',
        audience: 'customer',
        routeKind: 'conversation',
        conversationId: 'conversation-1',
      ),
    );

    expect(intent, isNotNull);
    expect(intent!.location, '/chat?conversationId=conversation-1');
  });

  test(
    'conversation identifier is URI encoded rather than interpolated raw',
    () {
      final intent = parsePushTapIntent(
        _data(
          notificationId: 'notification-encoded-chat',
          audience: 'customer',
          routeKind: 'conversation',
          conversationId: 'conversation/one?x=1',
        ),
      );

      expect(intent, isNotNull);

      final uri = Uri.parse(intent!.location);

      expect(uri.path, '/chat');
      expect(uri.queryParameters['conversationId'], 'conversation/one?x=1');
    },
  );

  test('order push tap maps to existing encoded order tracking route', () {
    final intent = parsePushTapIntent(
      _data(
        notificationId: 'notification-2',
        audience: 'customer',
        routeKind: 'order',
        orderId: 'order/1',
      ),
    );

    expect(intent, isNotNull);
    expect(intent!.location, '/orders/order%2F1/tracking');
  });

  test('notification push tap preserves customer and business audience', () {
    expect(
      parsePushTapIntent(
        _data(
          notificationId: 'notification-3',
          audience: 'customer',
          routeKind: 'notifications',
        ),
      )!.location,
      '/notifications',
    );

    expect(
      parsePushTapIntent(
        _data(
          notificationId: 'notification-4',
          audience: 'business',
          routeKind: 'notifications',
        ),
      )!.location,
      '/notifications?audience=business',
    );
  });

  test('malformed or unsupported push tap payload is ignored', () {
    expect(
      parsePushTapIntent({
        'audience': 'customer',
        'routeKind': 'notifications',
      }),
      isNull,
    );

    expect(
      parsePushTapIntent(
        _data(
          notificationId: 'n1',
          audience: 'attacker',
          routeKind: 'notifications',
        ),
      ),
      isNull,
    );

    expect(
      parsePushTapIntent(
        _data(
          notificationId: 'n2',
          audience: 'customer',
          routeKind: 'conversation',
        ),
      ),
      isNull,
    );

    expect(
      parsePushTapIntent(
        _data(notificationId: 'n3', audience: 'customer', routeKind: 'unknown'),
      ),
      isNull,
    );

    expect(
      parsePushTapIntent(
        _data(
          notificationId: 'n4\u0000bad',
          audience: 'customer',
          routeKind: 'notifications',
        ),
      ),
      isNull,
    );
  });

  test(
    'terminated-launch message is consumed once after app attaches',
    () async {
      final client = _TapMessagingClient()
        ..initialData = _data(
          notificationId: 'initial-1',
          audience: 'customer',
          routeKind: 'order',
          orderId: 'order-initial',
        );

      final service = PushService(
        authSessionService: const _AuthenticatedSessionService(),
        enabled: true,
        platformResolver: () => PushClientPlatform.android,
        clientFactory: () async => client,
      );

      final received = <PushTapIntent>[];

      final subscription = service.tapIntents.listen(received.add);

      await service.startTapHandling();
      await service.startTapHandling();

      expect(client.initialReads, 1);
      expect(received, hasLength(1));
      expect(received.single.location, '/orders/order-initial/tracking');

      await subscription.cancel();
      await service.close();
      await client.close();
    },
  );

  test('background-open event emits a typed navigation intent', () async {
    final client = _TapMessagingClient();

    final service = PushService(
      authSessionService: const _AuthenticatedSessionService(),
      enabled: true,
      platformResolver: () => PushClientPlatform.android,
      clientFactory: () async => client,
    );

    final received = <PushTapIntent>[];

    final subscription = service.tapIntents.listen(received.add);

    await service.startTapHandling();

    client.openedController.add(
      _data(
        notificationId: 'opened-1',
        audience: 'business',
        routeKind: 'conversation',
        conversationId: 'conversation-business',
      ),
    );

    await _drain();

    expect(received, hasLength(1));
    expect(
      received.single.location,
      '/chat?conversationId=conversation-business',
    );

    await subscription.cancel();
    await service.close();
    await client.close();
  });

  test(
    'same notification cannot navigate twice across initial and opened paths',
    () async {
      final data = _data(
        notificationId: 'duplicate-1',
        audience: 'customer',
        routeKind: 'notifications',
      );

      final client = _TapMessagingClient()..initialData = data;

      final service = PushService(
        authSessionService: const _AuthenticatedSessionService(),
        enabled: true,
        platformResolver: () => PushClientPlatform.android,
        clientFactory: () async => client,
      );

      final received = <PushTapIntent>[];

      final subscription = service.tapIntents.listen(received.add);

      await service.startTapHandling();

      client.openedController.add(data);

      await _drain();

      expect(received, hasLength(1));

      await subscription.cancel();
      await service.close();
      await client.close();
    },
  );

  test(
    'app root subscribes before consuming initial tap and owns navigation',
    () {
      final source = File('lib/app/app.dart').readAsStringSync();

      expect(source.contains('class MerzoxApp extends StatefulWidget'), true);

      expect(source.contains('late final GoRouter _router;'), true);

      final subscribe = source.indexOf('pushService.tapIntents.listen');

      final start = source.indexOf('pushService.startTapHandling()');

      final navigate = source.indexOf('_router.go(intent.location)');

      expect(subscribe, greaterThanOrEqualTo(0));
      expect(start, greaterThan(subscribe));
      expect(navigate, greaterThanOrEqualTo(0));

      expect(source.contains('routerConfig: _router'), true);
    },
  );

  test('push tap destinations remain behind existing AppRouter guard', () {
    final source = File('lib/router/app_router.dart').readAsStringSync();

    expect(source.contains('return AuthRouteGuard.redirect'), true);

    for (final route in [
      "path: '/chat'",
      "path: '/notifications'",
      "path: '/orders/:orderId/tracking'",
    ]) {
      expect(source.contains(route), true, reason: route);
    }
  });
}
