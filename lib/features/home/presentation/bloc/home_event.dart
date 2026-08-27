sealed class HomeEvent {
  const HomeEvent();
}

enum HomeCatalogSection { newest, best, offers, nearby, all }

final class HomeStarted extends HomeEvent {
  final bool isGuest;
  final int initialTab;

  const HomeStarted({required this.isGuest, this.initialTab = 0});
}

final class HomeRecommendationsRefreshRequested extends HomeEvent {
  const HomeRecommendationsRefreshRequested();
}

final class HomeSearchChanged extends HomeEvent {
  final String query;

  const HomeSearchChanged(this.query);
}

final class HomeTabChanged extends HomeEvent {
  final int index;

  const HomeTabChanged(this.index);
}

final class HomeLocationPromptShown extends HomeEvent {
  const HomeLocationPromptShown();
}

final class HomeLocationServiceRequested extends HomeEvent {
  final String reason;

  const HomeLocationServiceRequested({required this.reason});
}

final class HomeLocationPermissionAnswered extends HomeEvent {
  final bool granted;

  const HomeLocationPermissionAnswered({required this.granted});
}

final class HomeBusinessFollowToggled extends HomeEvent {
  final String businessId;

  const HomeBusinessFollowToggled(this.businessId);
}

final class HomeAllBusinessesNextPageRequested extends HomeEvent {
  const HomeAllBusinessesNextPageRequested();
}

final class HomeCatalogSectionRetryRequested extends HomeEvent {
  final HomeCatalogSection section;

  const HomeCatalogSectionRetryRequested(this.section);
}
