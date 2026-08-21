import 'dart:ui';

import '../../../services/share_app_service.dart';

sealed class ShareAppEvent {
  const ShareAppEvent();
}

final class ShareAppStarted extends ShareAppEvent {
  final String languageCode;

  const ShareAppStarted(this.languageCode);
}

final class ShareAppTargetRequested extends ShareAppEvent {
  final ShareAppTarget target;
  final Rect? sharePositionOrigin;

  const ShareAppTargetRequested(this.target, {this.sharePositionOrigin});
}

final class ShareAppLinkCopied extends ShareAppEvent {
  const ShareAppLinkCopied();
}

final class ShareAppStoreOpened extends ShareAppEvent {
  const ShareAppStoreOpened();
}
