import 'package:flutter_bloc/flutter_bloc.dart';
import 'onboarding_event.dart';
import 'onboarding_state.dart';
import 'package:shared_preferences/shared_preferences.dart';


class OnboardingBloc extends Bloc<OnboardingEvent, OnboardingState> {
  OnboardingBloc() : super(OnboardingState(currentPage: 0)) {
    on<NextPage>(_onNextPage);
    on<SkipOnboarding>(_onSkip);
  }

  Future<void> _onNextPage(
    NextPage event,
    Emitter<OnboardingState> emit,
  ) async {
    if (state.currentPage < 2) {
      emit(OnboardingState(currentPage: event.page));
    } else {
      emit(OnboardingState(currentPage: event.page));
      await _completeOnboarding();
    }
  }

  Future<void> _onSkip(
    SkipOnboarding event,
    Emitter<OnboardingState> emit,
  ) async {
    await _completeOnboarding();
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_completed', true);

    ///TODO Navigate to guest home screen
  }
}
