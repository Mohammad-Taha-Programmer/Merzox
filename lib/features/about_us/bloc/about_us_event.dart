sealed class AboutUsEvent {
  const AboutUsEvent();
}

final class AboutUsStarted extends AboutUsEvent {
  final String languageCode;

  const AboutUsStarted(this.languageCode);
}

final class AboutUsRefreshRequested extends AboutUsEvent {
  const AboutUsRefreshRequested();
}

final class AboutUsSectionToggled extends AboutUsEvent {
  final String sectionKey;

  const AboutUsSectionToggled(this.sectionKey);
}
