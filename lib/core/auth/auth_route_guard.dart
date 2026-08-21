import 'auth_session_service.dart';

final class AuthRouteGuard {
  static const Set<String> _authenticatedRoutes = {
    '/orders',
    '/favorites',
    '/profile/edit',
    '/business/enroll',
  };

  const AuthRouteGuard._();

  static String? redirect({
    required Uri uri,
    required AuthSessionSnapshot session,
  }) {
    final path = uri.path;

    if (path == '/home') {
      return _normalizeHome(uri, session);
    }

    if (_authenticatedRoutes.contains(path) && !session.isAuthenticated) {
      return '/login';
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
