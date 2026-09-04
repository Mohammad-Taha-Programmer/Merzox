import 'package:dio/dio.dart';
import 'package:merzox/core/localization/api_error_codes.dart';
import 'package:merzox/features/business/models/business_models.dart';

final String ipAddress = "192.168.1.11";

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

final class CourierLocationCapabilityRejected implements Exception {
  const CourierLocationCapabilityRejected();

  @override
  String toString() => 'CourierLocationCapabilityRejected';
}

final class CourierLocationCapabilityApiModel {
  final String token;
  final DateTime expiresAt;

  const CourierLocationCapabilityApiModel({
    required this.token,
    required this.expiresAt,
  });

  factory CourierLocationCapabilityApiModel.fromJson(
    Map<String, dynamic> json,
  ) {
    final token = json['token'];
    final expiresAtValue = json['expiresAt'];

    if (token is! String || !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(token)) {
      throw const ApiContractException(
        'courierLocationCapability',
        'response did not contain a valid capability token',
      );
    }

    if (expiresAtValue is! String) {
      throw const ApiContractException(
        'courierLocationCapability',
        'response did not contain capability expiry',
      );
    }

    final expiresAt = DateTime.tryParse(expiresAtValue);

    if (expiresAt == null) {
      throw const ApiContractException(
        'courierLocationCapability',
        'capability expiry was not a valid timestamp',
      );
    }

    return CourierLocationCapabilityApiModel(
      token: token,
      expiresAt: expiresAt,
    );
  }
}

final class CourierAssignmentApiResult {
  final OwnerOrder order;
  final CourierLocationCapabilityApiModel capability;

  const CourierAssignmentApiResult({
    required this.order,
    required this.capability,
  });
}

class ApiService {
  static const String configuredBaseUrl = String.fromEnvironment(
    'MERZOX_API_BASE_URL',
    defaultValue: '',
  );

  /// The development host. A shipped build passes `MERZOX_API_BASE_URL` at
  /// compile time; without it the app talks to the LAN address a developer
  /// runs the API on.
  ///
  /// There used to be an Android arm here returning the same string as the
  /// fallback below it, which read as a platform difference that did not
  /// exist.
  static String get defaultBaseUrl {
    if (configuredBaseUrl.isNotEmpty) {
      return configuredBaseUrl;
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

  /// [birthDate] is the canonical date-only `YYYY-MM-DD`. Passing null omits
  /// the field entirely, which leaves the stored date of birth untouched.
  Future<AuthApiUser> updateProfile({
    required String token,
    String? name,
    String? gender,
    String? address,
    String? birthDate,
    List<ContactEmail>? emails,
    List<ContactPhone>? phones,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/users/me',
      data: {
        if (name != null) 'name': name,
        if (gender != null) 'gender': gender,
        if (address != null) 'address': address,
        if (birthDate != null) 'birthDate': birthDate,
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

  Future<RecommendationApiResponse> recommendations({
    required String token,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/users/me/recommendations',
      options: _authOptions(token),
    );

    final rawData = response.data?['data'];

    if (rawData is! Map<String, dynamic>) {
      throw const ApiContractException(
        'recommendations',
        'response carried no recommendation data object',
      );
    }

    return RecommendationApiResponse.fromJson(rawData);
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

  /// Where the company delivers, and which governorates are closed.
  ///
  /// Public: the checkout form needs the list before anyone signs in to fill
  /// it, and where a company delivers is not private.
  Future<List<DeliveryRegionApiModel>> deliveryRegions() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/users/delivery-regions',
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? const {};
    final List<dynamic> regions = data['regions'] as List<dynamic>? ?? const [];

    return regions
        .whereType<Map<String, dynamic>>()
        .map(DeliveryRegionApiModel.fromJson)
        .toList();
  }

  /// The caller's own saved addresses. Every write below answers with the whole
  /// book, so a client never has to reconcile a partial update against it.
  Future<List<SavedAddressApiModel>> myAddresses({
    required String token,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/users/me/addresses',
      options: _authOptions(token),
    );

    return _addressesFrom(response.data);
  }

  Future<List<SavedAddressApiModel>> createAddress({
    required String token,
    required Map<String, dynamic> address,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/users/me/addresses',
      data: address,
      options: _authOptions(token),
    );

    return _addressesFrom(response.data);
  }

  Future<List<SavedAddressApiModel>> updateAddress({
    required String token,
    required String addressId,
    required Map<String, dynamic> address,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/users/me/addresses/$addressId',
      data: address,
      options: _authOptions(token),
    );

    return _addressesFrom(response.data);
  }

  Future<List<SavedAddressApiModel>> setDefaultAddress({
    required String token,
    required String addressId,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/users/me/addresses/$addressId/default',
      options: _authOptions(token),
    );

    return _addressesFrom(response.data);
  }

  Future<List<SavedAddressApiModel>> deleteAddress({
    required String token,
    required String addressId,
  }) async {
    final response = await _dio.delete<Map<String, dynamic>>(
      '/users/me/addresses/$addressId',
      options: _authOptions(token),
    );

    return _addressesFrom(response.data);
  }

  static List<SavedAddressApiModel> _addressesFrom(Map<String, dynamic>? body) {
    final data = body?['data'] as Map<String, dynamic>? ?? const {};
    final List<dynamic> raw = data['addresses'] as List<dynamic>? ?? const [];

    return raw
        .whereType<Map<String, dynamic>>()
        .map(SavedAddressApiModel.fromJson)
        .toList();
  }

  /// The delivery tiers and their prices, as the server charges them.
  ///
  /// Public, and deliberately not cached here: the checkout screen has to draw
  /// two prices and must draw the server's, not a copy that can drift.
  Future<DeliveryOptionsApiResponse> deliveryOptions() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/orders/delivery-options',
    );

    return DeliveryOptionsApiResponse.fromJson(
      response.data?['data'] as Map<String, dynamic>? ?? const {},
    );
  }

  Future<OrderApiModel> createOrder({
    required String token,
    required String businessId,
    required List<OrderItemRequest> items,
    required String deliveryAddress,
    String paymentMethod = 'cash',
    // A tier name, never a price: the fee is the server's to decide.
    String deliveryOption = 'standard',
    String? clientOrderId,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/orders',
      data: {
        'businessId': businessId,
        'items': items.map((item) => item.toJson()).toList(),
        'deliveryAddress': deliveryAddress,
        'paymentMethod': paymentMethod,
        'deliveryOption': deliveryOption,
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

  /// Lists the merchant's own orders.
  ///
  /// [statusGroup] and [filter]'s status are mutually exclusive: the server
  /// reads `statusGroup` first, so a caller that sent both would find the
  /// status quietly dropped. Passing neither lists every order, which is the
  /// state the merchant browse artboard draws.
  Future<OwnerOrderList> ownerOrders({
    required String token,
    String statusGroup = '',
    MerchantOrderFilter filter = const MerchantOrderFilter(),
    int page = 1,
    int limit = 30,
  }) async {
    assert(
      statusGroup.isEmpty || filter.status == null,
      'ownerOrders takes a status group or a status, never both.',
    );

    final response = await _dio.get<Map<String, dynamic>>(
      '/businesses/me/orders',
      queryParameters: <String, dynamic>{
        if (statusGroup.isNotEmpty) 'statusGroup': statusGroup,
        ...filter.toQueryParameters(),
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

  /// Re-sends the order's current status to the customer.
  ///
  /// Deliberately carries no body: what the customer is told is whatever the
  /// server already believes the order's status to be, so a merchant cannot
  /// announce a state the order is not in.
  Future<OwnerOrder> notifyOrderCustomer({
    required String token,
    required String orderId,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/businesses/me/orders/$orderId/notify',
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

  Future<CourierAssignmentApiResult> assignOrderCourier({
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

    final order = requiredEntity(
      response.data,
      'order',
      endpoint: 'ownerOrderCourier',
    );

    final capability = requiredEntity(
      response.data,
      'courierLocationCapability',
      endpoint: 'ownerOrderCourier',
    );

    return CourierAssignmentApiResult(
      order: OwnerOrder.fromJson(order),
      capability: CourierLocationCapabilityApiModel.fromJson(capability),
    );
  }

  /// Revokes the courier's location credential for one order.
  ///
  /// The merchant mints this credential when assigning a courier, and the
  /// handoff dialog shows it exactly once. Choosing to discard it there used to
  /// close the dialog and nothing else, which left a minted credential live
  /// until the order moved on. The server's kill switch is idempotent, so a
  /// second call on an already-revoked order is still a success.
  Future<OwnerOrder> revokeOrderCourierLocation({
    required String token,
    required String orderId,
  }) async {
    final response = await _dio.delete<Map<String, dynamic>>(
      '/businesses/me/orders/$orderId/courier-location-capability',
      options: _authOptions(token),
    );

    return OwnerOrder.fromJson(
      requiredEntity(
        response.data,
        'order',
        endpoint: 'revokeOwnerOrderCourierLocation',
      ),
    );
  }

  Future<DateTime> updateCourierLocationByCapability({
    required String orderId,
    required String capabilityToken,
    required double latitude,
    required double longitude,
    required double accuracy,
    required DateTime capturedAt,
  }) async {
    try {
      final response = await _dio.patch<Map<String, dynamic>>(
        '/orders/$orderId/courier-location',
        data: {
          'latitude': latitude,
          'longitude': longitude,
          'accuracy': accuracy,
          'capturedAt': capturedAt.toUtc().toIso8601String(),
        },
        options: Options(
          headers: {'Authorization': 'Courier $capabilityToken'},
        ),
      );

      final data = response.data?['data'] as Map<String, dynamic>?;

      if (data == null || data['accepted'] != true) {
        throw const ApiContractException(
          'courierLocation',
          'response did not acknowledge the location update',
        );
      }

      final receivedAtValue = data['receivedAt'];

      if (receivedAtValue is! String) {
        throw const ApiContractException(
          'courierLocation',
          'response did not contain receivedAt',
        );
      }

      final receivedAt = DateTime.tryParse(receivedAtValue);

      if (receivedAt == null) {
        throw const ApiContractException(
          'courierLocation',
          'receivedAt was not a valid timestamp',
        );
      }

      return receivedAt;
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        throw const CourierLocationCapabilityRejected();
      }

      rethrow;
    }
  }

  Future<void> registerPushTarget({
    required String token,
    required String target,
    required String platform,
  }) async {
    await _dio.put<Map<String, dynamic>>(
      '/push/registrations',
      data: {'targetKind': 'token', 'target': target, 'platform': platform},
      options: _authOptions(token),
    );
  }

  Future<void> unregisterPushTarget({
    required String token,
    required String target,
  }) async {
    await _dio.delete<Map<String, dynamic>>(
      '/push/registrations',
      data: {'targetKind': 'token', 'target': target},
      options: _authOptions(token),
    );
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

  /// Operational server codes whose English message would otherwise reach an
  /// Arabic screen verbatim. The code, not the prose, is the stable contract.
  static const Map<String, String> localizedApiErrorCodes = apiErrorMessageKeys;

  static String messageFromError(Object error) {
    if (error is ApiContractException) {
      return 'apiErrors.contract';
    }

    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map<String, dynamic>) {
        final errorBody = data['error'];
        if (errorBody is Map<String, dynamic>) {
          final localized = localizedApiErrorCodes[errorBody['code']];
          if (localized != null) {
            return localized;
          }

          if (errorBody['message'] is String) {
            return errorBody['message'] as String;
          }
        }
      }

      if (error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout) {
        return 'apiErrors.connection';
      }
    }

    return 'apiErrors.unexpected';
  }

  Options _authOptions(String token) {
    return Options(headers: {'Authorization': 'Bearer $token'});
  }
}

/// One PUBLIC sellable variant from `Business.productToJSON`.
///
/// The type deliberately has no `costPrice`, `stockQuantity` or
/// `unlimitedStock`. A customer receives identity, display label, effective
/// server price and availability only.
class BusinessProductVariantApiModel {
  final String id;
  final String label;
  final double price;
  final double finalPrice;
  final bool inStock;

  const BusinessProductVariantApiModel({
    required this.id,
    required this.label,
    required this.price,
    required this.finalPrice,
    required this.inStock,
  });

  bool get hasDiscount => finalPrice < price;

  factory BusinessProductVariantApiModel.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final rawLabel = json['label'];

    if (rawId is! String || !_objectIdPattern.hasMatch(rawId.trim())) {
      throw const ApiContractException(
        'product.variant',
        'id must be a MongoDB object id',
      );
    }

    if (rawLabel is! String || rawLabel.trim().isEmpty) {
      throw const ApiContractException(
        'product.variant',
        'label must be a non-empty string',
      );
    }

    return BusinessProductVariantApiModel(
      id: rawId.trim(),
      label: rawLabel.trim(),
      price: _requiredMoney(json, 'price'),
      finalPrice: _requiredMoney(json, 'finalPrice'),
      inStock: _requiredFlag(json, 'inStock'),
    );
  }

  static final RegExp _objectIdPattern = RegExp(r'^[a-fA-F0-9]{24}$');

  static double _requiredMoney(Map<String, dynamic> json, String field) {
    final value = json[field];

    if (value is! num || !value.isFinite || value < 0) {
      throw ApiContractException(
        'product.variant',
        '$field must be a non-negative finite number',
      );
    }

    return value.toDouble();
  }

  static bool _requiredFlag(Map<String, dynamic> json, String field) {
    final value = json[field];

    if (value is! bool) {
      throw ApiContractException('product.variant', '$field must be a boolean');
    }

    return value;
  }
}

/// The PUBLIC product contract, mirroring `Business.productToJSON` exactly.
///
/// Merchant-private cost and exact inventory do not exist on this type.
/// Variant products expose only active variant identities plus server-derived
/// effective prices, availability and product-level price ranges.
class BusinessProductApiModel {
  final String id;
  final String name;
  final String description;

  /// Parent/list price. For a simple product this is the sole list price.
  /// For a variant product it remains product metadata; sellable price comes
  /// from the selected server variant.
  final double price;

  final double discountPercent;
  final double finalPrice;
  final bool inStock;

  /// `true` means the server says this product is variant-mode.
  ///
  /// A customer must select one of [variants]; the client may not fall back to
  /// parent inventory when this is true.
  final bool hasVariants;

  /// Active PUBLIC variants only. Exact stock and merchant cost never appear.
  final List<BusinessProductVariantApiModel> variants;

  /// Server-derived public ranges.
  ///
  /// They are null only for a variant product with no active sellable variant.
  final double? minPrice;
  final double? maxPrice;
  final double? minFinalPrice;
  final double? maxFinalPrice;

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
    this.discountPercent = 0,
    double? finalPrice,
    this.inStock = true,
    this.hasVariants = false,
    this.variants = const [],
    this.minPrice,
    this.maxPrice,
    this.minFinalPrice,
    this.maxFinalPrice,
    this.isService = false,
  }) : finalPrice = finalPrice ?? price;

  bool get hasDiscount => discountPercent > 0 && finalPrice < price;

  /// Existing simple products retain their old display semantics.
  ///
  /// A variant product exposes its lowest payable price only as a preview.
  /// Cart/checkout must use the exact selected variant instead.
  double get displayPrice =>
      hasVariants ? (minFinalPrice ?? finalPrice) : finalPrice;

  bool get hasPriceRange =>
      hasVariants &&
      minFinalPrice != null &&
      maxFinalPrice != null &&
      minFinalPrice != maxFinalPrice;

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

    final price = _requiredMoney(json, 'price');
    final finalPrice = _requiredMoney(json, 'finalPrice');
    final inStock = _requiredFlag(json, 'inStock');
    final hasVariants = _requiredFlag(json, 'hasVariants');

    final rawVariants = json['variants'];

    if (rawVariants is! List) {
      throw const ApiContractException('product', 'variants must be a list');
    }

    final variants = <BusinessProductVariantApiModel>[];

    for (final rawVariant in rawVariants) {
      if (rawVariant is! Map) {
        throw const ApiContractException(
          'product',
          'each variant must be an object',
        );
      }

      variants.add(
        BusinessProductVariantApiModel.fromJson(
          Map<String, dynamic>.from(rawVariant),
        ),
      );
    }

    final minPrice = _requiredNullableMoney(json, 'minPrice');
    final maxPrice = _requiredNullableMoney(json, 'maxPrice');
    final minFinalPrice = _requiredNullableMoney(json, 'minFinalPrice');
    final maxFinalPrice = _requiredNullableMoney(json, 'maxFinalPrice');

    _validateVariantSummary(
      hasVariants: hasVariants,
      variants: variants,
      price: price,
      finalPrice: finalPrice,
      inStock: inStock,
      minPrice: minPrice,
      maxPrice: maxPrice,
      minFinalPrice: minFinalPrice,
      maxFinalPrice: maxFinalPrice,
    );

    return BusinessProductApiModel(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      price: price,
      discountPercent: _requiredPercent(json, 'discountPercent'),
      finalPrice: finalPrice,
      inStock: inStock,
      hasVariants: hasVariants,
      variants: List.unmodifiable(variants),
      minPrice: minPrice,
      maxPrice: maxPrice,
      minFinalPrice: minFinalPrice,
      maxFinalPrice: maxFinalPrice,
      imageUrl: imageUrls.isEmpty ? '' : imageUrls.first,
      imageUrls: imageUrls,
      classification: json['classification'] as String? ?? '',
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      ratingCount: (json['ratingCount'] as num?)?.toInt() ?? 0,
      likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
      isService: json['isService'] as bool? ?? false,
    );
  }

  static double _requiredMoney(Map<String, dynamic> json, String field) {
    final value = json[field];

    if (value is! num || !value.isFinite || value < 0) {
      throw ApiContractException(
        'product',
        '$field must be a non-negative finite number',
      );
    }

    return value.toDouble();
  }

  static double? _requiredNullableMoney(
    Map<String, dynamic> json,
    String field,
  ) {
    if (!json.containsKey(field)) {
      throw ApiContractException('product', '$field must be present');
    }

    final value = json[field];

    if (value == null) return null;

    if (value is! num || !value.isFinite || value < 0) {
      throw ApiContractException(
        'product',
        '$field must be null or a non-negative finite number',
      );
    }

    return value.toDouble();
  }

  static double _requiredPercent(Map<String, dynamic> json, String field) {
    final value = json[field];

    if (value is! num || !value.isFinite || value < 0 || value > 100) {
      throw ApiContractException('product', '$field must be between 0 and 100');
    }

    return value.toDouble();
  }

  static bool _requiredFlag(Map<String, dynamic> json, String field) {
    final value = json[field];

    if (value is! bool) {
      throw ApiContractException('product', '$field must be a boolean');
    }

    return value;
  }

  static void _validateVariantSummary({
    required bool hasVariants,
    required List<BusinessProductVariantApiModel> variants,
    required double price,
    required double finalPrice,
    required bool inStock,
    required double? minPrice,
    required double? maxPrice,
    required double? minFinalPrice,
    required double? maxFinalPrice,
  }) {
    Never fail(String detail) {
      throw ApiContractException('product', detail);
    }

    if (!hasVariants) {
      if (variants.isNotEmpty) {
        fail('a simple product cannot expose variants');
      }

      if (minPrice == null ||
          maxPrice == null ||
          minFinalPrice == null ||
          maxFinalPrice == null) {
        fail('a simple product must expose complete price bounds');
      }

      if (minPrice != price ||
          maxPrice != price ||
          minFinalPrice != finalPrice ||
          maxFinalPrice != finalPrice) {
        fail('simple-product price bounds must match its prices');
      }

      return;
    }

    if (variants.isEmpty) {
      if (inStock ||
          minPrice != null ||
          maxPrice != null ||
          minFinalPrice != null ||
          maxFinalPrice != null) {
        fail('a variant product with no active variants must be unavailable');
      }

      return;
    }

    if (minPrice == null ||
        maxPrice == null ||
        minFinalPrice == null ||
        maxFinalPrice == null) {
      fail('a sellable variant product must expose price bounds');
    }

    var expectedMinPrice = variants.first.price;
    var expectedMaxPrice = variants.first.price;
    var expectedMinFinalPrice = variants.first.finalPrice;
    var expectedMaxFinalPrice = variants.first.finalPrice;

    for (final variant in variants.skip(1)) {
      if (variant.price < expectedMinPrice) {
        expectedMinPrice = variant.price;
      }
      if (variant.price > expectedMaxPrice) {
        expectedMaxPrice = variant.price;
      }
      if (variant.finalPrice < expectedMinFinalPrice) {
        expectedMinFinalPrice = variant.finalPrice;
      }
      if (variant.finalPrice > expectedMaxFinalPrice) {
        expectedMaxFinalPrice = variant.finalPrice;
      }
    }

    if (minPrice != expectedMinPrice ||
        maxPrice != expectedMaxPrice ||
        minFinalPrice != expectedMinFinalPrice ||
        maxFinalPrice != expectedMaxFinalPrice) {
      fail('variant price bounds disagree with server variant facts');
    }

    if (inStock != variants.any((variant) => variant.inStock)) {
      fail('variant availability disagrees with server variant facts');
    }
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
  final String logoUrl;
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
    this.logoUrl = '',
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
      logoUrl: json['logoUrl'] as String? ?? '',
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
  final String logoUrl;
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
    this.logoUrl = '',
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
      logoUrl: json['logoUrl'] as String? ?? '',
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

class RecommendationApiResponse {
  final bool consentEnabled;
  final String consentStatus;
  final bool personalized;
  final List<String> preferenceCategories;
  final List<SearchBusinessApiModel> recommendations;

  const RecommendationApiResponse({
    required this.consentEnabled,
    required this.consentStatus,
    required this.personalized,
    required this.preferenceCategories,
    required this.recommendations,
  });

  bool get consentGranted => consentEnabled && consentStatus == 'granted';

  factory RecommendationApiResponse.fromJson(Map<String, dynamic> json) {
    final rawConsent = json['consent'];

    if (rawConsent is! Map) {
      throw const ApiContractException(
        'recommendations',
        'consent must be an object',
      );
    }

    final consent = Map<String, dynamic>.from(rawConsent);

    final enabled = consent['enabled'];
    final status = consent['status'];

    if (enabled is! bool) {
      throw const ApiContractException(
        'recommendations',
        'consent.enabled must be boolean',
      );
    }

    if (status is! String ||
        !const {'notAsked', 'granted', 'denied'}.contains(status)) {
      throw const ApiContractException(
        'recommendations',
        'consent.status is invalid',
      );
    }

    final personalized = json['personalized'];

    if (personalized is! bool) {
      throw const ApiContractException(
        'recommendations',
        'personalized must be boolean',
      );
    }

    final rawCategories = json['preferenceCategories'];

    if (rawCategories is! List) {
      throw const ApiContractException(
        'recommendations',
        'preferenceCategories must be a list',
      );
    }

    final categories = <String>[];

    for (final rawCategory in rawCategories) {
      if (rawCategory is! String || rawCategory.trim().isEmpty) {
        throw const ApiContractException(
          'recommendations',
          'preferenceCategories contains an invalid category',
        );
      }

      categories.add(rawCategory.trim());
    }

    final rawRecommendations = json['recommendations'];

    if (rawRecommendations is! List) {
      throw const ApiContractException(
        'recommendations',
        'recommendations must be a list',
      );
    }

    final businesses = <SearchBusinessApiModel>[];

    for (final rawBusiness in rawRecommendations) {
      if (rawBusiness is! Map) {
        throw const ApiContractException(
          'recommendations',
          'recommendation entry must be an object',
        );
      }

      final business = SearchBusinessApiModel.fromJson(
        Map<String, dynamic>.from(rawBusiness),
      );

      if (business.id.trim().isEmpty) {
        throw const ApiContractException(
          'recommendations',
          'recommendation entry has no business id',
        );
      }

      businesses.add(business);
    }

    return RecommendationApiResponse(
      consentEnabled: enabled,
      consentStatus: status,
      personalized: personalized,
      preferenceCategories: List.unmodifiable(categories),
      recommendations: List.unmodifiable(businesses),
    );
  }
}

class OrderItemRequest {
  final String productId;
  final String? variantId;
  final int quantity;

  const OrderItemRequest({
    required this.productId,
    required this.quantity,
    this.variantId,
  });

  /// Only sellable identity and quantity leave the client.
  ///
  /// Variant label, price and stock are server facts and are never submitted.
  Map<String, dynamic> toJson() {
    final normalizedVariantId = variantId?.trim();

    return {
      'productId': productId,
      if (normalizedVariantId != null && normalizedVariantId.isNotEmpty)
        'variantId': normalizedVariantId,
      'quantity': quantity,
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

class OrderCourierLocationApiModel {
  final double latitude;
  final double longitude;
  final double? accuracy;
  final DateTime capturedAt;
  final DateTime receivedAt;
  final DateTime capabilityExpiresAt;

  const OrderCourierLocationApiModel({
    required this.latitude,
    required this.longitude,
    required this.capturedAt,
    required this.receivedAt,
    required this.capabilityExpiresAt,
    this.accuracy,
  });

  static const visibilityWindow = Duration(minutes: 15);

  static const maximumFutureSkew = Duration(minutes: 2);

  DateTime get visibleUntil {
    final freshnessDeadline = capturedAt.add(visibilityWindow);

    return capabilityExpiresAt.isBefore(freshnessDeadline)
        ? capabilityExpiresAt
        : freshnessDeadline;
  }

  bool isFreshAt(DateTime now) {
    final ageMicroseconds = now.difference(capturedAt).inMicroseconds;

    return ageMicroseconds <= visibilityWindow.inMicroseconds &&
        ageMicroseconds >= -maximumFutureSkew.inMicroseconds &&
        now.isBefore(capabilityExpiresAt);
  }

  static OrderCourierLocationApiModel? fromJsonValue(Object? raw) {
    if (raw == null) {
      return null;
    }

    if (raw is! Map<String, dynamic>) {
      throw const ApiContractException(
        'order',
        'tracking.courierLocation has the wrong type',
      );
    }

    final latitudeValue = raw['latitude'];
    final longitudeValue = raw['longitude'];
    final accuracyValue = raw['accuracy'];
    final capturedAtValue = raw['capturedAt'];
    final receivedAtValue = raw['receivedAt'];
    final capabilityExpiresAtValue = raw['capabilityExpiresAt'];

    if (latitudeValue is! num || longitudeValue is! num) {
      throw const ApiContractException(
        'order',
        'tracking.courierLocation coordinates are invalid',
      );
    }

    final latitude = latitudeValue.toDouble();
    final longitude = longitudeValue.toDouble();

    if (!latitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        !longitude.isFinite ||
        longitude < -180 ||
        longitude > 180) {
      throw const ApiContractException(
        'order',
        'tracking.courierLocation coordinates are out of range',
      );
    }

    double? accuracy;

    if (accuracyValue != null) {
      if (accuracyValue is! num) {
        throw const ApiContractException(
          'order',
          'tracking.courierLocation accuracy is invalid',
        );
      }

      accuracy = accuracyValue.toDouble();

      if (!accuracy.isFinite || accuracy < 0 || accuracy > 10000) {
        throw const ApiContractException(
          'order',
          'tracking.courierLocation accuracy is out of range',
        );
      }
    }

    if (capturedAtValue is! String ||
        receivedAtValue is! String ||
        capabilityExpiresAtValue is! String) {
      throw const ApiContractException(
        'order',
        'tracking.courierLocation timestamps are invalid',
      );
    }

    final capturedAt = DateTime.tryParse(capturedAtValue);

    final receivedAt = DateTime.tryParse(receivedAtValue);

    final capabilityExpiresAt = DateTime.tryParse(capabilityExpiresAtValue);

    if (capturedAt == null ||
        receivedAt == null ||
        capabilityExpiresAt == null) {
      throw const ApiContractException(
        'order',
        'tracking.courierLocation timestamps are invalid',
      );
    }

    if (!capabilityExpiresAt.isAfter(receivedAt)) {
      throw const ApiContractException(
        'order',
        'tracking.courierLocation capability expiry is invalid',
      );
    }

    return OrderCourierLocationApiModel(
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
      capturedAt: capturedAt,
      receivedAt: receivedAt,
      capabilityExpiresAt: capabilityExpiresAt,
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
  final OrderCourierLocationApiModel? courierLocation;
  final bool canCancel;
  final bool canChangeAddress;
  final bool canReview;

  const OrderTrackingApiModel({
    required this.isCancelled,
    required this.currentStep,
    required this.currentIndex,
    required this.steps,
    required this.courier,
    this.courierLocation,
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
      // Absence is fail-closed for the optional live map. A present malformed
      // location is still a contract failure.
      courierLocation: OrderCourierLocationApiModel.fromJsonValue(
        json['courierLocation'],
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

  /// Stable purchased variant identity. Null means a legacy/simple product.
  final String? variantId;

  final String name;
  final String imageUrl;
  final double unitPrice;
  final int quantity;

  /// Historical purchase-time display snapshot.
  final String variant;

  const OrderItemApiModel({
    required this.productId,
    required this.name,
    required this.imageUrl,
    required this.unitPrice,
    required this.quantity,
    required this.variant,
    this.variantId,
  });

  factory OrderItemApiModel.fromJson(Map<String, dynamic> json) {
    final rawVariantId = json['variantId'];
    final normalizedVariantId = rawVariantId is String
        ? rawVariantId.trim()
        : '';

    return OrderItemApiModel(
      productId: json['productId'] as String? ?? '',
      variantId: normalizedVariantId.isEmpty ? null : normalizedVariantId,
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

  /// Canonical date-only `YYYY-MM-DD`, or null for an account that has never
  /// supplied one. A `DateTime` is deliberately not used: a birth date is a
  /// calendar fact and must not shift under a timezone conversion.
  final String? birthDate;
  final bool canChangeName;
  final bool canChangeGender;
  final UserPermissions permissions;
  final UserPermissionConsents permissionConsents;

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
    this.birthDate,
    this.permissionConsents = const UserPermissionConsents(),
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
      birthDate: canonicalBirthDate(json['birthDate']),
      canChangeName: json['canChangeName'] as bool? ?? true,
      canChangeGender: json['canChangeGender'] as bool? ?? true,
      permissions: UserPermissions.fromJson(
        json['permissions'] as Map<String, dynamic>? ?? {},
      ),
      permissionConsents: UserPermissionConsents.fromJson(
        json['permissionConsents'],
      ),
    );
  }
}

final _birthDatePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})');

/// The canonical `YYYY-MM-DD` a backend value denotes, or null.
///
/// Anything that is not a real Gregorian calendar date resolves to null rather
/// than to a silently normalized neighbouring day. A longer ISO string is
/// truncated to its calendar part so no timezone conversion can move it.
String? canonicalBirthDate(Object? raw) {
  if (raw is! String) {
    return null;
  }

  final match = _birthDatePattern.firstMatch(raw);

  if (match == null) {
    return null;
  }

  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);

  if (month < 1 || month > 12 || day < 1 || day > 31) {
    return null;
  }

  final parsed = DateTime.utc(year, month, day);

  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    return null;
  }

  return match.group(0);
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

class UserPermissionConsent {
  final String status;
  final DateTime? askedAt;
  final DateTime? respondedAt;

  const UserPermissionConsent({
    this.status = 'notAsked',
    this.askedAt,
    this.respondedAt,
  });

  bool get isGranted => status == 'granted';

  factory UserPermissionConsent.fromJson(Object? raw) {
    if (raw is! Map) {
      return const UserPermissionConsent();
    }

    final json = Map<String, dynamic>.from(raw);
    final rawStatus = json['status'];

    final status = switch (rawStatus) {
      'granted' => 'granted',
      'denied' => 'denied',
      'notAsked' => 'notAsked',
      _ => 'notAsked',
    };

    return UserPermissionConsent(
      status: status,
      askedAt: DateTime.tryParse(json['askedAt'] as String? ?? ''),
      respondedAt: DateTime.tryParse(json['respondedAt'] as String? ?? ''),
    );
  }
}

class UserPermissionConsents {
  final UserPermissionConsent aiPersonalization;
  final UserPermissionConsent location;
  final UserPermissionConsent contacts;

  const UserPermissionConsents({
    this.aiPersonalization = const UserPermissionConsent(),
    this.location = const UserPermissionConsent(),
    this.contacts = const UserPermissionConsent(),
  });

  factory UserPermissionConsents.fromJson(Object? raw) {
    if (raw is! Map) {
      return const UserPermissionConsents();
    }

    final json = Map<String, dynamic>.from(raw);

    return UserPermissionConsents(
      aiPersonalization: UserPermissionConsent.fromJson(
        json['aiPersonalization'],
      ),
      location: UserPermissionConsent.fromJson(json['location']),
      contacts: UserPermissionConsent.fromJson(json['contacts']),
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

/// A delivery tier and what the server charges for it.
final class DeliveryOptionApiModel {
  final String option;
  final double fee;

  const DeliveryOptionApiModel({required this.option, required this.fee});

  factory DeliveryOptionApiModel.fromJson(Map<String, dynamic> json) {
    return DeliveryOptionApiModel(
      option: json['option'] as String? ?? '',
      fee: (json['fee'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Every tier a buyer may choose between, and which one is assumed.
final class DeliveryOptionsApiResponse {
  final List<DeliveryOptionApiModel> options;
  final String defaultOption;

  const DeliveryOptionsApiResponse({
    required this.options,
    required this.defaultOption,
  });

  factory DeliveryOptionsApiResponse.fromJson(Map<String, dynamic> json) {
    final List<dynamic> raw = json['options'] as List<dynamic>? ?? const [];

    return DeliveryOptionsApiResponse(
      options: raw
          .whereType<Map<String, dynamic>>()
          .map(DeliveryOptionApiModel.fromJson)
          .where((DeliveryOptionApiModel option) => option.option.isNotEmpty)
          .toList(),
      defaultOption: json['defaultOption'] as String? ?? 'standard',
    );
  }

  /// The fee for [option], or null when the server did not offer it.
  double? feeFor(String option) {
    for (final DeliveryOptionApiModel candidate in options) {
      if (candidate.option == option) return candidate.fee;
    }

    return null;
  }
}

/// One saved delivery address.
final class SavedAddressApiModel {
  final String id;
  final String label;
  final String fullName;
  final String phone;
  final String altPhone;
  final String governorate;
  final String city;
  final String details;
  final bool isDefault;

  const SavedAddressApiModel({
    required this.id,
    required this.label,
    required this.fullName,
    required this.phone,
    required this.altPhone,
    required this.governorate,
    required this.city,
    required this.details,
    required this.isDefault,
  });

  factory SavedAddressApiModel.fromJson(Map<String, dynamic> json) {
    return SavedAddressApiModel(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      fullName: json['fullName'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      altPhone: json['altPhone'] as String? ?? '',
      governorate: json['governorate'] as String? ?? '',
      city: json['city'] as String? ?? '',
      details: json['details'] as String? ?? '',
      isDefault: json['isDefault'] as bool? ?? false,
    );
  }

  /// The one line an order records, matching what the server writes — a city
  /// named after its governorate is written once.
  String get line => <String>[
    governorate,
    if (city != governorate) city,
    details,
  ].where((String part) => part.isNotEmpty).join(' ، ');
}

/// A governorate and the cities under it, with whether it is served.
final class DeliveryRegionApiModel {
  final String governorate;
  final bool open;
  final List<String> cities;

  const DeliveryRegionApiModel({
    required this.governorate,
    required this.open,
    required this.cities,
  });

  factory DeliveryRegionApiModel.fromJson(Map<String, dynamic> json) {
    final List<dynamic> cities = json['cities'] as List<dynamic>? ?? const [];

    return DeliveryRegionApiModel(
      governorate: json['governorate'] as String? ?? '',
      open: json['open'] as bool? ?? false,
      cities: cities.whereType<String>().toList(),
    );
  }
}
