import 'package:shared_preferences/shared_preferences.dart';

import '../auth/auth_session_service.dart';
import 'startup_destination.dart';

class StartupService {
  final AuthSessionService _authSessionService;

  StartupService({AuthSessionService? authSessionService})
    : _authSessionService = authSessionService ?? const AuthSessionService();

  Future<StartupDestination> initialize() async {
    final prefs = await SharedPreferences.getInstance();

    final bool onboardingCompleted =
        prefs.getBool('onboarding_completed') ?? false;

    if (!onboardingCompleted) {
      return StartupDestination.onboarding;
    }

    final session = await _authSessionService.read();
    if (!session.isAuthenticated) {
      return StartupDestination.guestHome;
    }

    return session.isBusiness
        ? StartupDestination.businessHome
        : StartupDestination.home;
  }
}
