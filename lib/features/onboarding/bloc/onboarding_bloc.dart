import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'onboarding_event.dart';
import 'onboarding_state.dart';

class OnboardingBloc extends Bloc<OnboardingEvent, OnboardingState> {
  OnboardingBloc() : super(const OnboardingState(currentPage: 0)) {
    on<NextPage>(_onNextPage);
    on<SkipOnboarding>(_onSkip);
  }

  Future<void> _onNextPage(
    NextPage event,
    Emitter<OnboardingState> emit,
  ) async {
    emit(state.copyWith(currentPage: event.page));
  }

  Future<void> _onSkip(
    SkipOnboarding event,
    Emitter<OnboardingState> emit,
  ) async {
    await _completeOnboarding();
    emit(state.copyWith(isCompleted: true));
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_completed', true);
  }
}
