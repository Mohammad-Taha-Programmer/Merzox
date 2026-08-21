import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/auth/auth_route_guard.dart';
import 'package:merzox/core/auth/auth_session_service.dart';

void main() {
  const guest = AuthSessionSnapshot(type: AuthSessionType.unauthenticated);
  const customer = AuthSessionSnapshot(
    type: AuthSessionType.customer,
    token: 'customer-token',
  );
  const business = AuthSessionSnapshot(
    type: AuthSessionType.business,
    token: 'business-token',
  );

  group('protected customer routes', () {
    const protectedRoutes = [
      '/orders',
      '/favorites',
      '/profile/edit',
      '/business/enroll',
    ];

    for (final route in protectedRoutes) {
      test('redirects guest $route to login', () {
        expect(
          AuthRouteGuard.redirect(uri: Uri.parse(route), session: guest),
          '/login',
        );
      });

      test('allows authenticated customer $route', () {
        expect(
          AuthRouteGuard.redirect(uri: Uri.parse(route), session: customer),
          isNull,
        );
      });
    }
  });

  group('business dashboard', () {
    test('sends a guest to business login', () {
      expect(
        AuthRouteGuard.redirect(uri: Uri.parse('/business'), session: guest),
        '/business/login',
      );
    });

    test('sends an authenticated customer to business enrollment', () {
      expect(
        AuthRouteGuard.redirect(uri: Uri.parse('/business'), session: customer),
        '/business/enroll',
      );
    });

    test('allows an authenticated business', () {
      expect(
        AuthRouteGuard.redirect(uri: Uri.parse('/business'), session: business),
        isNull,
      );
    });
  });

  group('home normalization', () {
    test('adds the guest flag for an unauthenticated home request', () {
      expect(
        AuthRouteGuard.redirect(uri: Uri.parse('/home'), session: guest),
        '/home?guest=true',
      );
    });

    test('keeps an already normalized guest home request', () {
      expect(
        AuthRouteGuard.redirect(
          uri: Uri.parse('/home?guest=true'),
          session: guest,
        ),
        isNull,
      );
    });

    test('removes the guest flag for an authenticated user', () {
      expect(
        AuthRouteGuard.redirect(
          uri: Uri.parse('/home?guest=true'),
          session: customer,
        ),
        '/home',
      );
    });

    test('preserves other home query parameters while normalizing', () {
      expect(
        AuthRouteGuard.redirect(uri: Uri.parse('/home?tab=3'), session: guest),
        '/home?tab=3&guest=true',
      );
      expect(
        AuthRouteGuard.redirect(
          uri: Uri.parse('/home?guest=true&tab=3'),
          session: customer,
        ),
        '/home?tab=3',
      );
    });
  });
}
