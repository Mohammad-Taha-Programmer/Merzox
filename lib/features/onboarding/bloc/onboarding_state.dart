final class OnboardingState {
  int currentPage; // 0, 1, or 2
  OnboardingState({required this.currentPage});

  OnboardingState copyWith({int? currentPage}) {
    return OnboardingState(currentPage: currentPage ?? this.currentPage);
  }
}