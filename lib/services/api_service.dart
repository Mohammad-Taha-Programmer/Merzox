import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:merzox/features/business/models/business_models.dart';

final String ipAddress = "192.168.1.8";

/// Raised when a 2xx response does not carry the entity its endpoint promises.
///
/// Without this, `response.data?['data'] ?? {}` turns a malformed or truncated
/// payload into a fully-formed domain object with empty fields, and the UI
/// renders it as a successful load. A required entity that is absent is a
/// contract failure, not an empty result.
class ApiContractException implements Exception {
  final String endpoint;
  final String detail;

  const ApiContractException(this.endpoint, this.detail);

  @override
  String toString() => 'ApiContractException($endpoint): $detail';
}

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
    final user = requiredEntity(response.data, 'user', endpoint: 'auth');

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
    final user = requiredEntity(response.data, 'user', endpoint: 'auth');

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
    final user = requiredEntity(response.data, 'user', endpoint: 'auth');

    return AuthApiUser.fromJson(user);
  }

  Future<BusinessListApiResponse> businesses({
    int page = 1,
    int limit = 100,
    String? search,
    String? sort,
    bool? discounted,
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
        if (sort != null && sort.trim().isNotEmpty) 'sort': sort.trim(),
        if (discounted != null) 'discounted': discounted,
        if (latitude != null) 'lat': latitude,
        if (longitude != null) 'lng': longitude,
        if (radiusMeters != null) 'radiusMeters': radiusMeters,
      },
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? {};

    return BusinessListApiResponse.fromJson(data);
  }

  Future<BusinessDetailApiModel> business({required String businessId}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/businesses/$businessId',
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? {};
    final business = data['business'] as Map<String, dynamic>?;

    if (business == null || business['id'] is! String) {
      throw StateError('Business response did not contain a business');
    }

    return BusinessDetailApiModel.fromJson(business);
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
    final order = requiredEntity(response.data, 'order', endpoint: 'order');

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
    final order = requiredEntity(response.data, 'order', endpoint: 'order');

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
    final product = data['product'] as Map<String, dynamic>?;

    if (product == null || product['id'] is! String) {
      throw StateError('Product response did not contain a product');
    }

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
    final product = requiredEntity(
      response.data,
      'product',
      endpoint: 'product',
    );

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
    final review = requiredEntity(response.data, 'review', endpoint: 'review');

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
    final review = requiredEntity(
      response.data,
      'review',
      endpoint: 'productReview',
    );
    final product = requiredEntity(
      response.data,
      'product',
      endpoint: 'productReview',
    );

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
    return OwnerOrder.fromJson(
      requiredEntity(response.data, 'order', endpoint: 'ownerOrder'),
    );
  }

  Future<List<OwnerProduct>> ownerProducts({required String token}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/businesses/me/products',
      options: _authOptions(token),
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? {};
    final products = data['products'] as List<dynamic>? ?? [];
    return products
        .whereType<Map<String, dynamic>>()
        .map(OwnerProduct.fromJson)
        .toList();
  }

  Future<OwnerProduct> createOwnerProduct({
    required String token,
    required Map<String, dynamic> product,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/businesses/me/products',
      data: product,
      options: _authOptions(token),
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? {};
    return OwnerProduct.fromJson(
      data['product'] as Map<String, dynamic>? ?? {},
    );
  }

  Future<OwnerProduct> updateOwnerProduct({
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
    return OwnerProduct.fromJson(
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

  Future<ConversationListApiResponse> conversations({
    required String token,
    bool unreadOnly = false,
    int page = 1,
    int limit = 20,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/conversations',
      queryParameters: {
        'filter': unreadOnly ? 'unread' : 'all',
        'page': page,
        'limit': limit,
      },
      options: _authOptions(token),
    );

    return ConversationListApiResponse.fromJson(
      response.data?['data'] as Map<String, dynamic>? ?? {},
    );
  }

  Future<ConversationListApiResponse> merchantConversations({
    required String token,
    bool unreadOnly = false,
    int page = 1,
    int limit = 20,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/businesses/me/conversations',
      queryParameters: {
        'filter': unreadOnly ? 'unread' : 'all',
        'page': page,
        'limit': limit,
      },
      options: _authOptions(token),
    );

    return ConversationListApiResponse.fromJson(
      response.data?['data'] as Map<String, dynamic>? ?? {},
    );
  }

  /// Opens the thread with a business, reusing the existing one when the
  /// customer has written to that store before.
  Future<ConversationApiModel> openConversation({
    required String token,
    required String businessId,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/conversations',
      data: {'businessId': businessId},
      options: _authOptions(token),
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? {};

    return ConversationApiModel.fromJson(
      data['conversation'] as Map<String, dynamic>? ?? {},
    );
  }

  Future<ConversationMessagesApiResponse> conversationMessages({
    required String token,
    required String conversationId,
    int page = 1,
    int limit = 30,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/conversations/$conversationId/messages',
      queryParameters: {'page': page, 'limit': limit},
      options: _authOptions(token),
    );

    return ConversationMessagesApiResponse.fromJson(
      response.data?['data'] as Map<String, dynamic>? ?? {},
    );
  }

  Future<MessageApiModel> sendMessage({
    required String token,
    required String conversationId,
    required String body,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/conversations/$conversationId/messages',
      data: {'body': body},
      options: _authOptions(token),
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? {};

    return MessageApiModel.fromJson(
      data['message'] as Map<String, dynamic>? ?? {},
    );
  }

  Future<ConversationApiModel> markConversationRead({
    required String token,
    required String conversationId,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/conversations/$conversationId/read',
      options: _authOptions(token),
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? {};

    return ConversationApiModel.fromJson(
      data['conversation'] as Map<String, dynamic>? ?? {},
    );
  }

  Future<NotificationListApiResponse> notifications({
    required String token,
    bool businessAudience = false,
    bool unreadOnly = false,
    int page = 1,
    int limit = 20,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/notifications',
      queryParameters: {
        'audience': businessAudience ? 'business' : 'customer',
        'filter': unreadOnly ? 'unread' : 'all',
        'page': page,
        'limit': limit,
      },
      options: _authOptions(token),
    );

    return NotificationListApiResponse.fromJson(
      response.data?['data'] as Map<String, dynamic>? ?? {},
    );
  }

  Future<int> notificationUnreadCount({
    required String token,
    bool businessAudience = false,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/notifications/unread-count',
      queryParameters: {'audience': businessAudience ? 'business' : 'customer'},
      options: _authOptions(token),
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? {};

    return (data['unreadCount'] as num?)?.toInt() ?? 0;
  }

  Future<void> markNotificationRead({
    required String token,
    required String notificationId,
  }) async {
    await _dio.post<Map<String, dynamic>>(
      '/notifications/$notificationId/read',
      options: _authOptions(token),
    );
  }

  Future<void> markAllNotificationsRead({
    required String token,
    bool businessAudience = false,
  }) async {
    await _dio.post<Map<String, dynamic>>(
      '/notifications/read-all',
      data: {'audience': businessAudience ? 'business' : 'customer'},
      options: _authOptions(token),
    );
  }

  Future<OrderApiModel> order({
    required String token,
    required String orderId,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/orders/$orderId',
      options: _authOptions(token),
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? {};

    return OrderApiModel.fromJson(data['order'] as Map<String, dynamic>? ?? {});
  }

  Future<OrderApiModel> updateOrderAddress({
    required String token,
    required String orderId,
    required String deliveryAddress,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/orders/$orderId/address',
      data: {'deliveryAddress': deliveryAddress},
      options: _authOptions(token),
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? {};

    return OrderApiModel.fromJson(data['order'] as Map<String, dynamic>? ?? {});
  }

  Future<OwnerOrder> assignOrderCourier({
    required String token,
    required String orderId,
    required String name,
    String phone = '',
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/businesses/me/orders/$orderId/courier',
      data: {'name': name, 'phone': phone},
      options: _authOptions(token),
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? {};

    return OwnerOrder.fromJson(data['order'] as Map<String, dynamic>? ?? {});
  }

  /// Extracts an entity the endpoint is contractually required to return.
  ///
  /// Throws [ApiContractException] rather than substituting an empty map, so a
  /// malformed success can never reach the UI as a ready state. List endpoints
  /// keep using tolerant parsing: an empty list is a legitimate result.
  static Map<String, dynamic> requiredEntity(
    Map<String, dynamic>? body,
    String key, {
    required String endpoint,
    bool requireId = true,
  }) {
    final data = body?['data'];
    if (data is! Map<String, dynamic>) {
      throw ApiContractException(endpoint, 'response has no data object');
    }

    final entity = data[key];
    if (entity is! Map<String, dynamic> || entity.isEmpty) {
      throw ApiContractException(endpoint, 'response has no "\$key" object');
    }

    if (requireId && (entity['id'] as String? ?? '').trim().isEmpty) {
      throw ApiContractException(endpoint, '"\$key" has no id');
    }

    return entity;
  }

  static String messageFromError(Object error) {
    if (error is ApiContractException) {
      return 'تعذر قراءة رد الخادم. حاول مرة أخرى.';
    }

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
      classification: json['classification'] as String? ?? '',
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
  final String englishName;
  final String category;
  final List<String> products;
  final int productCount;
  final double rating;
  final int ratingCount;
  final int followerCount;
  final int viewCount;
  final String? discount;
  final int colorValue;
  final String address;
  final int? distanceMeters;
  final double? latitude;
  final double? longitude;
  final DateTime? subscribedAt;

  const SearchBusinessApiModel({
    required this.id,
    required this.publicId,
    required this.name,
    required this.englishName,
    required this.category,
    required this.products,
    required this.productCount,
    required this.rating,
    required this.ratingCount,
    required this.followerCount,
    required this.viewCount,
    required this.discount,
    required this.colorValue,
    required this.address,
    this.distanceMeters,
    this.latitude,
    this.longitude,
    this.subscribedAt,
  });

  factory SearchBusinessApiModel.fromJson(Map<String, dynamic> json) {
    final productsJson = json['products'] as List<dynamic>? ?? [];
    final location = json['location'] as Map<String, dynamic>?;
    final coordinates = location?['coordinates'] as List<dynamic>? ?? [];

    return SearchBusinessApiModel(
      id: json['id'] as String? ?? '',
      publicId: json['publicId'] as String? ?? '',
      name: json['name'] as String? ?? '',
      englishName: json['englishName'] as String? ?? '',
      category: json['category'] as String? ?? '',
      products: productsJson.whereType<String>().toList(),
      productCount: (json['productCount'] as num?)?.toInt() ?? 0,
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      ratingCount: (json['ratingCount'] as num?)?.toInt() ?? 0,
      followerCount: (json['followerCount'] as num?)?.toInt() ?? 0,
      viewCount: (json['viewCount'] as num?)?.toInt() ?? 0,
      discount: switch ((json['discount'] as String?)?.trim()) {
        final value? when value.isNotEmpty => value,
        _ => null,
      },
      colorValue: (json['colorValue'] as num?)?.toInt() ?? 0xffdeeef8,
      address: json['address'] as String? ?? '',
      distanceMeters: (json['distanceMeters'] as num?)?.toInt(),
      longitude: coordinates.isNotEmpty
          ? (coordinates[0] as num?)?.toDouble()
          : null,
      latitude: coordinates.length > 1
          ? (coordinates[1] as num?)?.toDouble()
          : null,
      subscribedAt: DateTime.tryParse(json['subscribedAt'] as String? ?? ''),
    );
  }
}

class BusinessDetailApiModel {
  final String id;
  final String publicId;
  final String name;
  final String englishName;
  final String category;
  final String description;
  final String address;
  final List<BusinessProductApiModel> products;
  final int productCount;
  final double rating;
  final int ratingCount;
  final int followerCount;
  final int viewCount;
  final String? discount;
  final int colorValue;
  final double? latitude;
  final double? longitude;
  final DateTime? subscribedAt;

  const BusinessDetailApiModel({
    required this.id,
    required this.publicId,
    required this.name,
    required this.englishName,
    required this.category,
    required this.description,
    required this.address,
    required this.products,
    required this.productCount,
    required this.rating,
    required this.ratingCount,
    required this.followerCount,
    required this.viewCount,
    required this.discount,
    required this.colorValue,
    this.latitude,
    this.longitude,
    this.subscribedAt,
  });

  factory BusinessDetailApiModel.fromJson(Map<String, dynamic> json) {
    final productsJson = json['products'] as List<dynamic>? ?? [];
    final location = json['location'] as Map<String, dynamic>?;
    final coordinates = location?['coordinates'] as List<dynamic>? ?? [];
    final products = productsJson
        .whereType<Map<String, dynamic>>()
        .map(BusinessProductApiModel.fromJson)
        .toList();

    return BusinessDetailApiModel(
      id: json['id'] as String? ?? '',
      publicId: json['publicId'] as String? ?? '',
      name: json['name'] as String? ?? '',
      englishName: json['englishName'] as String? ?? '',
      category: json['category'] as String? ?? '',
      description: json['description'] as String? ?? '',
      address: json['address'] as String? ?? '',
      products: products,
      productCount: (json['productCount'] as num?)?.toInt() ?? products.length,
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      ratingCount: (json['ratingCount'] as num?)?.toInt() ?? 0,
      followerCount: (json['followerCount'] as num?)?.toInt() ?? 0,
      viewCount: (json['viewCount'] as num?)?.toInt() ?? 0,
      discount: switch ((json['discount'] as String?)?.trim()) {
        final value? when value.isNotEmpty => value,
        _ => null,
      },
      colorValue: (json['colorValue'] as num?)?.toInt() ?? 0xffdeeef8,
      longitude: coordinates.isNotEmpty
          ? (coordinates[0] as num?)?.toDouble()
          : null,
      latitude: coordinates.length > 1
          ? (coordinates[1] as num?)?.toDouble()
          : null,
      subscribedAt: DateTime.tryParse(json['subscribedAt'] as String? ?? ''),
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

  const OrderItemRequest({required this.productId, required this.quantity});

  /// No variant is sent: the catalog models none, and the API refuses an order
  /// item that carries anything beyond a product and a quantity.
  Map<String, dynamic> toJson() {
    return {'productId': productId, 'quantity': quantity};
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
  final OrderCourierApiModel courier;
  final OrderTrackingApiModel tracking;

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
    required this.courier,
    required this.tracking,
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
      courier: OrderCourierApiModel.fromJson(
        json['courier'] as Map<String, dynamic>? ?? const {},
      ),
      // Customer action permissions are a backend decision. A missing or
      // malformed tracking object is a contract failure, never an invitation
      // to infer canCancel/canChangeAddress/canReview from the status.
      tracking: OrderTrackingApiModel.fromJson(json['tracking']),
    );
  }
}

class OrderCourierApiModel {
  final String name;
  final String phone;
  final DateTime? assignedAt;

  const OrderCourierApiModel({
    required this.name,
    required this.phone,
    required this.assignedAt,
  });

  bool get isAssigned => name.isNotEmpty;

  factory OrderCourierApiModel.fromJson(Map<String, dynamic> json) {
    return OrderCourierApiModel(
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      assignedAt: DateTime.tryParse(json['assignedAt'] as String? ?? ''),
    );
  }
}

/// The four steps the tracking screen draws. The server collapses its six
/// stored statuses onto these, so the client never has to map them itself.
class OrderTrackingStepApiModel {
  final String step;
  final DateTime? reachedAt;
  final bool isReached;

  const OrderTrackingStepApiModel({
    required this.step,
    required this.reachedAt,
    required this.isReached,
  });

  factory OrderTrackingStepApiModel.fromJson(Map<String, dynamic> json) {
    return OrderTrackingStepApiModel(
      step: json['step'] as String? ?? '',
      reachedAt: DateTime.tryParse(json['reachedAt'] as String? ?? ''),
      isReached: json['isReached'] as bool? ?? false,
    );
  }
}

class OrderTrackingApiModel {
  static const List<String> stepOrder = [
    'placed',
    'preparing',
    'outForDelivery',
    'delivered',
  ];

  final bool isCancelled;
  final String currentStep;
  final int currentIndex;
  final List<OrderTrackingStepApiModel> steps;
  final OrderCourierApiModel courier;
  final bool canCancel;
  final bool canChangeAddress;
  final bool canReview;

  const OrderTrackingApiModel({
    required this.isCancelled,
    required this.currentStep,
    required this.currentIndex,
    required this.steps,
    required this.courier,
    required this.canCancel,
    required this.canChangeAddress,
    required this.canReview,
  });

  /// Parses the server's tracking payload.
  ///
  /// There is deliberately no status-derived fallback: reconstructing the
  /// permission flags on the client would let a stale or truncated response
  /// widen what the customer is allowed to do.
  /// Reads one field of the required shape, or fails the contract.
  ///
  /// Defaulting a missing field would resurrect the problem R2 removed: a
  /// permission flag that the server never sent would be synthesized here, and
  /// a structurally wrong payload like `{'foo': 1}` would parse into a
  /// ready-looking object with every field defaulted.
  static T _field<T>(Map<String, dynamic> json, String key) {
    final value = json[key];

    // `int` arrives as `num` from JSON when the value is whole.
    if (T == int) {
      if (value is int) return value as T;
      if (value is num && value == value.roundToDouble()) {
        return value.toInt() as T;
      }
      throw ApiContractException('order', 'tracking.$key is not an integer');
    }

    if (value is T) return value;

    throw ApiContractException('order', 'tracking.$key has the wrong type');
  }

  factory OrderTrackingApiModel.fromJson(Object? raw) {
    if (raw is! Map<String, dynamic> || raw.isEmpty) {
      throw const ApiContractException(
        'order',
        'order response carried no tracking object',
      );
    }

    final json = raw;

    return OrderTrackingApiModel(
      isCancelled: _field<bool>(json, 'isCancelled'),
      currentStep: _field<String>(json, 'currentStep'),
      currentIndex: _field<int>(json, 'currentIndex'),
      steps: _field<List<dynamic>>(json, 'steps')
          .whereType<Map<String, dynamic>>()
          .map(OrderTrackingStepApiModel.fromJson)
          .toList(),
      courier: OrderCourierApiModel.fromJson(
        _field<Map<String, dynamic>>(json, 'courier'),
      ),
      // Permission flags are never defaulted: an absent flag is a malformed
      // response, not a closed permission.
      canCancel: _field<bool>(json, 'canCancel'),
      canChangeAddress: _field<bool>(json, 'canChangeAddress'),
      canReview: _field<bool>(json, 'canReview'),
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
    // Checked rather than cast: a malformed envelope must surface as a
    // contract failure, not an uncaught CastError.
    final envelope = json['data'];
    final data = envelope is Map<String, dynamic>
        ? envelope
        : const <String, dynamic>{};

    // A 200 with no usable token must fail here rather than be stored as an
    // empty one. AuthSessionService would reject it later, but failing at the
    // parse keeps the reason visible instead of surfacing as a silent logout.
    final token = (data['token'] as String? ?? '').trim();
    if (token.isEmpty) {
      throw const ApiContractException(
        'auth',
        'login response carried no token',
      );
    }

    // An authenticated response must also carry the identity it authenticates.
    // Without this, a missing or malformed `data.user` became
    // `AuthApiUser.fromJson({})` - an id-less user that then travelled through
    // session persistence and every downstream screen as though it were real.
    final user = ApiService.requiredEntity(json, 'user', endpoint: 'auth');

    return AuthApiResponse(token: token, user: AuthApiUser.fromJson(user));
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

class ConversationPartyApiModel {
  final String id;
  final String name;
  final String logoUrl;

  const ConversationPartyApiModel({
    required this.id,
    required this.name,
    required this.logoUrl,
  });

  factory ConversationPartyApiModel.fromJson(Map<String, dynamic> json) {
    return ConversationPartyApiModel(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      logoUrl: json['logoUrl'] as String? ?? '',
    );
  }
}

class ConversationLastMessageApiModel {
  final String body;
  final String senderType;
  final DateTime? sentAt;

  const ConversationLastMessageApiModel({
    required this.body,
    required this.senderType,
    required this.sentAt,
  });

  factory ConversationLastMessageApiModel.fromJson(Map<String, dynamic> json) {
    return ConversationLastMessageApiModel(
      body: json['body'] as String? ?? '',
      senderType: json['senderType'] as String? ?? 'customer',
      sentAt: DateTime.tryParse(json['sentAt'] as String? ?? ''),
    );
  }
}

/// One thread. The server already picks the counterpart for the caller's side,
/// so [title] is the store name for a customer and the customer name for a
/// merchant without the client having to decide.
class ConversationApiModel {
  final String id;
  final String title;
  final String avatarUrl;
  final ConversationPartyApiModel? business;
  final ConversationPartyApiModel? customer;
  final ConversationLastMessageApiModel lastMessage;
  final int unreadCount;
  final int messageCount;
  final DateTime? updatedAt;

  const ConversationApiModel({
    required this.id,
    required this.title,
    required this.avatarUrl,
    required this.business,
    required this.customer,
    required this.lastMessage,
    required this.unreadCount,
    required this.messageCount,
    required this.updatedAt,
  });

  bool get hasUnread => unreadCount > 0;

  factory ConversationApiModel.fromJson(Map<String, dynamic> json) {
    final business = json['business'] as Map<String, dynamic>?;
    final customer = json['customer'] as Map<String, dynamic>?;

    return ConversationApiModel(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String? ?? '',
      business: business == null
          ? null
          : ConversationPartyApiModel.fromJson(business),
      customer: customer == null
          ? null
          : ConversationPartyApiModel.fromJson(customer),
      lastMessage: ConversationLastMessageApiModel.fromJson(
        json['lastMessage'] as Map<String, dynamic>? ?? const {},
      ),
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
      messageCount: (json['messageCount'] as num?)?.toInt() ?? 0,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
    );
  }
}

class ConversationListApiResponse {
  final List<ConversationApiModel> conversations;
  final int unreadConversationCount;
  final int page;
  final bool hasMore;

  const ConversationListApiResponse({
    required this.conversations,
    required this.unreadConversationCount,
    required this.page,
    required this.hasMore,
  });

  factory ConversationListApiResponse.fromJson(Map<String, dynamic> json) {
    final conversations = json['conversations'] as List<dynamic>? ?? const [];
    final pagination = json['pagination'] as Map<String, dynamic>? ?? const {};

    return ConversationListApiResponse(
      conversations: conversations
          .whereType<Map<String, dynamic>>()
          .map(ConversationApiModel.fromJson)
          .toList(),
      unreadConversationCount:
          (json['unreadConversationCount'] as num?)?.toInt() ?? 0,
      page: (pagination['page'] as num?)?.toInt() ?? 1,
      hasMore: pagination['hasMore'] as bool? ?? false,
    );
  }
}

class MessageApiModel {
  final String id;
  final String conversationId;
  final String senderType;
  final String senderName;
  final String body;
  final bool isMine;
  final DateTime? readAt;
  final DateTime? createdAt;

  const MessageApiModel({
    required this.id,
    required this.conversationId,
    required this.senderType,
    required this.senderName,
    required this.body,
    required this.isMine,
    required this.readAt,
    required this.createdAt,
  });

  factory MessageApiModel.fromJson(Map<String, dynamic> json) {
    return MessageApiModel(
      id: json['id'] as String? ?? '',
      conversationId: json['conversationId'] as String? ?? '',
      senderType: json['senderType'] as String? ?? 'customer',
      senderName: json['senderName'] as String? ?? '',
      body: json['body'] as String? ?? '',
      isMine: json['isMine'] as bool? ?? false,
      readAt: DateTime.tryParse(json['readAt'] as String? ?? ''),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
    );
  }
}

class ConversationMessagesApiResponse {
  final ConversationApiModel conversation;

  /// Oldest first, ready to render. The API pages newest first so that walking
  /// back through history stays a plain offset query.
  final List<MessageApiModel> messages;
  final int page;
  final bool hasMore;

  const ConversationMessagesApiResponse({
    required this.conversation,
    required this.messages,
    required this.page,
    required this.hasMore,
  });

  factory ConversationMessagesApiResponse.fromJson(Map<String, dynamic> json) {
    final messages = json['messages'] as List<dynamic>? ?? const [];
    final pagination = json['pagination'] as Map<String, dynamic>? ?? const {};

    return ConversationMessagesApiResponse(
      conversation: ConversationApiModel.fromJson(
        json['conversation'] as Map<String, dynamic>? ?? const {},
      ),
      messages: messages
          .whereType<Map<String, dynamic>>()
          .map(MessageApiModel.fromJson)
          .toList()
          .reversed
          .toList(),
      page: (pagination['page'] as num?)?.toInt() ?? 1,
      hasMore: pagination['hasMore'] as bool? ?? false,
    );
  }
}

class AppNotificationApiModel {
  final String id;
  final String type;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final bool isRead;
  final DateTime? createdAt;

  const AppNotificationApiModel({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.data,
    required this.isRead,
    required this.createdAt,
  });

  String get orderId => data['orderId'] as String? ?? '';

  String get conversationId => data['conversationId'] as String? ?? '';

  factory AppNotificationApiModel.fromJson(Map<String, dynamic> json) {
    return AppNotificationApiModel(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? '',
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      data: json['data'] as Map<String, dynamic>? ?? const {},
      isRead: json['isRead'] as bool? ?? false,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
    );
  }

  AppNotificationApiModel copyWith({bool? isRead}) {
    return AppNotificationApiModel(
      id: id,
      type: type,
      title: title,
      body: body,
      data: data,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
    );
  }
}

class NotificationListApiResponse {
  final List<AppNotificationApiModel> notifications;
  final int unreadCount;
  final int page;
  final bool hasMore;

  const NotificationListApiResponse({
    required this.notifications,
    required this.unreadCount,
    required this.page,
    required this.hasMore,
  });

  factory NotificationListApiResponse.fromJson(Map<String, dynamic> json) {
    final notifications = json['notifications'] as List<dynamic>? ?? const [];
    final pagination = json['pagination'] as Map<String, dynamic>? ?? const {};

    return NotificationListApiResponse(
      notifications: notifications
          .whereType<Map<String, dynamic>>()
          .map(AppNotificationApiModel.fromJson)
          .toList(),
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
      page: (pagination['page'] as num?)?.toInt() ?? 1,
      hasMore: pagination['hasMore'] as bool? ?? false,
    );
  }
}
