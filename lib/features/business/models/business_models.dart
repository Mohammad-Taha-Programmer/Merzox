final class BusinessSocialLinks {
  final String instagram;
  final String whatsapp;
  final String mobile;
  final String facebook;

  const BusinessSocialLinks({
    this.instagram = '',
    this.whatsapp = '',
    this.mobile = '',
    this.facebook = '',
  });

  bool get isEmpty =>
      instagram.isEmpty &&
      whatsapp.isEmpty &&
      mobile.isEmpty &&
      facebook.isEmpty;

  factory BusinessSocialLinks.fromJson(Map<String, dynamic> json) =>
      BusinessSocialLinks(
        instagram: json['instagram'] as String? ?? '',
        whatsapp: json['whatsapp'] as String? ?? '',
        mobile: json['mobile'] as String? ?? '',
        facebook: json['facebook'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
    'instagram': instagram,
    'whatsapp': whatsapp,
    'mobile': mobile,
    'facebook': facebook,
  };
}

final class OwnerBusiness {
  final String id;
  final String name;
  final String englishName;
  final String description;
  final String category;
  final String address;
  final String attachmentUrl;
  final String logoUrl;
  final BusinessSocialLinks socialLinks;

  const OwnerBusiness({
    required this.id,
    required this.name,
    required this.englishName,
    required this.description,
    required this.category,
    required this.address,
    required this.attachmentUrl,
    this.logoUrl = '',
    this.socialLinks = const BusinessSocialLinks(),
  });

  factory OwnerBusiness.fromJson(Map<String, dynamic> json) => OwnerBusiness(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    englishName: json['englishName'] as String? ?? '',
    description: json['description'] as String? ?? '',
    category: json['category'] as String? ?? '',
    address: json['address'] as String? ?? '',
    attachmentUrl: json['attachmentUrl'] as String? ?? '',
    logoUrl: json['logoUrl'] as String? ?? '',
    socialLinks: BusinessSocialLinks.fromJson(
      json['socialLinks'] as Map<String, dynamic>? ?? const {},
    ),
  );
}

final class BusinessEnrollmentResult {
  final OwnerBusiness business;

  const BusinessEnrollmentResult({required this.business});

  factory BusinessEnrollmentResult.fromJson(Map<String, dynamic> json) =>
      BusinessEnrollmentResult(
        business: OwnerBusiness.fromJson(
          json['business'] as Map<String, dynamic>? ?? {},
        ),
      );
}

final class OwnerOrderItem {
  final String productId;
  final String? variantId;
  final String name;
  final int quantity;
  final double unitPrice;
  final String imageUrl;

  /// Immutable purchase-time variant label snapshot.
  final String variant;

  const OwnerOrderItem({
    required this.name,
    required this.quantity,
    this.productId = '',
    this.variantId,
    this.unitPrice = 0,
    this.imageUrl = '',
    this.variant = '',
  });

  double get lineTotal => unitPrice * quantity;

  factory OwnerOrderItem.fromJson(Map<String, dynamic> json) {
    final rawVariantId = json['variantId'];
    final variantId = rawVariantId is String ? rawVariantId.trim() : '';

    return OwnerOrderItem(
      productId: (json['productId'] as String? ?? '').trim(),
      variantId: variantId.isEmpty ? null : variantId,
      name: json['name'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? 0,
      imageUrl: json['imageUrl'] as String? ?? '',
      variant: json['variant'] as String? ?? '',
    );
  }
}

final class OwnerOrderCourier {
  final String name;
  final String phone;

  const OwnerOrderCourier({this.name = '', this.phone = ''});

  bool get isAssigned => name.isNotEmpty;

  factory OwnerOrderCourier.fromJson(Map<String, dynamic> json) =>
      OwnerOrderCourier(
        name: json['name'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
      );
}

final class OwnerOrder {
  final String id;
  final String publicId;
  final String customerName;
  final double total;
  final String status;
  final String statusGroup;
  final DateTime? createdAt;
  final List<OwnerOrderItem> items;
  final String customerPhone;
  final String deliveryAddress;
  final String paymentMethod;
  final double subtotal;
  final double deliveryFee;
  final String currency;
  final String cancellationReason;
  final OwnerOrderCourier courier;

  const OwnerOrder({
    required this.id,
    required this.publicId,
    required this.customerName,
    required this.total,
    required this.status,
    required this.statusGroup,
    required this.createdAt,
    required this.items,
    this.customerPhone = '',
    this.deliveryAddress = '',
    this.paymentMethod = 'cash',
    this.subtotal = 0,
    this.deliveryFee = 0,
    this.currency = 'ILS',
    this.cancellationReason = '',
    this.courier = const OwnerOrderCourier(),
  });

  int get itemCount =>
      items.fold(0, (running, item) => running + item.quantity);

  factory OwnerOrder.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? [];
    return OwnerOrder(
      id: json['id'] as String? ?? '',
      publicId: json['publicId'] as String? ?? '',
      customerName: json['customerName'] as String? ?? '',
      total: (json['total'] as num?)?.toDouble() ?? 0,
      status: json['status'] as String? ?? 'pending',
      statusGroup: json['statusGroup'] as String? ?? 'current',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      items: rawItems
          .whereType<Map<String, dynamic>>()
          .map(OwnerOrderItem.fromJson)
          .toList(),
      customerPhone: json['customerPhone'] as String? ?? '',
      deliveryAddress: json['deliveryAddress'] as String? ?? '',
      paymentMethod: json['paymentMethod'] as String? ?? 'cash',
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0,
      deliveryFee: (json['deliveryFee'] as num?)?.toDouble() ?? 0,
      currency: json['currency'] as String? ?? 'ILS',
      cancellationReason: json['cancellationReason'] as String? ?? '',
      courier: OwnerOrderCourier.fromJson(
        json['courier'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }
}

final class OwnerOrderList {
  final List<OwnerOrder> orders;
  final Map<String, int> counts;
  final bool hasMore;

  /// How many orders match, across every page. `hasMore` alone cannot say how
  /// many pages there are, which is what a page counter has to show.
  final int total;
  final int page;

  const OwnerOrderList({
    required this.orders,
    required this.counts,
    required this.hasMore,
    this.total = 0,
    this.page = 1,
  });

  factory OwnerOrderList.fromJson(Map<String, dynamic> json) {
    final rawOrders = json['orders'] as List<dynamic>? ?? [];
    final rawCounts = json['counts'] as Map<String, dynamic>? ?? {};
    final pagination = json['pagination'] as Map<String, dynamic>? ?? {};
    return OwnerOrderList(
      orders: rawOrders
          .whereType<Map<String, dynamic>>()
          .map(OwnerOrder.fromJson)
          .toList(),
      counts: rawCounts.map(
        (key, value) => MapEntry(key, (value as num?)?.toInt() ?? 0),
      ),
      hasMore: pagination['hasMore'] as bool? ?? false,
      total: (pagination['total'] as num?)?.toInt() ?? rawOrders.length,
      page: (pagination['page'] as num?)?.toInt() ?? 1,
    );
  }
}

final class BusinessDashboardData {
  final double sales;
  final int orderCount;
  final int activeOrderCount;
  final int viewCount;
  final List<OwnerOrder> recentOrders;

  const BusinessDashboardData({
    required this.sales,
    required this.orderCount,
    required this.activeOrderCount,
    required this.viewCount,
    required this.recentOrders,
  });

  factory BusinessDashboardData.fromJson(Map<String, dynamic> json) {
    final rawOrders = json['recentOrders'] as List<dynamic>? ?? [];
    return BusinessDashboardData(
      sales: (json['sales'] as num?)?.toDouble() ?? 0,
      orderCount: (json['orderCount'] as num?)?.toInt() ?? 0,
      activeOrderCount: (json['activeOrderCount'] as num?)?.toInt() ?? 0,
      viewCount: (json['viewCount'] as num?)?.toInt() ?? 0,
      recentOrders: rawOrders
          .whereType<Map<String, dynamic>>()
          .map(OwnerOrder.fromJson)
          .toList(),
    );
  }
}

/// One owner-visible product variant.
///
/// Exact stock and cost remain merchant-only. Effective [price], [finalPrice]
/// and [inStock] are server-derived facts.
final class OwnerProductVariant {
  final String id;
  final String label;
  final double? priceOverride;
  final double? costPrice;
  final int stockQuantity;
  final bool unlimitedStock;
  final bool isActive;
  final double price;
  final double finalPrice;
  final bool inStock;

  const OwnerProductVariant({
    required this.id,
    required this.label,
    required this.price,
    required this.finalPrice,
    required this.inStock,
    this.priceOverride,
    this.costPrice,
    this.stockQuantity = 0,
    this.unlimitedStock = true,
    this.isActive = true,
  });

  factory OwnerProductVariant.fromJson(Map<String, dynamic> json) {
    final price = (json['price'] as num?)?.toDouble() ?? 0;

    return OwnerProductVariant(
      id: (json['id'] as String? ?? '').trim(),
      label: (json['label'] as String? ?? '').trim(),
      priceOverride: (json['priceOverride'] as num?)?.toDouble(),
      costPrice: (json['costPrice'] as num?)?.toDouble(),
      stockQuantity: (json['stockQuantity'] as num?)?.toInt() ?? 0,
      unlimitedStock: json['unlimitedStock'] as bool? ?? true,
      isActive: json['isActive'] as bool? ?? true,
      price: price,
      finalPrice: (json['finalPrice'] as num?)?.toDouble() ?? price,
      inStock: json['inStock'] as bool? ?? true,
    );
  }
}

/// Exact merchant-writable variant state.
///
/// Existing variants retain the server-owned id. Newly added variants omit id.
final class OwnerProductVariantDraft {
  final String? id;
  final String label;
  final double? priceOverride;
  final double? costPrice;
  final int stockQuantity;
  final bool unlimitedStock;
  final bool isActive;

  const OwnerProductVariantDraft({
    required this.label,
    required this.stockQuantity,
    required this.unlimitedStock,
    required this.isActive,
    this.id,
    this.priceOverride,
    this.costPrice,
  });

  factory OwnerProductVariantDraft.fromOwner(OwnerProductVariant variant) {
    return OwnerProductVariantDraft(
      id: variant.id,
      label: variant.label,
      priceOverride: variant.priceOverride,
      costPrice: variant.costPrice,
      stockQuantity: variant.stockQuantity,
      unlimitedStock: variant.unlimitedStock,
      isActive: variant.isActive,
    );
  }

  Map<String, dynamic> toJson() {
    final normalizedId = id?.trim();

    return {
      if (normalizedId != null && normalizedId.isNotEmpty) 'id': normalizedId,
      'label': label.trim(),
      'priceOverride': priceOverride,
      'costPrice': costPrice,
      'unlimitedStock': unlimitedStock,
      if (!unlimitedStock) 'stockQuantity': stockQuantity,
      'isActive': isActive,
    };
  }
}

/// Merchant-facing product truth.
///
/// Private cost/inventory/variant fields stay outside the public customer model.
final class OwnerProduct {
  final String id;
  final String name;
  final String description;
  final double price;
  final double? costPrice;
  final int stockQuantity;
  final bool unlimitedStock;
  final double discountPercent;
  final List<OwnerProductVariant> variants;
  final double finalPrice;
  final bool inStock;
  final List<String> keywords;
  final List<String> imageUrls;
  final String classification;
  final bool isService;
  final bool isActive;

  const OwnerProduct({
    required this.id,
    required this.name,
    this.description = '',
    this.price = 0,
    this.costPrice,
    this.stockQuantity = 0,
    this.unlimitedStock = true,
    this.discountPercent = 0,
    this.variants = const [],
    this.finalPrice = 0,
    this.inStock = true,
    this.keywords = const [],
    this.imageUrls = const [],
    this.classification = 'new',
    this.isService = false,
    this.isActive = true,
  });

  String get imageUrl => imageUrls.isEmpty ? '' : imageUrls.first;

  bool get hasDiscount => discountPercent > 0;

  /// Stored variants define variant mode even when every one is inactive.
  bool get hasVariants => variants.isNotEmpty;

  factory OwnerProduct.fromJson(Map<String, dynamic> json) {
    final rawImages = json['imageUrls'] as List<dynamic>? ?? const [];
    final images = rawImages
        .whereType<String>()
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty)
        .toList();

    final legacyImage = (json['imageUrl'] as String? ?? '').trim();
    if (legacyImage.isNotEmpty && !images.contains(legacyImage)) {
      images.add(legacyImage);
    }

    final rawKeywords = json['keywords'] as List<dynamic>? ?? const [];
    final rawVariants = json['variants'] as List<dynamic>? ?? const [];
    final price = (json['price'] as num?)?.toDouble() ?? 0;

    return OwnerProduct(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      price: price,
      costPrice: (json['costPrice'] as num?)?.toDouble(),
      stockQuantity: (json['stockQuantity'] as num?)?.toInt() ?? 0,
      unlimitedStock: json['unlimitedStock'] as bool? ?? true,
      discountPercent: (json['discountPercent'] as num?)?.toDouble() ?? 0,
      variants: rawVariants
          .whereType<Map<String, dynamic>>()
          .map(OwnerProductVariant.fromJson)
          .toList(growable: false),
      finalPrice: (json['finalPrice'] as num?)?.toDouble() ?? price,
      inStock: json['inStock'] as bool? ?? true,
      keywords: rawKeywords
          .whereType<String>()
          .map((keyword) => keyword.trim())
          .where((keyword) => keyword.isNotEmpty)
          .toList(),
      imageUrls: images,
      classification: json['classification'] as String? ?? 'new',
      isService: json['isService'] as bool? ?? false,
      isActive: json['isActive'] as bool? ?? true,
    );
  }
}

/// Everything the merchant can narrow their order list by.
///
/// `الرئيسية – 9` contributes the free-text search and the status chip;
/// `الرئيسية – 12` adds an order number, a customer name and a date range as
/// separate fields. All are optional and the server intersects them.
final class MerchantOrderFilter {
  /// One status, or null while the chip still reads "order status".
  final String? status;

  /// The browse screen's search field, which matches either the order number
  /// or the customer name.
  final String query;

  /// The sheet's two needles, which match one field each.
  final String orderNumber;
  final String customerName;

  /// Inclusive calendar days. The server extends [to] to the end of its day.
  final DateTime? from;
  final DateTime? to;

  const MerchantOrderFilter({
    this.status,
    this.query = '',
    this.orderNumber = '',
    this.customerName = '',
    this.from,
    this.to,
  });

  /// True when nothing is narrowed, which is what the chip and the sheet both
  /// show on first open.
  bool get isEmpty =>
      status == null &&
      query.isEmpty &&
      orderNumber.isEmpty &&
      customerName.isEmpty &&
      from == null &&
      to == null;

  /// True when the sheet — as opposed to the chip or the search field — is
  /// narrowing the list, which is what the sheet's own indicator reflects.
  bool get hasSheetFields =>
      orderNumber.isNotEmpty ||
      customerName.isNotEmpty ||
      from != null ||
      to != null;

  MerchantOrderFilter copyWith({
    String? status,
    bool clearStatus = false,
    String? query,
    String? orderNumber,
    String? customerName,
    DateTime? from,
    bool clearFrom = false,
    DateTime? to,
    bool clearTo = false,
  }) => MerchantOrderFilter(
    status: clearStatus ? null : status ?? this.status,
    query: query ?? this.query,
    orderNumber: orderNumber ?? this.orderNumber,
    customerName: customerName ?? this.customerName,
    from: clearFrom ? null : from ?? this.from,
    to: clearTo ? null : to ?? this.to,
  );

  /// The query parameters this filter contributes, omitting every field the
  /// merchant left alone so the server never sees an empty needle.
  ///
  /// Dates go as plain calendar days: the merchant picked a day on a
  /// calendar, not an instant, so no time zone is implied either way.
  Map<String, String> toQueryParameters() => <String, String>{
    if (status != null) 'status': status!,
    if (query.isNotEmpty) 'q': query,
    if (orderNumber.isNotEmpty) 'orderNumber': orderNumber,
    if (customerName.isNotEmpty) 'customerName': customerName,
    if (from != null) 'from': _day(from!),
    if (to != null) 'to': _day(to!),
  };

  static String _day(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

/// The create payload for `الرئيسية – 13`'s "duplicate product".
///
/// Only fields the merchant may write are copied, in the exact shape the
/// product editor submits, so a duplicate goes through the same server-side
/// contract as anything typed by hand. Three deliberate omissions:
///
///  * no `id`, on the product or on any variant — a duplicate is a new
///    product, and reusing a variant id would have the server update the
///    original's variant instead of creating one;
///  * no derived money — `finalPrice` and `inStock` are the server's to
///    compute from price, discount and stock;
///  * no history — sales, reviews and likes belong to the product that
///    earned them.
///
/// The copy arrives hidden. A duplicate is a starting point for edits, and
/// publishing it before the merchant has looked at it would put an unedited
/// second listing in front of customers.
Map<String, dynamic> duplicateProductPayload(OwnerProduct product) {
  return <String, dynamic>{
    'name': product.name,
    'description': product.description,
    'price': product.price,
    'costPrice': product.costPrice,
    'unlimitedStock': product.unlimitedStock,
    if (!product.unlimitedStock) 'stockQuantity': product.stockQuantity,
    'discountPercent': product.discountPercent,
    'keywords': product.keywords,
    'imageUrls': product.imageUrls,
    'classification': product.classification,
    'isService': product.isService,
    'isActive': false,
    if (product.variants.isNotEmpty)
      'variants': <Map<String, dynamic>>[
        for (final OwnerProductVariant variant in product.variants)
          OwnerProductVariantDraft(
            label: variant.label,
            priceOverride: variant.priceOverride,
            costPrice: variant.costPrice,
            stockQuantity: variant.stockQuantity,
            unlimitedStock: variant.unlimitedStock,
            isActive: variant.isActive,
          ).toJson(),
      ],
  };
}
