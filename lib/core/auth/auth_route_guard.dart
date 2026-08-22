import 'auth_session_service.dart';

final class AuthRouteGuard {
  static const Set<String> _authenticatedRoutes = {
    '/orders',
    '/favorites',
    '/profile/edit',
    '/business/enroll',
    '/chat',
    '/notifications',
  };

  /// Order tracking carries the order id in the path, so it is matched by
  /// shape rather than by an exact route string.
  static bool _isAuthenticatedPattern(String path) {
    return path.startsWith('/orders/') && path.endsWith('/tracking');
  }

  const AuthRouteGuard._();

  static String? redirect({
    required Uri uri,
    required AuthSessionSnapshot session,
  }) {
    final path = uri.path;

    if (path == '/home') {
      return _normalizeHome(uri, session);
    }

    if ((_authenticatedRoutes.contains(path) ||
            _isAuthenticatedPattern(path)) &&
        !session.isAuthenticated) {
      return '/login';
    }

    // A presentation flag must never confer a role. `audience=business` only
    // selects which feed to request; the session decides whether that is
    // allowed, and the parameter is stripped when it is not.
    if (path == '/notifications') {
      return _normalizeNotifications(uri, session);
    }

    if (path == '/business/messages' && !session.isBusiness) {
      return session.isAuthenticated ? '/business/enroll' : '/business/login';
    }

    if (path == '/business') {
      if (!session.isAuthenticated) {
        return '/business/login';
      }
      if (!session.isBusiness) {
        return '/business/enroll';
      }
    }

    return null;
  }

  static String? _normalizeNotifications(Uri uri, AuthSessionSnapshot session) {
    final wantsBusinessFeed = uri.queryParameters['audience'] == 'business';

    if (!wantsBusinessFeed || session.isBusiness) {
      return null;
    }

    // The customer keeps their own notifications rather than being bounced
    // away from a route they are entitled to; only the role claim is removed.
    final query = Map<String, String>.from(uri.queryParameters)
      ..remove('audience');
    return _routeWithQuery(uri, query);
  }

  static String? _normalizeHome(Uri uri, AuthSessionSnapshot session) {
    final guestFlag = uri.queryParameters['guest'] == 'true';

    if (!session.isAuthenticated && !guestFlag) {
      final query = Map<String, String>.from(uri.queryParameters)
        ..['guest'] = 'true';
      return _routeWithQuery(uri, query);
    }

    if (session.isAuthenticated && guestFlag) {
      final query = Map<String, String>.from(uri.queryParameters)
        ..remove('guest');
      return _routeWithQuery(uri, query);
    }

    return null;
  }

  static String _routeWithQuery(Uri uri, Map<String, String> query) {
    final route = StringBuffer(uri.path);
    if (query.isNotEmpty) {
      route
        ..write('?')
        ..write(Uri(queryParameters: query).query);
    }
    if (uri.hasFragment) {
      route
        ..write('#')
        ..write(uri.fragment);
    }
    return route.toString();
  }
}
