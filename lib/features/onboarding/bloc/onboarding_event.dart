abstract class OnboardingEvent{}

class NextPage extends OnboardingEvent {
  final int page;
  NextPage(this.page);
}

class SkipOnboarding extends OnboardingEvent {}
