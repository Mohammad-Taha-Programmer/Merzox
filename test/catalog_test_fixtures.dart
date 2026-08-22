import 'package:merzox/services/api_service.dart';

SearchBusinessApiModel catalogBusiness({
  String id = '64b000000000000000000001',
  String publicId = 'MXB-0001',
  String name = 'Test business',
  String category = 'Test category',
  String? discount,
  int? distanceMeters,
  double rating = 4.5,
}) {
  return SearchBusinessApiModel(
    id: id,
    publicId: publicId,
    name: name,
    englishName: name,
    category: category,
    products: const ['Test product'],
    productCount: 1,
    rating: rating,
    ratingCount: 4,
    followerCount: 8,
    viewCount: 12,
    discount: discount,
    colorValue: 0xffdeeef8,
    address: 'Test address',
    distanceMeters: distanceMeters,
    latitude: distanceMeters == null ? null : 31.9,
    longitude: distanceMeters == null ? null : 35.2,
    subscribedAt: DateTime.utc(2026, 1, 1),
  );
}

BusinessListApiResponse businessPage({
  List<SearchBusinessApiModel> businesses = const [],
  int page = 1,
  int limit = 10,
  bool hasMore = false,
  int? total,
}) {
  return BusinessListApiResponse(
    businesses: businesses,
    page: page,
    limit: limit,
    total: total ?? businesses.length,
    hasMore: hasMore,
  );
}

BusinessProductApiModel catalogProduct({
  String id = '64c000000000000000000001',
  String name = 'Test product',
  String description = '',
  double price = 25,
  double discountPercent = 0,
  double? finalPrice,
  bool inStock = true,
}) {
  return BusinessProductApiModel(
    id: id,
    name: name,
    description: description,
    price: price,
    discountPercent: discountPercent,
    finalPrice: finalPrice,
    inStock: inStock,
    imageUrl: '',
    imageUrls: const [],
    classification: 'new',
    rating: 0,
    ratingCount: 0,
    likeCount: 0,
  );
}

/// A PUBLIC product payload exactly as `Business.productToJSON` emits it.
///
/// Tests parse this rather than constructing the model, so a change to the
/// required commerce contract is caught here instead of being papered over by
/// constructor defaults.
Map<String, dynamic> catalogProductJson({
  String id = '64c000000000000000000001',
  String name = 'Test product',
  double price = 25,
  double discountPercent = 0,
  double? finalPrice,
  bool inStock = true,
}) {
  return <String, dynamic>{
    'id': id,
    'name': name,
    'description': '',
    'price': price,
    'discountPercent': discountPercent,
    'finalPrice': finalPrice ?? price,
    'inStock': inStock,
    'imageUrl': '',
    'imageUrls': const <String>[],
    'classification': 'new',
    'rating': 0,
    'ratingCount': 0,
    'likeCount': 0,
    'isService': false,
  };
}

BusinessDetailApiModel catalogBusinessDetail({
  String id = '64b000000000000000000001',
  List<BusinessProductApiModel> products = const [],
}) {
  return BusinessDetailApiModel(
    id: id,
    publicId: 'MXB-0001',
    name: 'Test business',
    englishName: 'Test business',
    category: 'Test category',
    description: '',
    address: 'Test address',
    products: products,
    productCount: products.length,
    rating: 0,
    ratingCount: 0,
    followerCount: 0,
    viewCount: 0,
    discount: null,
    colorValue: 0xffdeeef8,
  );
}
