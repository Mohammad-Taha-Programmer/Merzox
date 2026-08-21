import '../../../services/share_app_service.dart';

enum ShareAppStatus { initial, ready, sharing, success, failure }

final class ShareAppState {
  final ShareAppStatus status;
  final String languageCode;
  final ShareAppStoreInfo? store;
  final ShareAppPayload? payload;
  final ShareAppTarget? activeTarget;
  final String messageCode;

  const ShareAppState({
    this.status = ShareAppStatus.initial,
    this.languageCode = 'ar',
    this.store,
    this.payload,
    this.activeTarget,
    this.messageCode = '',
  });

  ShareAppState copyWith({
    ShareAppStatus? status,
    String? languageCode,
    ShareAppStoreInfo? store,
    ShareAppPayload? payload,
    ShareAppTarget? activeTarget,
    bool clearActiveTarget = false,
    String? messageCode,
  }) {
    return ShareAppState(
      status: status ?? this.status,
      languageCode: languageCode ?? this.languageCode,
      store: store ?? this.store,
      payload: payload ?? this.payload,
      activeTarget: clearActiveTarget
          ? null
          : activeTarget ?? this.activeTarget,
      messageCode: messageCode ?? this.messageCode,
    );
  }
}
