import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:merzox/features/authentication/bloc/auth_event.dart';
import 'package:merzox/features/authentication/bloc/auth_state.dart';
import 'package:merzox/services/push_service.dart';
import 'package:merzox/services/realtime_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class _OrderedPushController implements PushSessionController {
  final List<String> order;

  _OrderedPushController(this.order);

  @override
  Future<void> prepareForStartup() async {
    order.add('push-prepare');
  }

  @override
  Future<void> syncWithSession() async {
    order.add('push-sync');
  }

  @override
  Future<void> unregisterCurrentTarget() async {
    final prefs = await SharedPreferences.getInstance();

    order.add(
      prefs.getString(AuthBloc.tokenKey) == 'jwt-logout'
          ? 'push-unregister-with-token'
          : 'push-unregister-without-token',
    );
  }
}

final class _OrderedRealtimeController implements RealtimeSessionController {
  final List<String> order;

  _OrderedRealtimeController(this.order);

  @override
  Future<void> syncWithSession() async {
    order.add('realtime-sync');
  }

  @override
  Future<void> disconnect() async {
    final prefs = await SharedPreferences.getInstance();

    order.add(
      prefs.getString(AuthBloc.tokenKey) == null
          ? 'realtime-disconnect-after-clear'
          : 'realtime-disconnect-before-clear',
    );
  }
}

int _index(String source, String needle) {
  final value = source.indexOf(needle);

  expect(
    value,
    greaterThanOrEqualTo(0),
    reason: 'Missing source contract: $needle',
  );

  return value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'AuthSessionService detects authenticated session that startup will purge',
    () async {
      SharedPreferences.setMockInitialValues({
        AuthBloc.sessionKey: true,
        AuthBloc.rememberSessionKey: false,
        AuthBloc.tokenKey: 'jwt-old-process',
        AuthBloc.userTypeKey: 'normal',
      });

      expect(
        await const AuthSessionService().hasUnrememberedAuthenticatedSession(),
        true,
      );

      SharedPreferences.setMockInitialValues({
        AuthBloc.sessionKey: true,
        AuthBloc.rememberSessionKey: true,
        AuthBloc.tokenKey: 'jwt-remembered',
        AuthBloc.userTypeKey: 'normal',
      });

      expect(
        await const AuthSessionService().hasUnrememberedAuthenticatedSession(),
        false,
      );
    },
  );

  test(
    'AuthBloc logout unregisters push with JWT before clear then disconnects realtime',
    () async {
      SharedPreferences.setMockInitialValues({
        AuthBloc.sessionKey: true,
        AuthBloc.rememberSessionKey: true,
        AuthBloc.tokenKey: 'jwt-logout',
        AuthBloc.userTypeKey: 'normal',
      });

      final order = <String>[];

      final bloc = AuthBloc(
        realtimeSessionController: _OrderedRealtimeController(order),
        pushSessionController: _OrderedPushController(order),
      );

      bloc.add(const LogoutRequested());

      await bloc.stream.firstWhere(
        (state) => state.status == AuthStatus.unauthenticated,
      );

      expect(order, [
        'push-unregister-with-token',
        'realtime-disconnect-after-clear',
      ]);

      final prefs = await SharedPreferences.getInstance();

      expect(prefs.getString(AuthBloc.tokenKey), isNull);

      await bloc.close();
    },
  );

  test(
    'bootstrap prepares push before StartupService can purge auth and syncs after truth',
    () {
      final source = File('lib/app/bootstrap.dart').readAsStringSync();

      final prepare = _index(source, 'await pushService.prepareForStartup();');

      final startup = _index(
        source,
        'final destination = await startupService.initialize();',
      );

      final realtime = _index(
        source,
        'await locator<RealtimeService>().syncWithSession();',
      );

      final pushSync = _index(source, 'await pushService.syncWithSession();');

      expect(prepare, lessThan(startup));
      expect(startup, lessThan(realtime));
      expect(realtime, lessThan(pushSync));
    },
  );

  test(
    'AuthBloc login persists session before realtime and push synchronization',
    () {
      final source = File(
        'lib/features/authentication/bloc/auth_bloc.dart',
      ).readAsStringSync();

      final persisted = _index(source, 'await _persistAuthenticatedSession(');

      final realtime = _index(source, 'await _syncRealtimeSession();');

      final push = _index(source, 'await _syncPushSession();');

      expect(persisted, lessThan(realtime));
      expect(realtime, lessThan(push));
    },
  );

  test(
    'direct customer and business logout paths unregister push before auth clear',
    () {
      for (final path in [
        'lib/features/home/home_screen.dart',
        'lib/features/business/shell/business_shell_page.dart',
      ]) {
        final source = File(path).readAsStringSync();

        final unregister = _index(source, 'unregisterCurrentTarget()');

        final clear = _index(source, 'AuthBloc.clearStoredSession()');

        final realtime = _index(source, 'RealtimeService>().disconnect()');

        expect(unregister, lessThan(clear), reason: path);

        expect(clear, lessThan(realtime), reason: path);
      }
    },
  );

  test(
    'all AuthBloc routes receive both realtime and push session controllers',
    () {
      final source = File('lib/router/app_router.dart').readAsStringSync();

      expect(
        RegExp(
          r'pushSessionController:\s*_pushSessionController',
        ).allMatches(source).length,
        3,
      );

      expect(
        source.contains('PushSessionController? get _pushSessionController'),
        true,
      );
    },
  );
}
