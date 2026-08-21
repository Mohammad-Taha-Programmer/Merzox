import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:merzox/features/business/models/business_models.dart';

final String ipAddress = "192.168.1.8";

class ApiService {
  static const String configuredBaseUrl = String.fromEnvironment(
    'MERZOX_API_BASE_URL',
    defaultValue: '',
  );

  static String get defaultBaseUrl {
    if (configuredBaseUrl.isNotEmpty) {
      return configuredBaseUrl;
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://$ipAddress:4000/api/v1';
    }

    return 'http://$ipAddress:4000/api/v1';
  }

  final Dio _dio;

  ApiService({Dio? dio, String? baseUrl})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: baseUrl ?? defaultBaseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
              headers: {'Content-Type': 'application/json'},
            ),
          );

  Future<AuthApiResponse> login({
    required String identifier,
    required String password,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/login',
      data: {'identifier': identifier, 'password': password},
    );

    return AuthApiResponse.fromJson(response.data ?? {});
  }

  Future<AuthApiUser> me({required String token}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/auth/me',
      options: _authOptions(token),
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? {};
    final user = data['user'] as Map<String, dynamic>? ?? {};

    return AuthApiUser.fromJson(user);
  }

  Future<AuthApiUser> updateProfile({
    required String token,
    String? name,
    String? gender,
    String? address,
    List<ContactEmail>? emails,
    List<ContactPhone>? phones,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/users/me',
      data: {
        if (name != null) 'name': name,
        if (gender != null) 'gender': gender,
        if (address != null) 'address': address,
        if (emails != null)
          'emails': emails.map((email) => email.toJson()).toList(),
        if (phones != null)
          'phones': phones.map((phone) => phone.toJson()).toList(),
      },
      options: _authOptions(token),
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? {};
    final user = data['user'] as Map<String, dynamic>? ?? {};

    return AuthApiUser.fromJson(user);
  }

  Future<AuthApiUser> updatePermissions({
    required String token,
    bool? location,
    bool? aiPersonalization,
    bool? contacts,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/users/me',
      data: {
        'permissions': {
          if (location != null) 'location': location,
          if (aiPersonalization != null) 'aiPersonalization': aiPersonalization,
          if (contacts != null) 'contacts': contacts,
        },
      },
      options: _authOptions(token),
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? {};
    final user = data['user'] as Map<String, dynamic>? ?? {};

    return AuthApiUser.fromJson(user);
  }

  Future<BusinessListApiResponse> businesses({
    int page = 1,
    int limit = 100,
    String? search,
    double? latitude,
    double? longitude,
    int? radiusMeters,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/businesses',
      queryParameters: {
        'page': page,
        'limit': limit,
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
        if (latitude != null) 'lat': latitude,
        if (longitude != null) 'lng': longitude,
        if (radiusMeters != null) 'radiusMeters': radiusMeters,
      },
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? {};

    return BusinessListApiResponse.fromJson(data);
  }

  Future<FavoriteBusinessListApiResponse> favoriteBusinesses({
    required String token,
    int page = 1,
    int limit = 20,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/favorites/businesses',
      queryParameters: {'page': page, 'limit': limit},
      options: _authOptions(token),
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? {};

    return FavoriteBusinessListApiResponse.fromJson(data);
  }

  Future<FavoriteProductListApiResponse> favoriteProducts({
    required String token,
    int page = 1,
    int limit = 20,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/favorites/products',
      queryParameters: {'page': page, 'limit': limit},
      options: _authOptions(token),
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? {};

    return FavoriteProductListApiResponse.fromJson(data);
  }

  Future<FavoriteStatusApiResponse> favoriteStatus({
    required String token,
    required String businessId,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/favorites/businesses/$businessId/status',
      options: _authOptions(token),
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? {};

    return FavoriteStatusApiResponse.fromJson(data);
  }

  Future<bool> setBusinessFavorited({
    required String token,
    required String businessId,
    required bool favorited,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/businesses/$businessId/favorite',
      data: {'favorited': favorited},
      options: _authOptions(token),
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? {};

    return data['favorited'] as bool? ?? favorited;
  }

  Future<OrderListApiResponse> orders({
    required String token,
    required String status,
    int page = 1,
    int limit = 20,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/orders',
      queryParameters: {'status': status, 'page': page, 'limit': limit},
      options: _authOptions(token),
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? {};

    return OrderListApiResponse.fromJson(data);
  }

  Future<OrderApiModel> createOrder({
    required String token,
    required String businessId,
    required List<OrderItemRequest> items,
    required String deliveryAddress,
    String paymentMethod = 'cash',
    String? clientOrderId,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/orders',
      data: {
        'businessId': businessId,
        'items': items.map((item) => item.toJson()).toList(),
        'deliveryAddress': deliveryAddress,
        'paymentMethod': paymentMethod,
        if (clientOrderId != null) 'clientOrderId': clientOrderId,
      },
      options: _authOptions(token),
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? {};
    final order = data['order'] as Map<String, dynamic>? ?? {};

    return OrderApiModel.fromJson(order);
  }

  Future<OrderApiModel> cancelOrder({
    required String token,
    required String orderId,
    String reason = '',
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/orders/$orderId/cancel',
      data: {'reason': reason},
      options: _authOptions(token),
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? {};
    final order = data['order'] as Map<String, dynamic>? ?? {};

    return OrderApiModel.fromJson(order);
  }

  Future<List<BusinessProductApiModel>> businessProducts({
    required String businessId,
    required String classification,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/businesses/$businessId/products',
      queryParameters: {'classification': classification},
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? {};
    final products = data['products'] as List<dynamic>? ?? [];

    return products
        .whereType<Map<String, dynamic>>()
        .map(BusinessProductApiModel.fromJson)
        .toList();
  }

  Future<List<BusinessReviewApiModel>> businessReviews({
    required String businessId,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/businesses/$businessId/reviews',
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? {};
    final reviews = data['reviews'] as List<dynamic>? ?? [];

    return reviews
        .whereType<Map<String, dynamic>>()
        .map(BusinessReviewApiModel.fromJson)
        .toList();
  }

  Future<BusinessProductApiModel> businessProduct({
    required String businessId,
    required String productId,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/businesses/$businessId/products/$productId',
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? {};
    final product = data['product'] as Map<String, dynamic>? ?? {};

    return BusinessProductApiModel.fromJson(product);
  }

  Future<List<BusinessReviewApiModel>> productReviews({
    required String businessId,
    required String productId,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/businesses/$businessId/products/$productId/reviews',
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? {};
    final reviews = data['reviews'] as List<dynamic>? ?? [];

    return reviews
        .whereType<Map<String, dynamic>>()
        .map(BusinessReviewApiModel.fromJson)
        .toList();
  }

  Future<BusinessProductApiModel> setProductLiked({
    required String token,
    required String businessId,
    required String productId,
    required bool liked,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/businesses/$businessId/products/$productId/like',
      data: {'liked': liked},
      options: _authOptions(token),
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? {};
    final product = data['product'] as Map<String, dynamic>? ?? {};

    return BusinessProductApiModel.fromJson(product);
  }

  Future<BusinessReviewApiModel> submitBusinessReview({
    required String token,
    required String businessId,
    required int rating,
    required String comment,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/businesses/$businessId/reviews',
      data: {'rating': rating, 'comment': comment},
      options: _authOptions(token),
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? {};
    final review = data['review'] as Map<String, dynamic>? ?? {};

    return BusinessReviewApiModel.fromJson(review);
  }

  Future<ProductReviewSubmitResponse> submitProductReview({
    required String token,
    required String businessId,
    required String productId,
    required int rating,
    required String comment,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/businesses/$businessId/products/$productId/reviews',
      data: {'rating': rating, 'comment': comment},
      options: _authOptions(token),
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? {};
    final review = data['review'] as Map<String, dynamic>? ?? {};
    final product = data['product'] as Map<String, dynamic>? ?? {};

    return ProductReviewSubmitResponse(
      review: BusinessReviewApiModel.fromJson(review),
      product: BusinessProductApiModel.fromJson(product),
    );
  }

  Future<SearchApiResponse> searchCatalog({
    required String query,
    int limit = 30,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/search',
      queryParameters: {'query': query, 'limit': limit},
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? {};

    return SearchApiResponse.fromJson(data);
  }

  Future<AboutUsApiModel> aboutUs({required String languageCode}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/content/about-us',
      queryParameters: {'lang': languageCode == 'en' ? 'en' : 'ar'},
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? {};
    final aboutUs = data['aboutUs'] as Map<String, dynamic>? ?? {};

    return AboutUsApiModel.fromJson(aboutUs);
  }

  Future<SignupApiResponse> signup({
    required String name,
    String? email,
    String? phone,
    required String password,
    required String userType,
    String address = '',
    String gender = 'unspecified',
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/signup',
      data: {
        'name': name,
        if (email != null) 'email': email,
        if (phone != null) 'phone': phone,
        'password': password,
        'address': address,
        'userType': userType,
        'gender': gender,
      },
    );

    return SignupApiResponse.fromJson(response.data ?? {});
  }

  Future<BusinessEnrollmentResult> enrollBusiness({
    required String token,
    required String phone,
    required String email,
    required String currentPassword,
    required String name,
    required String englishName,
    required String description,
    required String category,
    required String address,
    required String attachmentUrl,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/businesses/enroll',
      data: {
        'phone': phone,
        'email': email,
        'currentPassword': currentPassword,
        'name': name,
        'englishName': englishName,
        'description': description,
        'category': category,
        'address': address,
        'attachmentUrl': attachmentUrl,
      },
      options: _authOptions(token),
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? {};
    return BusinessEnrollmentResult.fromJson(data);
  }

  Future<OwnerBusiness> ownerBusiness({required String token}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/businesses/me',
      options: _authOptions(token),
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? {};
    return OwnerBusiness.fromJson(
      data['business'] as Map<String, dynamic>? ?? {},
    );
  }

  Future<OwnerBusiness> updateOwnerBusiness({
    required String token,
    required Map<String, dynamic> changes,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/businesses/me',
      data: changes,
      options: _authOptions(token),
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? {};
    return OwnerBusiness.fromJson(
      data['business'] as Map<String, dynamic>? ?? {},
    );
  }

  Future<BusinessDashboardData> businessDashboard({
    required String token,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/businesses/me/dashboard',
      options: _authOptions(token),
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? {};
    return BusinessDashboardData.fromJson(
      data['dashboard'] as Map<String, dynamic>? ?? {},
    );
  }

  Future<OwnerOrderList> ownerOrders({
    required String token,
    String statusGroup = 'current',
    int page = 1,
    int limit = 30,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/businesses/me/orders',
      queryParameters: {
        'statusGroup': statusGroup,
        'page': page,
        'limit': limit,
      },
      options: _authOptions(token),
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? {};
    return OwnerOrderList.fromJson(data);
  }

  Future<OwnerOrder> updateOwnerOrderStatus({
    required String token,
    required String orderId,
    required String status,
    String note = '',
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/businesses/me/orders/$orderId/status',
      data: {'status': status, 'note': note},
      options: _authOptions(token),
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? {};
    return OwnerOrder.fromJson(data['order'] as Map<String, dynamic>? ?? {});
  }

  Future<List<BusinessProductApiModel>> ownerProducts({
    required String token,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/businesses/me/products',
      options: _authOptions(token),
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? {};
    final products = data['products'] as List<dynamic>? ?? [];
    return products
        .whereType<Map<String, dynamic>>()
        .map(BusinessProductApiModel.fromJson)
        .toList();
  }

  Future<BusinessProductApiModel> createOwnerProduct({
    required String token,
    required Map<String, dynamic> product,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/businesses/me/products',
      data: product,
      options: _authOptions(token),
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? {};
    return BusinessProductApiModel.fromJson(
      data['product'] as Map<String, dynamic>? ?? {},
    );
  }

  Future<BusinessProductApiModel> updateOwnerProduct({
    required String token,
    required String productId,
    required Map<String, dynamic> changes,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/businesses/me/products/$productId',
      data: changes,
      options: _authOptions(token),
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? {};
    return BusinessProductApiModel.fromJson(
      data['product'] as Map<String, dynamic>? ?? {},
    );
  }

  Future<void> deleteOwnerProduct({
    required String token,
    required String productId,
  }) async {
    await _dio.delete<void>(
      '/businesses/me/products/$productId',
      options: _authOptions(token),
    );
  }

  static String messageFromError(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map<String, dynamic>) {
        final errorBody = data['error'];
        if (errorBody is Map<String, dynamic> &&
            errorBody['message'] is String) {
          return errorBody['message'] as String;
        }
      }

      if (error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout) {
        return 'تعذر الاتصال بالخادم. تأكد من تشغيل Backend Merzox.';
      }
    }

    return 'حدث خطأ غير متوقع، حاول مرة أخرى';
  }

  Options _authOptions(String token) {
    return Options(headers: {'Authorization': 'Bearer $token'});
  }
}

class BusinessProductApiModel {
  final String id;
  final String name;
  final String description;
  final double price;
  final String imageUrl;
  final List<String> imageUrls;
  final String classification;
  final double rating;
  final int ratingCount;
  final int likeCount;
  final bool isService;

  const BusinessProductApiModel({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.imageUrl,
    required this.imageUrls,
    required this.classification,
    required this.rating,
    required this.ratingCount,
    required this.likeCount,
    this.isService = false,
  });

  factory BusinessProductApiModel.fromJson(Map<String, dynamic> json) {
    final rawImageUrls = json['imageUrls'] as List<dynamic>? ?? [];
    final parsedImageUrls = rawImageUrls
        .whereType<String>()
        .where((url) => url.trim().isNotEmpty)
        .toList();
    final legacyImageUrl = json['imageUrl'] as String? ?? '';
    final imageUrls = <String>[
      ...parsedImageUrls,
      if (legacyImageUrl.isNotEmpty &&
          !parsedImageUrls.contains(legacyImageUrl))
        legacyImageUrl,
    ];

    return BusinessProductApiModel(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0,
      imageUrl: imageUrls.isEmpty ? '' : imageUrls.first,
      imageUrls: imageUrls,
      classification: json['classification'] as String? ?? 'new',
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      ratingCount: (json['ratingCount'] as num?)?.toInt() ?? 0,
      likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
      isService: json['isService'] as bool? ?? false,
    );
  }
}

class ProductReviewSubmitResponse {
  final BusinessReviewApiModel review;
  final BusinessProductApiModel product;

  const ProductReviewSubmitResponse({
    required this.review,
    required this.product,
  });
}

class SearchApiResponse {
  final String query;
  final List<SearchProductApiModel> products;
  final List<SearchBusinessApiModel> businesses;

  const SearchApiResponse({
    required this.query,
    required this.products,
    required this.businesses,
  });

  factory SearchApiResponse.fromJson(Map<String, dynamic> json) {
    final productsJson = json['products'] as List<dynamic>? ?? [];
    final businessesJson = json['businesses'] as List<dynamic>? ?? [];

    return SearchApiResponse(
      query: json['query'] as String? ?? '',
      products: productsJson
          .whereType<Map<String, dynamic>>()
          .map(SearchProductApiModel.fromJson)
          .toList(),
      businesses: businessesJson
          .whereType<Map<String, dynamic>>()
          .map(SearchBusinessApiModel.fromJson)
          .toList(),
    );
  }
}

class SearchProductApiModel {
  final BusinessProductApiModel product;
  final SearchBusinessApiModel business;

  const SearchProductApiModel({required this.product, required this.business});

  factory SearchProductApiModel.fromJson(Map<String, dynamic> json) {
    final businessJson = json['business'] as Map<String, dynamic>? ?? {};

    return SearchProductApiModel(
      product: BusinessProductApiModel.fromJson(json),
      business: SearchBusinessApiModel.fromJson(businessJson),
    );
  }
}

class SearchBusinessApiModel {
  final String id;
  final String publicId;
  final String name;
  final String category;
  final List<String> products;
  final double rating;
  final int colorValue;
  final String address;
  final int? distanceMeters;
  final double? latitude;
  final double? longitude;

  const SearchBusinessApiModel({
    required this.id,
    required this.publicId,
    required this.name,
    required this.category,
    required this.products,
    required this.rating,
    required this.colorValue,
    required this.address,
    this.distanceMeters,
    this.latitude,
    this.longitude,
  });

  factory SearchBusinessApiModel.fromJson(Map<String, dynamic> json) {
    final productsJson = json['products'] as List<dynamic>? ?? [];
    final location = json['location'] as Map<String, dynamic>?;
    final coordinates = location?['coordinates'] as List<dynamic>? ?? [];

    return SearchBusinessApiModel(
      id: json['id'] as String? ?? '',
      publicId: json['publicId'] as String? ?? '',
      name: json['name'] as String? ?? '',
      category: json['category'] as String? ?? '',
      products: productsJson.whereType<String>().toList(),
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      colorValue: (json['colorValue'] as num?)?.toInt() ?? 0xffdeeef8,
      address: json['address'] as String? ?? '',
      distanceMeters: (json['distanceMeters'] as num?)?.toInt(),
      longitude: coordinates.isNotEmpty
          ? (coordinates[0] as num?)?.toDouble()
          : null,
      latitude: coordinates.length > 1
          ? (coordinates[1] as num?)?.toDouble()
          : null,
    );
  }
}

class BusinessListApiResponse {
  final List<SearchBusinessApiModel> businesses;
  final int page;
  final int limit;
  final int total;
  final bool hasMore;

  const BusinessListApiResponse({
    required this.businesses,
    required this.page,
    required this.limit,
    required this.total,
    required this.hasMore,
  });

  factory BusinessListApiResponse.fromJson(Map<String, dynamic> json) {
    final businessesJson = json['businesses'] as List<dynamic>? ?? [];
    final pagination = json['pagination'] as Map<String, dynamic>? ?? {};

    return BusinessListApiResponse(
      businesses: businessesJson
          .whereType<Map<String, dynamic>>()
          .map(SearchBusinessApiModel.fromJson)
          .toList(),
      page: (pagination['page'] as num?)?.toInt() ?? 1,
      limit: (pagination['limit'] as num?)?.toInt() ?? 100,
      total: (pagination['total'] as num?)?.toInt() ?? 0,
      hasMore: pagination['hasMore'] as bool? ?? false,
    );
  }
}

class FavoriteBusinessListApiResponse {
  final List<SearchBusinessApiModel> businesses;
  final int page;
  final int total;
  final bool hasMore;

  const FavoriteBusinessListApiResponse({
    required this.businesses,
    required this.page,
    required this.total,
    required this.hasMore,
  });

  factory FavoriteBusinessListApiResponse.fromJson(Map<String, dynamic> json) {
    final businesses = json['businesses'] as List<dynamic>? ?? [];
    final pagination = json['pagination'] as Map<String, dynamic>? ?? {};

    return FavoriteBusinessListApiResponse(
      businesses: businesses
          .whereType<Map<String, dynamic>>()
          .map(SearchBusinessApiModel.fromJson)
          .toList(),
      page: (pagination['page'] as num?)?.toInt() ?? 1,
      total: (pagination['total'] as num?)?.toInt() ?? 0,
      hasMore: pagination['hasMore'] as bool? ?? false,
    );
  }
}

class FavoriteProductListApiResponse {
  final List<FavoriteProductApiModel> products;
  final int page;
  final int total;
  final bool hasMore;

  const FavoriteProductListApiResponse({
    required this.products,
    required this.page,
    required this.total,
    required this.hasMore,
  });

  factory FavoriteProductListApiResponse.fromJson(Map<String, dynamic> json) {
    final products = json['products'] as List<dynamic>? ?? [];
    final pagination = json['pagination'] as Map<String, dynamic>? ?? {};

    return FavoriteProductListApiResponse(
      products: products
          .whereType<Map<String, dynamic>>()
          .map(FavoriteProductApiModel.fromJson)
          .toList(),
      page: (pagination['page'] as num?)?.toInt() ?? 1,
      total: (pagination['total'] as num?)?.toInt() ?? 0,
      hasMore: pagination['hasMore'] as bool? ?? false,
    );
  }
}

class FavoriteProductApiModel {
  final SearchBusinessApiModel business;
  final BusinessProductApiModel product;
  final DateTime? favoritedAt;

  const FavoriteProductApiModel({
    required this.business,
    required this.product,
    required this.favoritedAt,
  });

  factory FavoriteProductApiModel.fromJson(Map<String, dynamic> json) {
    return FavoriteProductApiModel(
      business: SearchBusinessApiModel.fromJson(
        json['business'] as Map<String, dynamic>? ?? {},
      ),
      product: BusinessProductApiModel.fromJson(
        json['product'] as Map<String, dynamic>? ?? {},
      ),
      favoritedAt: DateTime.tryParse(json['favoritedAt'] as String? ?? ''),
    );
  }
}

class FavoriteStatusApiResponse {
  final bool businessFavorited;
  final Set<String> productIds;

  const FavoriteStatusApiResponse({
    required this.businessFavorited,
    required this.productIds,
  });

  factory FavoriteStatusApiResponse.fromJson(Map<String, dynamic> json) {
    final productIds = json['productIds'] as List<dynamic>? ?? [];
    return FavoriteStatusApiResponse(
      businessFavorited: json['businessFavorited'] as bool? ?? false,
      productIds: productIds.whereType<String>().toSet(),
    );
  }
}

class OrderItemRequest {
  final String productId;
  final int quantity;
  final String variant;

  const OrderItemRequest({
    required this.productId,
    required this.quantity,
    this.variant = '',
  });

  Map<String, dynamic> toJson() {
    return {
      'productId': productId,
      'quantity': quantity,
      if (variant.trim().isNotEmpty) 'variant': variant.trim(),
    };
  }
}

class OrderListApiResponse {
  final List<OrderApiModel> orders;
  final int page;
  final int limit;
  final int total;
  final int totalAcrossStatuses;
  final bool hasMore;

  const OrderListApiResponse({
    required this.orders,
    required this.page,
    required this.limit,
    required this.total,
    required this.totalAcrossStatuses,
    required this.hasMore,
  });

  factory OrderListApiResponse.fromJson(Map<String, dynamic> json) {
    final ordersJson = json['orders'] as List<dynamic>? ?? [];
    final pagination = json['pagination'] as Map<String, dynamic>? ?? {};
    final counts = json['counts'] as Map<String, dynamic>? ?? {};

    return OrderListApiResponse(
      orders: ordersJson
          .whereType<Map<String, dynamic>>()
          .map(OrderApiModel.fromJson)
          .toList(),
      page: (pagination['page'] as num?)?.toInt() ?? 1,
      limit: (pagination['limit'] as num?)?.toInt() ?? 20,
      total: (pagination['total'] as num?)?.toInt() ?? 0,
      totalAcrossStatuses: (counts['total'] as num?)?.toInt() ?? 0,
      hasMore: pagination['hasMore'] as bool? ?? false,
    );
  }
}

class OrderApiModel {
  final String id;
  final String publicId;
  final OrderBusinessApiModel business;
  final List<OrderItemApiModel> items;
  final double subtotal;
  final double deliveryFee;
  final double total;
  final String currency;
  final String deliveryAddress;
  final String paymentMethod;
  final String status;
  final String statusGroup;
  final List<OrderStatusHistoryApiModel> statusHistory;
  final String cancellationReason;
  final DateTime? createdAt;

  const OrderApiModel({
    required this.id,
    required this.publicId,
    required this.business,
    required this.items,
    required this.subtotal,
    required this.deliveryFee,
    required this.total,
    required this.currency,
    required this.deliveryAddress,
    required this.paymentMethod,
    required this.status,
    required this.statusGroup,
    required this.statusHistory,
    required this.cancellationReason,
    required this.createdAt,
  });

  factory OrderApiModel.fromJson(Map<String, dynamic> json) {
    final business = json['business'] as Map<String, dynamic>? ?? {};
    final items = json['items'] as List<dynamic>? ?? [];
    final history = json['statusHistory'] as List<dynamic>? ?? [];

    return OrderApiModel(
      id: json['id'] as String? ?? '',
      publicId: json['publicId'] as String? ?? '',
      business: OrderBusinessApiModel.fromJson(business),
      items: items
          .whereType<Map<String, dynamic>>()
          .map(OrderItemApiModel.fromJson)
          .toList(),
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0,
      deliveryFee: (json['deliveryFee'] as num?)?.toDouble() ?? 0,
      total: (json['total'] as num?)?.toDouble() ?? 0,
      currency: json['currency'] as String? ?? 'ILS',
      deliveryAddress: json['deliveryAddress'] as String? ?? '',
      paymentMethod: json['paymentMethod'] as String? ?? 'cash',
      status: json['status'] as String? ?? 'pending',
      statusGroup: json['statusGroup'] as String? ?? 'current',
      statusHistory: history
          .whereType<Map<String, dynamic>>()
          .map(OrderStatusHistoryApiModel.fromJson)
          .toList(),
      cancellationReason: json['cancellationReason'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
    );
  }
}

class OrderBusinessApiModel {
  final String id;
  final String name;
  final String address;

  const OrderBusinessApiModel({
    required this.id,
    required this.name,
    required this.address,
  });

  factory OrderBusinessApiModel.fromJson(Map<String, dynamic> json) {
    return OrderBusinessApiModel(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      address: json['address'] as String? ?? '',
    );
  }
}

class OrderItemApiModel {
  final String productId;
  final String name;
  final String imageUrl;
  final double unitPrice;
  final int quantity;
  final String variant;

  const OrderItemApiModel({
    required this.productId,
    required this.name,
    required this.imageUrl,
    required this.unitPrice,
    required this.quantity,
    required this.variant,
  });

  factory OrderItemApiModel.fromJson(Map<String, dynamic> json) {
    return OrderItemApiModel(
      productId: json['productId'] as String? ?? '',
      name: json['name'] as String? ?? '',
      imageUrl: json['imageUrl'] as String? ?? '',
      unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? 0,
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      variant: json['variant'] as String? ?? '',
    );
  }
}

class OrderStatusHistoryApiModel {
  final String status;
  final DateTime? changedAt;
  final String note;

  const OrderStatusHistoryApiModel({
    required this.status,
    required this.changedAt,
    required this.note,
  });

  factory OrderStatusHistoryApiModel.fromJson(Map<String, dynamic> json) {
    return OrderStatusHistoryApiModel(
      status: json['status'] as String? ?? '',
      changedAt: DateTime.tryParse(json['changedAt'] as String? ?? ''),
      note: json['note'] as String? ?? '',
    );
  }
}

class BusinessReviewApiModel {
  final String id;
  final String userName;
  final double rating;
  final String comment;
  final DateTime? createdAt;

  const BusinessReviewApiModel({
    required this.id,
    required this.userName,
    required this.rating,
    required this.comment,
    required this.createdAt,
  });

  factory BusinessReviewApiModel.fromJson(Map<String, dynamic> json) {
    return BusinessReviewApiModel(
      id: json['id'] as String? ?? '',
      userName: json['userName'] as String? ?? '',
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      comment: json['comment'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
    );
  }
}

class ContactEmail {
  final String value;
  final String label;
  final bool isPrimary;
  final bool verified;

  const ContactEmail({
    required this.value,
    this.label = 'personal',
    this.isPrimary = false,
    this.verified = false,
  });

  factory ContactEmail.fromJson(Map<String, dynamic> json) {
    return ContactEmail(
      value: json['value'] as String? ?? '',
      label: json['label'] as String? ?? 'personal',
      isPrimary: json['isPrimary'] as bool? ?? false,
      verified: json['verified'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {'value': value, 'label': label, 'isPrimary': isPrimary};
  }
}

class ContactPhone {
  final String value;
  final String label;
  final bool isPrimary;

  const ContactPhone({
    required this.value,
    this.label = 'mobile',
    this.isPrimary = false,
  });

  factory ContactPhone.fromJson(Map<String, dynamic> json) {
    return ContactPhone(
      value: json['value'] as String? ?? '',
      label: json['label'] as String? ?? 'mobile',
      isPrimary: json['isPrimary'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {'value': value, 'label': label, 'isPrimary': isPrimary};
  }
}

class SignupApiResponse {
  final bool requiresEmailVerification;
  final bool emailSent;
  final String? verificationLink;

  const SignupApiResponse({
    required this.requiresEmailVerification,
    required this.emailSent,
    this.verificationLink,
  });

  factory SignupApiResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? {};

    return SignupApiResponse(
      requiresEmailVerification:
          data['requiresEmailVerification'] as bool? ?? false,
      emailSent: data['emailSent'] as bool? ?? false,
      verificationLink: data['verificationLink'] as String?,
    );
  }
}

class AuthApiResponse {
  final String token;
  final AuthApiUser user;

  const AuthApiResponse({required this.token, required this.user});

  factory AuthApiResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? {};
    final user = data['user'] as Map<String, dynamic>? ?? {};

    return AuthApiResponse(
      token: data['token'] as String? ?? '',
      user: AuthApiUser.fromJson(user),
    );
  }
}

class AuthApiUser {
  final String id;
  final String name;
  final String? email;
  final List<ContactEmail> emails;
  final String? phone;
  final List<ContactPhone> phones;
  final String address;
  final String userType;
  final String gender;
  final bool canChangeName;
  final bool canChangeGender;
  final UserPermissions permissions;

  const AuthApiUser({
    required this.id,
    required this.name,
    required this.email,
    required this.emails,
    required this.phone,
    required this.phones,
    required this.address,
    required this.userType,
    required this.gender,
    required this.canChangeName,
    required this.canChangeGender,
    required this.permissions,
  });

  factory AuthApiUser.fromJson(Map<String, dynamic> json) {
    final emailsJson = json['emails'] as List<dynamic>? ?? [];
    final phonesJson = json['phones'] as List<dynamic>? ?? [];

    return AuthApiUser(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      email: json['email'] as String?,
      emails: emailsJson
          .whereType<Map<String, dynamic>>()
          .map(ContactEmail.fromJson)
          .where((email) => email.value.isNotEmpty)
          .toList(),
      phone: json['phone'] as String?,
      phones: phonesJson
          .whereType<Map<String, dynamic>>()
          .map(ContactPhone.fromJson)
          .where((phone) => phone.value.isNotEmpty)
          .toList(),
      address: json['address'] as String? ?? '',
      userType: json['userType'] as String? ?? 'normal',
      gender: json['gender'] as String? ?? 'unspecified',
      canChangeName: json['canChangeName'] as bool? ?? true,
      canChangeGender: json['canChangeGender'] as bool? ?? true,
      permissions: UserPermissions.fromJson(
        json['permissions'] as Map<String, dynamic>? ?? {},
      ),
    );
  }
}

class UserPermissions {
  final bool aiPersonalization;
  final bool location;
  final bool contacts;

  const UserPermissions({
    required this.aiPersonalization,
    required this.location,
    required this.contacts,
  });

  factory UserPermissions.fromJson(Map<String, dynamic> json) {
    return UserPermissions(
      aiPersonalization: json['aiPersonalization'] as bool? ?? false,
      location: json['location'] as bool? ?? false,
      contacts: json['contacts'] as bool? ?? false,
    );
  }
}

class AboutUsApiModel {
  final String pageTitle;
  final String appLabel;
  final String appName;
  final String introduction;
  final List<AboutUsSectionApiModel> sections;
  final DateTime? updatedAt;

  const AboutUsApiModel({
    required this.pageTitle,
    required this.appLabel,
    required this.appName,
    required this.introduction,
    required this.sections,
    required this.updatedAt,
  });

  factory AboutUsApiModel.fromJson(Map<String, dynamic> json) {
    final rawSections = json['sections'] as List<dynamic>? ?? [];

    return AboutUsApiModel(
      pageTitle: json['pageTitle'] as String? ?? '',
      appLabel: json['appLabel'] as String? ?? '',
      appName: json['appName'] as String? ?? '',
      introduction: json['introduction'] as String? ?? '',
      sections: rawSections
          .whereType<Map<String, dynamic>>()
          .map(AboutUsSectionApiModel.fromJson)
          .where((section) => section.key.isNotEmpty)
          .toList(growable: false),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
    );
  }
}

class AboutUsSectionApiModel {
  final String key;
  final String title;
  final String content;

  const AboutUsSectionApiModel({
    required this.key,
    required this.title,
    required this.content,
  });

  factory AboutUsSectionApiModel.fromJson(Map<String, dynamic> json) {
    return AboutUsSectionApiModel(
      key: json['key'] as String? ?? '',
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
    );
  }
}
