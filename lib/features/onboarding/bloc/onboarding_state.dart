final class OnboardingState {
  final int currentPage;
  final bool isCompleted;

  const OnboardingState({required this.currentPage, this.isCompleted = false});

  OnboardingState copyWith({int? currentPage, bool? isCompleted}) {
    return OnboardingState(
      currentPage: currentPage ?? this.currentPage,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
}
