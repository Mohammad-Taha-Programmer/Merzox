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
  final String name;
  final int quantity;
  final double unitPrice;
  final String imageUrl;
  final String variant;

  const OwnerOrderItem({
    required this.name,
    required this.quantity,
    this.unitPrice = 0,
    this.imageUrl = '',
    this.variant = '',
  });

  double get lineTotal => unitPrice * quantity;

  factory OwnerOrderItem.fromJson(Map<String, dynamic> json) => OwnerOrderItem(
    name: json['name'] as String? ?? '',
    quantity: (json['quantity'] as num?)?.toInt() ?? 0,
    unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? 0,
    imageUrl: json['imageUrl'] as String? ?? '',
    variant: json['variant'] as String? ?? '',
  );
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

  const OwnerOrderList({
    required this.orders,
    required this.counts,
    required this.hasMore,
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
