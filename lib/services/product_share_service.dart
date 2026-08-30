import 'dart:ui';

import 'package:share_plus/share_plus.dart';

import 'package:merzox/core/constants/money.dart';

enum ProductShareOutcome { selected, dismissed }

final class ProductSharePayload {
  final String subject;
  final String message;

  const ProductSharePayload({required this.subject, required this.message});
}

abstract interface class ProductShareGateway {
  Future<ProductShareOutcome> shareProduct({
    required String productName,
    required String businessName,
    required double displayPrice,
    required String languageCode,
    Rect? sharePositionOrigin,
  });
}

final class ProductShareService implements ProductShareGateway {
  const ProductShareService();

  ProductSharePayload payloadFor({
    required String productName,
    required String businessName,
    required double displayPrice,
    required String languageCode,
  }) {
    final cleanProductName = productName.trim();
    final cleanBusinessName = businessName.trim();

    // Match the price precision currently rendered on ProductDetailsPage.
    final visiblePrice = merzoxAmount(displayPrice);

    if (languageCode == 'en') {
      return ProductSharePayload(
        subject: 'Share $cleanProductName',
        message: [
          cleanProductName,
          'Business: $cleanBusinessName',
          'Price: ₪ $visiblePrice',
        ].join('\n'),
      );
    }

    return ProductSharePayload(
      subject: 'مشاركة $cleanProductName',
      message: [
        cleanProductName,
        'المتجر: $cleanBusinessName',
        'السعر: ₪ $visiblePrice',
      ].join('\n'),
    );
  }

  @override
  Future<ProductShareOutcome> shareProduct({
    required String productName,
    required String businessName,
    required double displayPrice,
    required String languageCode,
    Rect? sharePositionOrigin,
  }) async {
    final payload = payloadFor(
      productName: productName,
      businessName: businessName,
      displayPrice: displayPrice,
      languageCode: languageCode,
    );

    final result = await SharePlus.instance.share(
      ShareParams(
        text: payload.message,
        subject: payload.subject,
        title: 'Merzox',
        sharePositionOrigin: sharePositionOrigin,
      ),
    );

    return result.status == ShareResultStatus.dismissed
        ? ProductShareOutcome.dismissed
        : ProductShareOutcome.selected;
  }
}
