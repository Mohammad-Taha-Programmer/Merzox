import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

enum ShareAppTarget { whatsapp, messenger, instagram, telegram, email, system }

enum ShareAppOutcome { launched, selected, dismissed }

final class ShareAppStoreInfo {
  final Uri uri;
  final String storeName;
  final bool isAppleStore;

  const ShareAppStoreInfo({
    required this.uri,
    required this.storeName,
    required this.isAppleStore,
  });
}

final class ShareAppPayload {
  final String subject;
  final String message;

  const ShareAppPayload({required this.subject, required this.message});
}

class ShareAppService {
  static const _androidPackageId = String.fromEnvironment(
    'MERZOX_ANDROID_PACKAGE_ID',
    defaultValue: 'com.example.merzox',
  );
  static const _configuredPlayStoreUrl = String.fromEnvironment(
    'MERZOX_PLAY_STORE_URL',
  );
  static const _iosAppStoreId = String.fromEnvironment(
    'MERZOX_IOS_APP_STORE_ID',
  );
  static const _configuredAppStoreUrl = String.fromEnvironment(
    'MERZOX_APP_STORE_URL',
  );

  ShareAppStoreInfo currentStore() {
    final useAppleStore =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    if (useAppleStore) {
      return ShareAppStoreInfo(
        uri: _appleStoreUri(),
        storeName: 'App Store',
        isAppleStore: true,
      );
    }

    return ShareAppStoreInfo(
      uri: _playStoreUri(),
      storeName: 'Google Play',
      isAppleStore: false,
    );
  }

  ShareAppPayload payloadFor({
    required String languageCode,
    required Uri storeUri,
  }) {
    if (languageCode == 'en') {
      return ShareAppPayload(
        subject: 'Try Merzox',
        message:
            'Discover nearby businesses, products, and services with Merzox.\n${storeUri.toString()}',
      );
    }

    return ShareAppPayload(
      subject: 'جرّب تطبيق Merzox',
      message:
          'اكتشف المتاجر والمنتجات والخدمات القريبة منك عبر تطبيق Merzox.\n${storeUri.toString()}',
    );
  }

  Future<ShareAppOutcome> share({
    required ShareAppTarget target,
    required ShareAppStoreInfo store,
    required ShareAppPayload payload,
    Rect? sharePositionOrigin,
  }) async {
    return switch (target) {
      ShareAppTarget.whatsapp => _launchOrShare(
        Uri.https('wa.me', '/', {'text': payload.message}),
        payload,
        sharePositionOrigin,
      ),
      ShareAppTarget.messenger => _launchOrShare(
        Uri(
          scheme: 'fb-messenger',
          host: 'share',
          path: '/',
          queryParameters: {'link': store.uri.toString()},
        ),
        payload,
        sharePositionOrigin,
      ),
      ShareAppTarget.instagram => _shareWithSystem(
        payload,
        sharePositionOrigin,
      ),
      ShareAppTarget.telegram => _launchOrShare(
        Uri.https('t.me', '/share/url', {
          'url': store.uri.toString(),
          'text': payload.subject,
        }),
        payload,
        sharePositionOrigin,
      ),
      ShareAppTarget.email => _launchOrShare(
        Uri(
          scheme: 'mailto',
          query: _encodeQueryParameters({
            'subject': payload.subject,
            'body': payload.message,
          }),
        ),
        payload,
        sharePositionOrigin,
      ),
      ShareAppTarget.system => _shareWithSystem(payload, sharePositionOrigin),
    };
  }

  Future<void> copyStoreLink(ShareAppStoreInfo store) {
    return Clipboard.setData(ClipboardData(text: store.uri.toString()));
  }

  Future<bool> openStore(ShareAppStoreInfo store) async {
    try {
      return await launchUrl(store.uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  Future<ShareAppOutcome> _launchOrShare(
    Uri uri,
    ShareAppPayload payload,
    Rect? sharePositionOrigin,
  ) async {
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (launched) return ShareAppOutcome.launched;
    } catch (_) {
      // The native share sheet remains available when a target app is absent.
    }

    return _shareWithSystem(payload, sharePositionOrigin);
  }

  Future<ShareAppOutcome> _shareWithSystem(
    ShareAppPayload payload,
    Rect? sharePositionOrigin,
  ) async {
    final result = await SharePlus.instance.share(
      ShareParams(
        text: payload.message,
        subject: payload.subject,
        title: 'Merzox',
        sharePositionOrigin: sharePositionOrigin,
      ),
    );

    return result.status == ShareResultStatus.dismissed
        ? ShareAppOutcome.dismissed
        : ShareAppOutcome.selected;
  }

  Uri _playStoreUri() {
    final configured = _safeHttpsUri(_configuredPlayStoreUrl);
    if (configured != null) return configured;

    final packageId =
        RegExp(
          r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$',
        ).hasMatch(_androidPackageId)
        ? _androidPackageId
        : 'com.example.merzox';
    return Uri.https('play.google.com', '/store/apps/details', {
      'id': packageId,
    });
  }

  Uri _appleStoreUri() {
    final configured = _safeHttpsUri(_configuredAppStoreUrl);
    if (configured != null) return configured;

    final appStoreId = _iosAppStoreId.replaceFirst(RegExp(r'^id'), '');
    if (RegExp(r'^\d{6,}$').hasMatch(appStoreId)) {
      return Uri.https('apps.apple.com', '/app/id$appStoreId');
    }

    return Uri.https('apps.apple.com', '/us/search', {'term': 'Merzox'});
  }

  Uri? _safeHttpsUri(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    return uri;
  }

  String _encodeQueryParameters(Map<String, String> parameters) {
    return parameters.entries
        .map(
          (entry) =>
              '${Uri.encodeComponent(entry.key)}=${Uri.encodeComponent(entry.value)}',
        )
        .join('&');
  }
}
