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

BusinessProductVariantApiModel catalogVariant({
  String id = '64d000000000000000000001',
  String label = 'Variant',
  double price = 25,
  double? finalPrice,
  bool inStock = true,
}) {
  return BusinessProductVariantApiModel(
    id: id,
    label: label,
    price: price,
    finalPrice: finalPrice ?? price,
    inStock: inStock,
  );
}

Map<String, dynamic> catalogVariantJson({
  String id = '64d000000000000000000001',
  String label = 'Variant',
  double price = 25,
  double? finalPrice,
  bool inStock = true,
}) {
  return <String, dynamic>{
    'id': id,
    'label': label,
    'price': price,
    'finalPrice': finalPrice ?? price,
    'inStock': inStock,
  };
}

BusinessProductApiModel catalogProduct({
  String id = '64c000000000000000000001',
  String name = 'Test product',
  String description = '',
  double price = 25,
  double discountPercent = 0,
  double? finalPrice,
  bool inStock = true,
  bool hasVariants = false,
  List<BusinessProductVariantApiModel> variants = const [],
  double? minPrice,
  double? maxPrice,
  double? minFinalPrice,
  double? maxFinalPrice,
}) {
  final payable = finalPrice ?? price;

  return BusinessProductApiModel(
    id: id,
    name: name,
    description: description,
    price: price,
    discountPercent: discountPercent,
    finalPrice: payable,
    inStock: inStock,
    hasVariants: hasVariants,
    variants: variants,
    minPrice: hasVariants ? minPrice : (minPrice ?? price),
    maxPrice: hasVariants ? maxPrice : (maxPrice ?? price),
    minFinalPrice: hasVariants ? minFinalPrice : (minFinalPrice ?? payable),
    maxFinalPrice: hasVariants ? maxFinalPrice : (maxFinalPrice ?? payable),
    imageUrl: '',
    imageUrls: const [],
    classification: 'new',
    rating: 0,
    ratingCount: 0,
    likeCount: 0,
  );
}

/// A PUBLIC product payload exactly as `Business.productToJSON` emits it.
Map<String, dynamic> catalogProductJson({
  String id = '64c000000000000000000001',
  String name = 'Test product',
  double price = 25,
  double discountPercent = 0,
  double? finalPrice,
  bool inStock = true,
  bool hasVariants = false,
  List<Map<String, dynamic>> variants = const [],
  double? minPrice,
  double? maxPrice,
  double? minFinalPrice,
  double? maxFinalPrice,
}) {
  final payable = finalPrice ?? price;

  return <String, dynamic>{
    'id': id,
    'name': name,
    'description': '',
    'price': price,
    'discountPercent': discountPercent,
    'finalPrice': payable,
    'inStock': inStock,
    'hasVariants': hasVariants,
    'variants': variants,
    'minPrice': hasVariants ? minPrice : (minPrice ?? price),
    'maxPrice': hasVariants ? maxPrice : (maxPrice ?? price),
    'minFinalPrice': hasVariants ? minFinalPrice : (minFinalPrice ?? payable),
    'maxFinalPrice': hasVariants ? maxFinalPrice : (maxFinalPrice ?? payable),
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
