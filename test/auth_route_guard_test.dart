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

  group('routes added by the bulk implementation', () {
    // AC-19: messaging, notifications, and tracking are customer-private and
    // must be classified alongside the pre-existing protected routes.
    const protectedRoutes = [
      '/chat',
      '/notifications',
      '/orders/64b000000000000000000001/tracking',
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

    test('a chat deep link carrying query parameters is still guarded', () {
      expect(
        AuthRouteGuard.redirect(
          uri: Uri.parse('/chat?businessId=64b000000000000000000001&title=x'),
          session: guest,
        ),
        '/login',
      );
    });

    test('a tracking deep link is guarded for any order id', () {
      expect(
        AuthRouteGuard.redirect(
          uri: Uri.parse('/orders/000000000000000000000000/tracking'),
          session: guest,
        ),
        '/login',
      );
    });

    test('the orders list route is not confused with tracking', () {
      expect(
        AuthRouteGuard.redirect(uri: Uri.parse('/orders'), session: guest),
        '/login',
      );
    });
  });

  group('merchant inbox route', () {
    test('sends a guest to the business login', () {
      expect(
        AuthRouteGuard.redirect(
          uri: Uri.parse('/business/messages'),
          session: guest,
        ),
        '/business/login',
      );
    });

    test('sends a customer to enrollment rather than the merchant inbox', () {
      expect(
        AuthRouteGuard.redirect(
          uri: Uri.parse('/business/messages'),
          session: customer,
        ),
        '/business/enroll',
      );
    });

    test('allows the business account through', () {
      expect(
        AuthRouteGuard.redirect(
          uri: Uri.parse('/business/messages'),
          session: business,
        ),
        isNull,
      );
    });
  });

  group('guest presentation flag is never authorization', () {
    // AC-20: ?guest=true is a home-presentation hint only. It must not open a
    // protected route, and it must not be honoured for a real session.
    test('a guest flag does not unlock a protected route', () {
      for (final route in [
        '/chat?guest=true',
        '/notifications?guest=true',
        '/orders/64b000000000000000000001/tracking?guest=true',
      ]) {
        expect(
          AuthRouteGuard.redirect(uri: Uri.parse(route), session: guest),
          '/login',
          reason: route,
        );
      }
    });

    test('an authenticated session drops the guest flag on home', () {
      expect(
        AuthRouteGuard.redirect(
          uri: Uri.parse('/home?guest=true'),
          session: customer,
        ),
        '/home',
      );
    });
  });

  group('FIX2-B: presentation flags never confer a role', () {
    // A hand-typed or deep-linked URL must not be able to promote a customer
    // into the merchant notification feed.
    test('a customer asking for the business feed has the claim stripped', () {
      expect(
        AuthRouteGuard.redirect(
          uri: Uri.parse('/notifications?audience=business'),
          session: customer,
        ),
        '/notifications',
      );
    });

    test('the stripped route keeps unrelated query parameters', () {
      final redirect = AuthRouteGuard.redirect(
        uri: Uri.parse('/notifications?audience=business&filter=unread'),
        session: customer,
      );

      expect(redirect, isNotNull);
      final target = Uri.parse(redirect!);
      expect(target.path, '/notifications');
      expect(target.queryParameters.containsKey('audience'), isFalse);
      expect(target.queryParameters['filter'], 'unread');
    });

    test('a guest asking for the business feed is sent to login', () {
      expect(
        AuthRouteGuard.redirect(
          uri: Uri.parse('/notifications?audience=business'),
          session: guest,
        ),
        '/login',
      );
    });

    test('a business session keeps the business feed', () {
      expect(
        AuthRouteGuard.redirect(
          uri: Uri.parse('/notifications?audience=business'),
          session: business,
        ),
        isNull,
      );
    });

    test('a customer feed request is left alone', () {
      for (final route in ['/notifications', '/notifications?filter=unread']) {
        expect(
          AuthRouteGuard.redirect(uri: Uri.parse(route), session: customer),
          isNull,
          reason: route,
        );
      }
    });

    test('an unknown audience value is not treated as business', () {
      for (final value in ['Business', 'BUSINESS', 'business ', 'admin', '1']) {
        expect(
          AuthRouteGuard.redirect(
            uri: Uri.parse('/notifications?audience=$value'),
            session: customer,
          ),
          isNull,
          reason: 'audience=$value must not be read as a business claim',
        );
      }
    });

    test('the merchant inbox cannot be reached by a customer', () {
      expect(
        AuthRouteGuard.redirect(
          uri: Uri.parse('/business/messages?merchantMode=true'),
          session: customer,
        ),
        '/business/enroll',
      );
      expect(
        AuthRouteGuard.redirect(
          uri: Uri.parse('/business/messages?merchantMode=true'),
          session: guest,
        ),
        '/business/login',
      );
      expect(
        AuthRouteGuard.redirect(
          uri: Uri.parse('/business/messages?merchantMode=true'),
          session: business,
        ),
        isNull,
      );
    });

    test('the business shell cannot be reached by a customer', () {
      expect(
        AuthRouteGuard.redirect(
          uri: Uri.parse('/business?businessAudience=true'),
          session: customer,
        ),
        '/business/enroll',
      );
      expect(
        AuthRouteGuard.redirect(uri: Uri.parse('/business'), session: guest),
        '/business/login',
      );
    });
  });
}
