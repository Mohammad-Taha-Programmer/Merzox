import 'package:shared_preferences/shared_preferences.dart';

import '../../features/authentication/bloc/auth_bloc.dart';
import 'startup_destination.dart';

class StartupService {
  Future<StartupDestination> initialize() async {
    final prefs = await SharedPreferences.getInstance();

    final bool onboardingCompleted =
        prefs.getBool('onboarding_completed') ?? false;

    final bool loggedIn = prefs.getBool(AuthBloc.sessionKey) ?? false;
    final String? token = prefs.getString(AuthBloc.tokenKey);

    if (!onboardingCompleted) {
      return StartupDestination.onboarding;
    }

    if (!loggedIn || token == null || token.trim().isEmpty) {
      return StartupDestination.guestHome;
    }

    final userType = prefs.getString(AuthBloc.userTypeKey);
    return userType == 'business'
        ? StartupDestination.businessHome
        : StartupDestination.home;
  }
}
