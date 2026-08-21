import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/startup/startup_destination.dart';
import '../features/about_us/bloc/about_us_bloc.dart';
import '../features/about_us/pages/about_us_page.dart';
import '../features/authentication/bloc/auth_bloc.dart';
import '../features/authentication/pages/login_page.dart';
import '../features/authentication/pages/signup_page.dart';
import '../features/business/enrollment/business_enrollment_bloc.dart';
import '../features/business/enrollment/business_enrollment_page.dart';
import '../features/business/shell/business_bloc.dart';
import '../features/business/shell/business_shell_page.dart';
import '../features/favorites/bloc/favorites_bloc.dart';
import '../features/favorites/bloc/favorites_event.dart';
import '../features/favorites/pages/favorites_page.dart';
import '../features/home/home_screen.dart';
import '../features/home/presentation/bloc/home_bloc.dart';
import '../features/home/presentation/bloc/home_event.dart';
import '../features/map/bloc/nearby_map_bloc.dart';
import '../features/map/bloc/nearby_map_event.dart';
import '../features/map/pages/nearby_map_page.dart';
import '../features/onboarding/bloc/onboarding_bloc.dart';
import '../features/onboarding/view/onboarding_screen.dart';
import '../features/orders/bloc/orders_bloc.dart';
import '../features/orders/bloc/orders_event.dart';
import '../features/orders/pages/orders_page.dart';
import '../features/profile/bloc/profile_edit_bloc.dart';
import '../features/profile/bloc/profile_edit_event.dart';
import '../features/profile/pages/profile_edit_page.dart';
import '../features/search/bloc/search_bloc.dart';
import '../features/search/bloc/search_event.dart';
import '../features/search/pages/search_page.dart';
import '../features/share_app/bloc/share_app_bloc.dart';
import '../features/share_app/pages/share_app_page.dart';

class AppRouter {
  final StartupDestination destination;

  AppRouter(this.destination);

  GoRouter get router => GoRouter(
    initialLocation: switch (destination) {
      StartupDestination.onboarding => '/onboarding',
      StartupDestination.login => '/login',
      StartupDestination.home => '/home',
      StartupDestination.businessHome => '/business',
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, __) => BlocProvider(
          create: (_) => OnboardingBloc(),
          child: OnboardingScreen(onFinished: () => context.go('/login')),
        ),
      ),
      GoRoute(
        path: '/login',
        builder: (context, __) => BlocProvider(
          create: (_) => AuthBloc(),
          child: LoginPage(
            onAuthenticated: () => _goAfterLogin(context),
            onBrowseAsGuest: () => context.go('/home?guest=true'),
            onSignupRequested: () => context.go('/signup'),
          ),
        ),
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
          create: (_) => AuthBloc(),
          child: LoginPage(
            businessMode: true,
            onAuthenticated: () => context.go('/business'),
            onBrowseAsGuest: () => context.go('/login'),
            onSignupRequested: () => context.go('/login'),
          ),
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
          create: (_) => AuthBloc(),
          child: SignupPage(
            onSignupCreated: () => context.go('/login'),
            onLoginRequested: () => context.go('/login'),
          ),
        ),
      ),
      GoRoute(
        path: '/home',
        builder: (_, state) {
          final isGuest = state.uri.queryParameters['guest'] == 'true';
          final initialTab =
              int.tryParse(state.uri.queryParameters['tab'] ?? '') ?? 0;
          return BlocProvider(
            create: (_) =>
                HomeBloc()
                  ..add(HomeStarted(isGuest: isGuest, initialTab: initialTab)),
            child: HomeScreen(isGuest: isGuest),
          );
        },
      ),
      GoRoute(
        path: '/orders',
        builder: (_, __) => BlocProvider(
          create: (_) => OrdersBloc()..add(const OrdersStarted()),
          child: const OrdersPage(),
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
          StartupDestination.home => '/home',
          StartupDestination.businessHome => '/business',
        },
      ),
    ],
  );

  static Future<void> _goAfterLogin(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final route = prefs.getString(AuthBloc.userTypeKey) == 'business'
        ? '/business'
        : '/home';
    if (context.mounted) context.go(route);
  }
}
