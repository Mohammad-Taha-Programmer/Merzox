import 'dart:ui';

import 'package:share_plus/share_plus.dart';

/// Telling somebody about a shop.
///
/// The mirror of [ProductShareService], with one difference that matters: a
/// product's message says what it is, while a shop's has to be findable. A
/// name alone sends the reader looking through a list of shops; the public id
/// is the one thing that leads to exactly this one, and the app already
/// searches by it.
enum StoreShareOutcome { selected, dismissed }

final class StoreSharePayload {
  final String subject;
  final String message;

  const StoreSharePayload({required this.subject, required this.message});
}

abstract interface class StoreShareGateway {
  Future<StoreShareOutcome> shareStore({
    required String storeName,
    required String category,
    required String publicId,
    required String languageCode,
    Rect? sharePositionOrigin,
  });
}

final class StoreShareService implements StoreShareGateway {
  const StoreShareService();

  StoreSharePayload payloadFor({
    required String storeName,
    required String category,
    required String publicId,
    required String languageCode,
  }) {
    final String name = storeName.trim();
    final String kind = category.trim();
    final String id = publicId.trim();

    if (languageCode == 'en') {
      return StoreSharePayload(
        subject: 'Share $name',
        message: <String>[
          name,
          // Both are left out when empty rather than printed as a label with
          // nothing after it, which is what a shop that has not filled in its
          // category would have looked like.
          if (kind.isNotEmpty) 'Category: $kind',
          if (id.isNotEmpty) 'Store ID: $id',
          if (id.isNotEmpty) 'Find it on Merzox by searching for this ID.',
        ].join('\n'),
      );
    }

    return StoreSharePayload(
      subject: 'مشاركة $name',
      message: <String>[
        name,
        if (kind.isNotEmpty) 'التصنيف: $kind',
        if (id.isNotEmpty) 'رقم المتجر: $id',
        if (id.isNotEmpty) 'ابحث عن هذا الرقم في تطبيق مرزوكس لتصل إليه.',
      ].join('\n'),
    );
  }

  @override
  Future<StoreShareOutcome> shareStore({
    required String storeName,
    required String category,
    required String publicId,
    required String languageCode,
    Rect? sharePositionOrigin,
  }) async {
    final StoreSharePayload payload = payloadFor(
      storeName: storeName,
      category: category,
      publicId: publicId,
      languageCode: languageCode,
    );

    final ShareResult result = await SharePlus.instance.share(
      ShareParams(
        text: payload.message,
        subject: payload.subject,
        title: 'Merzox',
        sharePositionOrigin: sharePositionOrigin,
      ),
    );

    return result.status == ShareResultStatus.dismissed
        ? StoreShareOutcome.dismissed
        : StoreShareOutcome.selected;
  }
}
