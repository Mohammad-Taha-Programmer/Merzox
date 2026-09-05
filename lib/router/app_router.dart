import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/auth_route_guard.dart';
import '../core/auth/auth_session_service.dart';
import '../core/startup/startup_destination.dart';
import '../injection/injector.dart';
import '../services/push_service.dart';
import '../services/realtime_service.dart';
import '../features/about_us/bloc/about_us_bloc.dart';
import '../features/about_us/pages/about_us_page.dart';
import '../features/authentication/bloc/auth_bloc.dart';
import '../features/authentication/pages/login_page.dart';
import '../features/authentication/pages/signup_page.dart';
import '../features/authentication/password_recovery/bloc/password_recovery_bloc.dart';
import '../features/authentication/password_recovery/pages/forgot_password_page.dart';
import '../features/authentication/password_recovery/pages/reset_password_page.dart';
import '../features/business/enrollment/business_enrollment_bloc.dart';
import '../features/business/messages/merchant_messages_page.dart';
import '../features/business/orders/merchant_order_route.dart';
import '../features/business/enrollment/business_enrollment_page.dart';
import '../features/business/preview/store_preview_page.dart';
import '../features/business/shell/business_bloc.dart';
import '../features/business/shell/business_shell_page.dart';
import '../features/courier_location/courier_location_bloc.dart';
import '../features/courier_location/courier_location_page.dart';
import '../features/favorites/bloc/favorites_bloc.dart';
import '../features/favorites/bloc/favorites_event.dart';
import '../features/favorites/pages/favorites_page.dart';
import '../features/home/home_screen.dart';
import '../features/home/presentation/bloc/home_bloc.dart';
import '../features/home/presentation/bloc/home_event.dart';
import '../features/map/bloc/nearby_map_bloc.dart';
import '../features/map/bloc/nearby_map_event.dart';
import '../features/map/pages/nearby_map_page.dart';
import '../features/messages/bloc/chat_bloc.dart';
import '../features/messages/bloc/messages_bloc.dart';
import '../features/messages/bloc/messages_event.dart';
import '../features/messages/bloc/chat_event.dart';
import '../features/messages/pages/chat_page.dart';
import '../features/notifications/bloc/notifications_bloc.dart';
import '../features/notifications/bloc/notifications_event.dart';
import '../features/notifications/pages/notifications_page.dart';
import '../features/onboarding/bloc/onboarding_bloc.dart';
import '../features/onboarding/view/onboarding_screen.dart';
import '../features/orders/bloc/orders_bloc.dart';
import '../features/orders/bloc/order_tracking_bloc.dart';
import '../features/orders/bloc/order_tracking_event.dart';
import '../features/orders/bloc/orders_event.dart';
import '../features/orders/pages/order_tracking_page.dart';
import '../features/orders/pages/orders_page.dart';
import '../features/profile/bloc/profile_edit_bloc.dart';
import '../features/profile/bloc/profile_edit_event.dart';
import '../features/profile/pages/profile_edit_page.dart';
import '../features/search/bloc/search_bloc.dart';
import '../features/search/bloc/search_event.dart';
import '../features/search/pages/search_page.dart';
import '../features/share_app/bloc/share_app_bloc.dart';
import '../features/share_app/pages/share_app_page.dart';
import 'package:merzox/features/cart/bloc/cart_bloc.dart';
import 'package:merzox/features/cart/bloc/cart_event.dart';
import 'package:merzox/features/checkout/pages/checkout_page.dart';

class AppRouter {
  final StartupDestination destination;
  final AuthSessionService _authSessionService;

  AppRouter(this.destination, {AuthSessionService? authSessionService})
    : _authSessionService = authSessionService ?? const AuthSessionService();

  RealtimeSessionController? get _realtimeSessionController {
    if (!locator.isRegistered<RealtimeService>()) {
      return null;
    }

    return locator<RealtimeService>();
  }

  PushSessionController? get _pushSessionController {
    if (!locator.isRegistered<PushService>()) {
      return null;
    }

    return locator<PushService>();
  }

  RealtimeService? get _realtimeService {
    if (!locator.isRegistered<RealtimeService>()) {
      return null;
    }

    return locator<RealtimeService>();
  }

  GoRouter get router => GoRouter(
    initialLocation: switch (destination) {
      StartupDestination.onboarding => '/onboarding',
      StartupDestination.login => '/login',
      StartupDestination.guestHome => '/home?guest=true',
      StartupDestination.home => '/home',
      StartupDestination.businessHome => '/business',
    },
    redirect: (_, state) async {
      final session = await _authSessionService.read();
      return AuthRouteGuard.redirect(uri: state.uri, session: session);
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, __) => BlocProvider(
          create: (_) => OnboardingBloc(),
          child: OnboardingScreen(
            onFinished: () => context.go('/home?guest=true'),
          ),
        ),
      ),
      GoRoute(
        path: '/login',
        builder: (context, __) => BlocProvider(
          create: (_) => AuthBloc(
            realtimeSessionController: _realtimeSessionController,
            pushSessionController: _pushSessionController,
          ),
          child: LoginPage(
            onAuthenticated: () => _goAfterLogin(context),
            onBrowseAsGuest: () => context.go('/home?guest=true'),
            onSignupRequested: () => context.go('/signup'),
            onForgotPasswordRequested: () => context.go('/forgot-password'),
            onCourierLocationRequested: () => context.push('/courier/location'),
          ),
        ),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) {
          final businessMode = state.uri.queryParameters['business'] == 'true';
          final loginRoute = businessMode ? '/business/login' : '/login';
          final resetRoute = businessMode
              ? '/reset-password?business=true'
              : '/reset-password';

          return BlocProvider(
            create: (_) => PasswordRecoveryBloc(),
            child: ForgotPasswordPage(
              onRequestAccepted: () => context.go(resetRoute),
              onBackToLogin: () => context.go(loginRoute),
            ),
          );
        },
      ),
      GoRoute(
        path: '/reset-password',
        builder: (context, state) {
          final businessMode = state.uri.queryParameters['business'] == 'true';
          final loginRoute = businessMode ? '/business/login' : '/login';

          return BlocProvider(
            create: (_) => PasswordRecoveryBloc(),
            child: ResetPasswordPage(
              onResetSucceeded: () => context.go(loginRoute),
              onBackToLogin: () => context.go(loginRoute),
            ),
          );
        },
      ),
      GoRoute(
        path: '/business/enroll',
        builder: (context, __) => BlocProvider(
          create: (_) => BusinessEnrollmentBloc(),
          child: BusinessEnrollmentPage(
            onCompleted: () => context.go('/business/login'),
          ),
        ),
      ),
      GoRoute(
        path: '/business/login',
        builder: (context, __) => BlocProvider(
          create: (_) => AuthBloc(
            realtimeSessionController: _realtimeSessionController,
            pushSessionController: _pushSessionController,
          ),
          child: LoginPage(
            businessMode: true,
            onAuthenticated: () => context.go('/business'),
            onBrowseAsGuest: () => context.go('/login'),
            onSignupRequested: () => context.go('/login'),
            onForgotPasswordRequested: () =>
                context.go('/forgot-password?business=true'),
            onCourierLocationRequested: () => context.push('/courier/location'),
          ),
        ),
      ),
      GoRoute(
        path: '/courier/location',
        builder: (_, __) => BlocProvider(
          create: (_) => CourierLocationBloc(),
          child: const CourierLocationPage(),
        ),
      ),
      GoRoute(
        path: '/business/messages',
        builder: (_, __) => BlocProvider(
          create: (_) => MessagesBloc(
            merchantMode: true,
            realtimeMessageInvalidations:
                _realtimeService?.messageInvalidations,
            realtimeConnectionStatuses: _realtimeService?.connectionStatuses,
          )..add(const MessagesStarted()),
          child: const MerchantMessagesPage(),
        ),
      ),
      // The preview takes no business id from the route: it loads the owner
      // business for the current session, so the URL cannot be pointed at
      // somebody else's store.
      GoRoute(
        path: '/business/preview',
        builder: (_, __) => BlocProvider(
          create: (_) => BusinessBloc()..add(const BusinessStarted()),
          child: const StorePreviewPage(),
        ),
      ),
      GoRoute(
        path: '/business',
        builder: (context, __) => BlocProvider(
          create: (_) => BusinessBloc()..add(const BusinessStarted()),
          child: BusinessShellPage(onLoggedOut: () => context.go('/login')),
        ),
      ),
      GoRoute(
        path: '/signup',
        builder: (context, __) => BlocProvider(
          create: (_) => AuthBloc(
            realtimeSessionController: _realtimeSessionController,
            pushSessionController: _pushSessionController,
          ),
          child: SignupPage(
            onSignupCreated: () => context.go('/login'),
            onLoginRequested: () => context.go('/login'),
          ),
        ),
      ),
      GoRoute(
        path: '/home',
        builder: (_, state) {
          final showGuestPresentation =
              state.uri.queryParameters['guest'] == 'true';
          final initialTab =
              int.tryParse(state.uri.queryParameters['tab'] ?? '') ?? 0;
          return BlocProvider(
            create: (_) => HomeBloc()
              ..add(
                HomeStarted(
                  isGuest: showGuestPresentation,
                  initialTab: initialTab,
                ),
              ),
            child: HomeScreen(isGuest: showGuestPresentation),
          );
        },
      ),
      GoRoute(
        path: '/checkout',
        builder: (context, __) => BlocProvider<CartBloc>(
          // Its own cart instance: the flow reads the basket it is about to
          // submit, and submits through the same event the cart tab used.
          create: (_) => CartBloc()..add(const CartStarted()),
          child: CheckoutPage(
            onCompleted: () {
              if (context.canPop()) context.pop();
            },
          ),
        ),
      ),
      GoRoute(
        path: '/orders',
        builder: (_, __) => BlocProvider(
          create: (_) => OrdersBloc()..add(const OrdersStarted()),
          child: const OrdersPage(),
        ),
      ),
      // A merchant arriving from a notification. The customer's tracking route
      // below looks an order up among the reader's OWN orders, so a merchant
      // sent there is told their own shop's order does not exist.
      GoRoute(
        path: '/business/orders/:orderId',
        builder: (_, state) =>
            MerchantOrderRoute(orderId: state.pathParameters['orderId'] ?? ''),
      ),
      GoRoute(
        path: '/orders/:orderId/tracking',
        builder: (_, state) => BlocProvider(
          create: (_) => OrderTrackingBloc(
            orderId: state.pathParameters['orderId'] ?? '',
            realtimeOrderTrackingInvalidations:
                _realtimeService?.orderTrackingInvalidations,
          )..add(const OrderTrackingStarted()),
          child: const OrderTrackingPage(),
        ),
      ),
      GoRoute(
        path: '/chat',
        builder: (_, state) {
          final parameters = state.uri.queryParameters;
          final conversationId = parameters['conversationId'] ?? '';
          final businessId = parameters['businessId'] ?? '';

          return BlocProvider(
            create: (_) {
              final realtimeService = _realtimeService;

              final bloc = ChatBloc(
                realtimeMessageInvalidations:
                    realtimeService?.messageInvalidations,
                realtimeConnectionStatuses: realtimeService?.connectionStatuses,
                conversationId: conversationId,
                title: parameters['title'] ?? '',
                avatarUrl: parameters['avatarUrl'] ?? '',
              );

              // Coming from a store page there is no thread yet, so the bloc
              // opens one before it loads any history.
              return conversationId.isEmpty
                  ? (bloc..add(ChatOpenedForBusiness(businessId)))
                  : (bloc..add(const ChatStarted()));
            },
            child: const ChatPage(),
          );
        },
      ),
      GoRoute(
        path: '/notifications',
        builder: (_, state) => BlocProvider(
          create: (_) => NotificationsBloc(
            businessAudience:
                state.uri.queryParameters['audience'] == 'business',
            realtimeNotificationInvalidations:
                _realtimeService?.notificationInvalidations,
            realtimeConnectionStatuses: _realtimeService?.connectionStatuses,
          )..add(const NotificationsStarted()),
          child: const NotificationsPage(),
        ),
      ),
      GoRoute(
        path: '/map',
        builder: (_, __) => BlocProvider(
          create: (_) => NearbyMapBloc()..add(const NearbyMapStarted()),
          child: const NearbyMapPage(),
        ),
      ),
      GoRoute(
        path: '/favorites',
        builder: (_, __) => BlocProvider(
          create: (_) => FavoritesBloc()..add(const FavoritesStarted()),
          child: const FavoritesPage(),
        ),
      ),
      GoRoute(
        path: '/about-us',
        builder: (_, __) => BlocProvider(
          create: (_) => AboutUsBloc(),
          child: const AboutUsPage(),
        ),
      ),
      GoRoute(
        path: '/share-app',
        builder: (_, __) => BlocProvider(
          create: (_) => ShareAppBloc(),
          child: const ShareAppPage(),
        ),
      ),
      GoRoute(
        path: '/profile/edit',
        builder: (_, __) => BlocProvider(
          create: (_) => ProfileEditBloc()..add(const ProfileEditStarted()),
          child: const ProfileEditPage(),
        ),
      ),
      GoRoute(
        path: '/search',
        builder: (_, __) => BlocProvider(
          create: (_) => SearchBloc()..add(const SearchStarted()),
          child: const SearchPage(),
        ),
      ),
      GoRoute(
        path: '/',
        redirect: (_, __) => switch (destination) {
          StartupDestination.onboarding => '/onboarding',
          StartupDestination.login => '/login',
          StartupDestination.guestHome => '/home?guest=true',
          StartupDestination.home => '/home',
          StartupDestination.businessHome => '/business',
        },
      ),
    ],
  );

  /// The destination after login comes from the centralized session, not from
  /// a stored userType that could survive a logout.
  Future<void> _goAfterLogin(BuildContext context) async {
    final session = await _authSessionService.read();

    if (!context.mounted) return;

    if (!session.isAuthenticated) {
      context.go('/login');
      return;
    }

    context.go(session.isBusiness ? '/business' : '/home');
  }
}
