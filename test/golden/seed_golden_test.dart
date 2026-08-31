// MERZOX-UI-GOLDEN-I4-I1 - the five deterministic seed goldens.
//
// These are Flutter rendering baselines captured on the canonical Windows
// golden environment. They are NOT evidence of Adobe XD parity: nothing here
// compares a Merzox screen against an XD reference, and no production widget is
// adjusted to make a capture look "right".
//
// Every fixture below is feature specific and therefore lives here rather than
// in `merzox_golden_harness.dart`. The construction strategies are the ones the
// existing suite already proves:
//
//   * `test/widget_test.dart`          - Arabic `EasyLocalization` pump, the
//                                        `OnboardingBloc` + `SharedPreferences`
//                                        mock setup, and the
//                                        `ApiService`-subclass fake used to
//                                        keep `AuthBloc` off the network.
//   * `test/merchant_store_preview_test.dart`
//                                      - the merchant/storefront fake API pair,
//                                        the `BusinessStarted` /
//                                        `BusinessProfileStarted` await-ready
//                                        wiring, and the `storefrontBloc` seam
//                                        on `StorePreviewPage`.

import 'dart:async';

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/about_us/bloc/about_us_bloc.dart';
import 'package:merzox/features/about_us/bloc/about_us_event.dart';
import 'package:merzox/features/about_us/bloc/about_us_state.dart';
import 'package:merzox/features/about_us/pages/about_us_page.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:merzox/features/authentication/pages/login_page.dart';
import 'package:merzox/features/authentication/pages/signup_page.dart';
import 'package:merzox/features/business/models/business_models.dart';
import 'package:merzox/features/business/preview/store_preview_page.dart';
import 'package:merzox/features/business/shell/business_bloc.dart';
import 'package:merzox/features/business/shell/business_shell_page.dart';
import 'package:merzox/features/business_profile/bloc/business_profile_bloc.dart';
import 'package:merzox/features/business_profile/bloc/business_profile_event.dart';
import 'package:merzox/features/business_profile/bloc/business_profile_state.dart';
import 'package:merzox/features/business_profile/business_profile_view_mode.dart';
import 'package:merzox/features/business_profile/pages/business_profile_page.dart';
import 'package:merzox/features/cart/bloc/cart_bloc.dart';
import 'package:merzox/features/cart/bloc/cart_event.dart';
import 'package:merzox/features/cart/bloc/cart_state.dart';
import 'package:merzox/features/cart/cart_storage_keys.dart';
import 'package:merzox/features/checkout/pages/checkout_page.dart';
import 'package:merzox/features/favorites/bloc/favorites_bloc.dart';
import 'package:merzox/features/favorites/bloc/favorites_event.dart';
import 'package:merzox/features/favorites/bloc/favorites_state.dart';
import 'package:merzox/features/favorites/pages/favorites_page.dart';
import 'package:merzox/features/home/home_screen.dart';
import 'package:merzox/features/home/presentation/bloc/home_bloc.dart';
import 'package:merzox/features/home/presentation/bloc/home_event.dart';
import 'package:merzox/features/home/presentation/bloc/home_state_.dart';
import 'package:merzox/features/onboarding/bloc/onboarding_bloc.dart';
import 'package:merzox/features/product_details/bloc/product_details_bloc.dart';
import 'package:merzox/features/product_details/bloc/product_details_event.dart';
import 'package:merzox/features/product_details/bloc/product_details_state.dart';
import 'package:merzox/features/product_details/pages/product_details_page.dart';
import 'package:merzox/features/onboarding/view/onboarding_screen.dart';
import 'package:merzox/features/checkout/pages/address_form_page.dart';
import 'package:merzox/features/business/shell/merchant_product_images_page.dart';
import 'package:merzox/features/messages/bloc/chat_bloc.dart';
import 'package:merzox/features/messages/bloc/chat_event.dart';
import 'package:merzox/features/messages/bloc/chat_state.dart';
import 'package:merzox/features/messages/pages/chat_page.dart';
import 'package:merzox/features/business/enrollment/business_enrollment_bloc.dart';
import 'package:merzox/features/business/enrollment/business_enrollment_page.dart';
import 'package:merzox/features/business/orders/merchant_order_detail_page.dart';
import 'package:merzox/features/business/orders/merchant_order_invoice_page.dart';
import 'package:merzox/features/business/products/merchant_product_editor_page.dart';
import 'package:merzox/features/business/products/merchant_product_options_dialog.dart';
import 'package:merzox/features/orders/bloc/orders_bloc.dart';
import 'package:merzox/features/orders/bloc/orders_event.dart';
import 'package:merzox/features/orders/bloc/orders_state.dart';
import 'package:merzox/features/orders/pages/orders_page.dart';
import 'package:merzox/features/orders/bloc/order_tracking_bloc.dart';
import 'package:merzox/features/orders/bloc/order_tracking_event.dart';
import 'package:merzox/features/orders/bloc/order_tracking_state.dart';
import 'package:merzox/features/orders/pages/order_tracking_page.dart';
import 'package:merzox/features/splash/presentation/splash_screen.dart';
import 'package:merzox/services/api_service.dart';
import 'package:merzox/features/business/settings/store_settings_page.dart';
import 'package:merzox/services/notification_preference_service.dart';
import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:merzox/features/profile/bloc/profile_edit_bloc.dart';
import 'package:merzox/features/profile/bloc/profile_edit_event.dart';
import 'package:merzox/features/profile/bloc/profile_edit_state.dart';
import 'package:merzox/features/profile/pages/profile_edit_page.dart';
import 'package:merzox/features/search/bloc/search_bloc.dart';
import 'package:merzox/features/search/bloc/search_event.dart';
import 'package:merzox/features/search/bloc/search_state.dart';
import 'package:merzox/features/search/pages/search_page.dart';
import 'package:merzox/features/notifications/bloc/notifications_bloc.dart';
import 'package:merzox/features/notifications/bloc/notifications_event.dart';
import 'package:merzox/features/messages/bloc/messages_bloc.dart';
import 'package:merzox/features/messages/bloc/messages_event.dart';
import 'package:merzox/features/messages/bloc/messages_state.dart';
import 'package:merzox/features/messages/pages/messages_inbox_view.dart';
import 'package:merzox/features/notifications/pages/notifications_page.dart';
import 'package:merzox/features/notifications/bloc/notifications_state.dart';
import 'package:merzox/services/device_location_service.dart';
import 'package:merzox/services/location_permission_service.dart';
import 'package:merzox/services/review_eligibility_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'merzox_golden_harness.dart';

// ---------------------------------------------------------------------------
// Login fixture
// ---------------------------------------------------------------------------

/// An [ApiService] that cannot reach the network.
///
/// The idle authentication goldens never submit a form, so any call here
/// means a capture drifted into a request-driven state and the test should say so
/// rather than quietly hit a real endpoint.
final class _OfflineAuthApiService extends ApiService {
  @override
  Future<AuthApiResponse> login({
    required String identifier,
    required String password,
  }) async {
    throw StateError('an idle authentication golden must not call login()');
  }

  @override
  Future<SignupApiResponse> signup({
    required String name,
    String? email,
    String? phone,
    required String password,
    required String userType,
    String address = '',
    String gender = 'unspecified',
  }) async {
    throw StateError('an idle authentication golden must not call signup()');
  }
}

// ---------------------------------------------------------------------------
// Home shell fixture
// ---------------------------------------------------------------------------

/// An [ApiService] the home shell cannot reach the network through.
///
/// The guest cart seed never dispatches `HomeStarted`, so no catalog request
/// belongs to this capture. A call here means the fixture drifted into a
/// data-driven state and the test should say so rather than reach a real
/// endpoint.
final class _OfflineHomeApiService extends ApiService {
  @override
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
    throw StateError('the guest cart golden must not call businesses()');
  }
}

// ---------------------------------------------------------------------------
// Favorites fixture
// ---------------------------------------------------------------------------

/// One liked product, repeated four times as the artboard's 2x2 grid shows.
///
/// `imageUrl` is deliberately blank. The artboard puts a photograph in each
/// card; a golden must not fetch one, so the card reaches its placeholder
/// branch instead. That difference is real and is recorded in the mapping's
/// semantic reason rather than hidden.
Map<String, dynamic> _seedFavoriteProduct(int index) {
  return <String, dynamic>{
    'business': <String, dynamic>{
      'id': '64b00000000000000000001$index',
      'publicId': '002010$index',
      'name': 'متجر الياسمين',
      'category': 'أفضل المتاجر',
    },
    'product': <String, dynamic>{
      'id': '64c00000000000000000001$index',
      'name': index.isEven ? 'أساس فت مي' : 'بودرة نوت',
      'description': '',
      'price': index.isEven ? 65 : 40,
      'discountPercent': 0,
      'finalPrice': index.isEven ? 65 : 40,
      'inStock': true,
      'imageUrl': '',
      'imageUrls': <String>[],
      'classification': 'new',
      'rating': 4,
      'ratingCount': 12,
      'likeCount': 3,
      'isService': false,
      // The product contract refuses to default these. A simple product must
      // still expose complete price bounds - they collapse onto its single
      // price - because a missing bound would otherwise be inferred here.
      'hasVariants': false,
      'variants': <Map<String, dynamic>>[],
      'minPrice': index.isEven ? 65 : 40,
      'maxPrice': index.isEven ? 65 : 40,
      'minFinalPrice': index.isEven ? 65 : 40,
      'maxFinalPrice': index.isEven ? 65 : 40,
    },
    'favoritedAt': '2022-02-15T14:40:00.000',
  };
}

final class _SeedFavoritesApi extends ApiService {
  @override
  Future<FavoriteProductListApiResponse> favoriteProducts({
    required String token,
    int page = 1,
    int limit = 20,
  }) async {
    return FavoriteProductListApiResponse.fromJson(<String, dynamic>{
      'products': <Map<String, dynamic>>[
        for (int index = 0; index < 4; index++) _seedFavoriteProduct(index),
      ],
      'pagination': <String, dynamic>{'page': 1, 'total': 4, 'hasMore': false},
    });
  }

  @override
  Future<FavoriteBusinessListApiResponse> favoriteBusinesses({
    required String token,
    int page = 1,
    int limit = 20,
  }) async {
    return FavoriteBusinessListApiResponse.fromJson(const <String, dynamic>{
      'businesses': <Map<String, dynamic>>[],
      'pagination': <String, dynamic>{'page': 1, 'total': 0, 'hasMore': false},
    });
  }
}

// ---------------------------------------------------------------------------
// About Us fixture
// ---------------------------------------------------------------------------

/// The `من نحن` page is server-driven, so its seed serves the payload the
/// artboard draws: the wordmark line, one introduction paragraph and the three
/// collapsed sections. Nothing is expanded - the artboard shows all three shut.
final class _SeedAboutUsApi extends ApiService {
  @override
  Future<AboutUsApiModel> aboutUs({required String languageCode}) async {
    return AboutUsApiModel.fromJson(<String, dynamic>{
      'pageTitle': 'من نحن',
      'appLabel': 'تطبيق',
      'appName': 'MERZOX',
      'introduction':
          'نص افتراضي نص افتراضي نص افتراضي نص افتراضي نص افتراضي نص افتراضي '
          'نص افتراضي نص افتراضي نص افتراضي نص افتراضي نص افتراضي نص افتراضي '
          'نص افتراضي',
      'sections': <Map<String, dynamic>>[
        <String, dynamic>{
          'key': 'how',
          'title': 'آلية العمل',
          'content': 'نص افتراضي',
        },
        <String, dynamic>{
          'key': 'terms',
          'title': 'شروط العمل',
          'content': 'نص افتراضي',
        },
        <String, dynamic>{
          'key': 'rules',
          'title': 'أحكام العمل',
          'content': 'نص افتراضي',
        },
      ],
      'updatedAt': null,
    });
  }
}

// ---------------------------------------------------------------------------
// Product details fixture
// ---------------------------------------------------------------------------

/// The product the `تفاصيل المتجر – 8` artboard draws: one foundation with
/// three shade variants, priced 5.5, in stock.
///
/// Variants are spelled out because the artboard shows the shade chips, and
/// the product contract refuses to infer either the variants or the price
/// bounds they imply.
Map<String, dynamic> _seedDetailedProduct() {
  return <String, dynamic>{
    'id': '64c000000000000000000099',
    'name': 'أساس فت مي',
    'description':
        'كريم أساس بتغطية متوسطة وثبات طويل، يمنح البشرة مظهرًا طبيعيًا '
        'ومتجانسًا طوال اليوم.',
    'price': 5.5,
    'discountPercent': 0,
    'finalPrice': 5.5,
    'inStock': true,
    'imageUrl': '',
    'imageUrls': <String>[],
    'classification': 'new',
    'rating': 5,
    'ratingCount': 50,
    'likeCount': 12,
    'isService': false,
    'hasVariants': true,
    'variants': <Map<String, dynamic>>[
      for (final (int index, String shade) in <String>[
        '01',
        '02',
        '03',
      ].indexed)
        <String, dynamic>{
          // A real object id: the variant contract refuses anything else.
          'id': '64d00000000000000000010$index',
          // The contract names it `label`, and refuses an empty one.
          'label': shade,
          'price': 5.5,
          'finalPrice': 5.5,
          'inStock': true,
        },
    ],
    'minPrice': 5.5,
    'maxPrice': 5.5,
    'minFinalPrice': 5.5,
    'maxFinalPrice': 5.5,
  };
}

final class _SeedProductApi extends ApiService {
  /// Whether `تفاصيل المتجر – 34` has anything to list.
  final bool withReviews;

  _SeedProductApi({this.withReviews = false});

  @override
  Future<BusinessProductApiModel> businessProduct({
    required String businessId,
    required String productId,
  }) async => BusinessProductApiModel.fromJson(_seedDetailedProduct());

  @override
  Future<List<BusinessReviewApiModel>> productReviews({
    required String businessId,
    required String productId,
  }) async {
    if (!withReviews) return const <BusinessReviewApiModel>[];

    // The board draws three, all five stars and all the same sentence.
    return <BusinessReviewApiModel>[
      for (int index = 0; index < 3; index++)
        BusinessReviewApiModel.fromJson(<String, dynamic>{
          'id': '64f00000000000000000000$index',
          'userName': 'ياسمين خالد',
          'rating': 5,
          'comment':
              'قمت بشراء الاساس ، للأمانة جدًا رفيع وأنا مبسوطة بالتعامل '
              'معهم، حيث أني اعتمدت المتجر ومنتجاته',
          'createdAt': '2022-02-15T14:40:00.000',
        }),
    ];
  }
}

// ---------------------------------------------------------------------------
// Nearby map fixture
// ---------------------------------------------------------------------------
// Conversation fixture
// ---------------------------------------------------------------------------

/// The exchange `الرسائل – 2` and its merchant twin draw, in the order they
/// draw it.
///
/// `isMine` is what decides which side a bubble sits on, so the two seeds are
/// the same six lines with that flag inverted: the customer's own words are on
/// one side of their screen and on the other side of the shop's.
final class _SeedChatApi extends ApiService {
  /// Whether the capture is the customer's screen or the shop's.
  final bool asCustomer;

  /// How many of the six lines the thread has reached. Zero is the thread a
  /// customer opens for the first time, which `تفاصيل المتجر – 18` draws.
  final int lineCount;

  _SeedChatApi({required this.asCustomer, this.lineCount = 6});

  static const List<(String, bool)> _lines = <(String, bool)>[
    ('مرحبا ، عندي استفسار ؟', true),
    ('هلا ، تفضلي شو عاوزة ؟', false),
    ('قديه بدها الطلبية لتوصلني؟', true),
    ('مو كثير ، إن شاء الله يومين', false),
    ('تمام ، شكرا كثير', true),
    ('ولو العفو ، أهلا وسهلا', false),
  ];

  ConversationApiModel get _conversation => ConversationApiModel(
    id: 'c-seed',
    title: asCustomer ? 'متجر الياسمين' : 'ياسمين خالد',
    avatarUrl: '',
    business: const ConversationPartyApiModel(
      id: '64b000000000000000000009',
      name: 'متجر الياسمين',
      logoUrl: '',
    ),
    customer: const ConversationPartyApiModel(
      id: '64a000000000000000000009',
      name: 'ياسمين خالد',
      logoUrl: '',
    ),
    lastMessage: ConversationLastMessageApiModel(
      body: _lines.last.$1,
      senderType: 'business',
      sentAt: DateTime.utc(2022, 2, 15, 9, 43),
    ),
    unreadCount: 0,
    messageCount: lineCount,
    updatedAt: DateTime.utc(2022, 2, 15, 9, 43),
  );

  @override
  Future<ConversationMessagesApiResponse> conversationMessages({
    required String token,
    required String conversationId,
    int page = 1,
    int limit = 30,
  }) async {
    return ConversationMessagesApiResponse(
      conversation: _conversation,
      messages: <MessageApiModel>[
        for (int index = 0; index < lineCount; index++)
          MessageApiModel(
            id: 'm$index',
            conversationId: 'c-seed',
            // The customer wrote the odd-indexed-false lines; on the shop's
            // screen those are the incoming ones.
            senderType: _lines[index].$2 ? 'customer' : 'business',
            senderName: _lines[index].$2 ? 'ياسمين خالد' : 'متجر الياسمين',
            body: _lines[index].$1,
            isMine: asCustomer ? _lines[index].$2 : !_lines[index].$2,
            readAt: null,
            createdAt: DateTime.utc(2022, 2, 15, 9, 40 + index),
          ),
      ],
      page: page,
      hasMore: false,
    );
  }

  @override
  Future<ConversationApiModel> markConversationRead({
    required String token,
    required String conversationId,
  }) async => _conversation;
}

// ---------------------------------------------------------------------------
// Customer order history fixture
// ---------------------------------------------------------------------------

/// One card of `تفاصيل المتجر – 21`, with the artboard's own numbers.
///
/// 35 + 10 = 45, ordered on 30/1/2022, one unit of `أساس فت مي`. `imageUrl` is
/// empty because the repository ships no product photography - the card falls
/// back to its placeholder rather than reaching the network mid-capture.
Map<String, dynamic> _seedCustomerOrder({
  required int index,
  required String statusGroup,
  required String status,
  String cancellationReason = '',
}) {
  return <String, dynamic>{
    'id': '64d00000000000000000010$index',
    'publicId': '222321',
    'business': <String, dynamic>{
      'id': '64b000000000000000000009',
      'name': 'متجر الياسمين',
    },
    'items': <Map<String, dynamic>>[
      <String, dynamic>{
        'productId': '64c00000000000000000010$index',
        'variantId': 'v$index',
        'name': 'أساس فت مي',
        'imageUrl': '',
        'unitPrice': 35,
        'quantity': 1,
        'variant': '',
      },
    ],
    'subtotal': 35,
    'deliveryFee': 10,
    'total': 45,
    'currency': 'ILS',
    'deliveryAddress': 'رام الله ، المصيون',
    'paymentMethod': 'cash',
    'status': status,
    'statusGroup': statusGroup,
    'statusHistory': const <Map<String, dynamic>>[],
    'cancellationReason': cancellationReason,
    'createdAt': '2022-01-30T10:00:00.000',
    'courier': const <String, dynamic>{},
    'tracking': <String, dynamic>{
      'isCancelled': statusGroup == 'cancelled',
      'currentStep': 'placed',
      'currentIndex': 0,
      'steps': const <Map<String, dynamic>>[],
      'courier': const <String, dynamic>{},
      'courierLocation': null,
      'canCancel': statusGroup == 'current',
      'canChangeAddress': statusGroup == 'current',
      'canReview': statusGroup == 'completed',
    },
  };
}

/// Answers `/orders` for whichever tab the bloc asks about.
///
/// `counts.total` is the figure the tab strip is gated on, so it is the sum
/// across the three groups and not the length of the answer.
final class _SeedCustomerOrdersApi extends ApiService {
  @override
  Future<OrderListApiResponse> orders({
    required String token,
    required String status,
    int page = 1,
    int limit = 20,
  }) async {
    final List<Map<String, dynamic>> orders;
    switch (status) {
      case 'completed':
        orders = <Map<String, dynamic>>[
          for (int index = 0; index < 3; index++)
            _seedCustomerOrder(
              index: index,
              statusGroup: 'completed',
              status: 'delivered',
            ),
        ];
      case 'cancelled':
        orders = <Map<String, dynamic>>[
          for (int index = 0; index < 2; index++)
            _seedCustomerOrder(
              index: index,
              statusGroup: 'cancelled',
              status: 'cancelled',
              cancellationReason: 'قمت بشراء شي شبيه',
            ),
        ];
      default:
        orders = <Map<String, dynamic>>[
          for (int index = 0; index < 3; index++)
            _seedCustomerOrder(
              index: index,
              statusGroup: 'current',
              status: 'preparing',
            ),
        ];
    }

    return OrderListApiResponse.fromJson(<String, dynamic>{
      'orders': orders,
      'pagination': <String, dynamic>{
        'page': 1,
        'limit': limit,
        'total': orders.length,
        'hasMore': false,
      },
      'counts': const <String, dynamic>{'total': 8},
    });
  }
}

/// The same endpoint for a customer who has never ordered.
final class _SeedNoCustomerOrdersApi extends ApiService {
  @override
  Future<OrderListApiResponse> orders({
    required String token,
    required String status,
    int page = 1,
    int limit = 20,
  }) async {
    return OrderListApiResponse.fromJson(const <String, dynamic>{
      'orders': <Map<String, dynamic>>[],
      'pagination': <String, dynamic>{
        'page': 1,
        'limit': 20,
        'total': 0,
        'hasMore': false,
      },
      'counts': <String, dynamic>{'total': 0},
    });
  }
}

// ---------------------------------------------------------------------------
// Merchant order detail fixture
// ---------------------------------------------------------------------------

/// The order `تفاصيل الطلب` draws: 35 + 10 = 45, placed 15.2.2022 by
/// `ياسمين خالد`, one unit of `أساس فت مي`.
OwnerOrder _seedDetailOrder({String status = 'pending'}) {
  return OwnerOrder.fromJson(<String, dynamic>{
    'id': '64d000000000000000000201',
    'publicId': '222321',
    'customerName': 'ياسمين خالد',
    'customerPhone': '0592029316',
    'items': <Map<String, dynamic>>[
      <String, dynamic>{
        'productId': '64c000000000000000000201',
        'variantId': null,
        'name': 'أساس فت مي',
        'imageUrl': '',
        'unitPrice': 35,
        'quantity': 1,
        'variant': '',
      },
    ],
    'subtotal': 35,
    'deliveryFee': 10,
    'total': 45,
    'currency': 'ILS',
    'deliveryAddress': 'أريحا ، النبي موسى',
    'paymentMethod': 'cash',
    'status': status,
    'statusGroup': status == 'pending' ? 'current' : 'current',
    'statusHistory': const <Map<String, dynamic>>[],
    'cancellationReason': '',
    'createdAt': '2022-02-15T10:00:00.000',
    'courier': const <String, dynamic>{},
  });
}

// ---------------------------------------------------------------------------
// Order tracking fixture
// ---------------------------------------------------------------------------

const String _trackedOrderId = '64d000000000000000000001';

/// The order the `تتبع الطلب` artboard draws: placed, nothing further reached.
///
/// Every tracking field is spelled out because `OrderTrackingApiModel` refuses
/// to default them - a permission the server never sent must never be
/// synthesized here. No courier is assigned and no courier location exists, so
/// the live map and its network tiles are not part of this capture.
final class _SeedOrderTrackingApi extends ApiService {
  /// Which step the order has reached. `تتبع الطلب – 1` draws `preparing`,
  /// `– 2` draws `outForDelivery` with a driver, and `تقييم` draws it
  /// delivered with the review the customer is invited to leave.
  final String step;

  _SeedOrderTrackingApi({this.step = 'placed'});

  static const List<String> _steps = <String>[
    'placed',
    'preparing',
    'outForDelivery',
    'delivered',
  ];

  int get _index => _steps.indexOf(step);

  @override
  Future<OrderApiModel> order({
    required String token,
    required String orderId,
  }) async {
    return OrderApiModel.fromJson(<String, dynamic>{
      'id': orderId,
      'publicId': '222321',
      'business': <String, dynamic>{
        'id': '64b000000000000000000009',
        'name': 'متجر الياسمين',
      },
      'items': <Map<String, dynamic>>[],
      'subtotal': 120,
      'deliveryFee': 10,
      'total': 130,
      'currency': 'ILS',
      'deliveryAddress': 'عنوان التوصيل للاختبار',
      'paymentMethod': 'cash',
      'status': step == 'placed' ? 'pending' : step,
      'statusGroup': step == 'delivered' ? 'completed' : 'current',
      'statusHistory': <Map<String, dynamic>>[],
      'cancellationReason': '',
      // The artboard's own stamp: Saturday 15.2.2022, 02:40 PM.
      'createdAt': '2022-02-15T14:40:00.000',
      'courier': _courier,
      'tracking': <String, dynamic>{
        'isCancelled': false,
        'currentStep': step,
        'currentIndex': _index,
        'steps': <Map<String, dynamic>>[
          for (int at = 0; at < _steps.length; at++)
            <String, dynamic>{
              'step': _steps[at],
              'reachedAt': at <= _index ? _reachedAt[at] : null,
              'isReached': at <= _index,
            },
        ],
        'courier': _courier,
        'courierLocation': null,
        // A driver may be recalled and an order may be cancelled right up to
        // the point it is handed over; after that neither is true and a review
        // becomes possible instead.
        'canCancel': step != 'delivered',
        'canChangeAddress': step == 'placed' || step == 'preparing',
        'canReview': step == 'delivered',
      },
    });
  }

  /// The driver `تتبع الطلب – 2` names, and only once one is out.
  Map<String, dynamic> get _courier => _index >= 2
      ? const <String, dynamic>{
          'name': 'Hamode Hussen',
          'phone': '0592029316',
          'assignedAt': '2022-02-17T15:30:00.000',
        }
      : const <String, dynamic>{};

  static const List<String> _reachedAt = <String>[
    '2022-02-15T14:40:00.000',
    '2022-02-17T15:30:00.000',
    '2022-02-18T14:40:00.000',
    '2022-02-18T15:30:00.000',
  ];
}

/// Installs the authenticated customer session the tracking bloc reads.
void _useAuthenticatedCustomerSession() {
  SharedPreferences.setMockInitialValues(<String, Object>{
    AuthBloc.sessionKey: true,
    AuthBloc.tokenKey: 'seed-golden-token',
    AuthBloc.userTypeKey: 'customer',
  });
}

// ---------------------------------------------------------------------------
// Store preview fixtures
// ---------------------------------------------------------------------------

const String _previewBusinessId = '64b000000000000000000001';

/// Serves the merchant shell so the preview can resolve *which* business is
/// being previewed. Only the four reads `BusinessBloc` performs on start are
/// answered; anything else would be an unexpected request.
final class _SeedMerchantApi extends ApiService {
  @override
  Future<OwnerBusiness> ownerBusiness({required String token}) async {
    return OwnerBusiness.fromJson(const <String, dynamic>{
      'id': _previewBusinessId,
      'name': 'اسم المالك للمتجر',
      'englishName': 'Owner side name',
      'category': 'Owner side category',
      'address': 'Owner side address',
      'description': 'Owner side description',
      // Deliberately blank: the preview must not need a remote logo to render.
      'logoUrl': '',
      'attachmentUrl': '',
    });
  }

  @override
  Future<BusinessDashboardData> businessDashboard({
    required String token,
  }) async => BusinessDashboardData.fromJson(const <String, dynamic>{});

  @override
  Future<OwnerOrderList> ownerOrders({
    required String token,
    String statusGroup = '',
    MerchantOrderFilter filter = const MerchantOrderFilter(),
    int page = 1,
    int limit = 20,
  }) async => OwnerOrderList.fromJson(const <String, dynamic>{});

  @override
  Future<List<OwnerProduct>> ownerProducts({required String token}) async =>
      const <OwnerProduct>[];
}

/// One recent order row, in the shape the merchant dashboard table draws.
Map<String, dynamic> _seedOwnerOrder(int index) {
  const List<String> statuses = <String>[
    'pending',
    'preparing',
    'delivered',
    'outForDelivery',
    'cancelled',
  ];
  return <String, dynamic>{
    'id': '64f00000000000000000000$index',
    'publicId': '22232$index',
    'customerName': index.isEven ? 'ياسمين خالد' : 'أحلام محمد',
    'total': index.isEven ? 45 : 120,
    'status': statuses[index],
    'statusGroup': statuses[index] == 'cancelled' ? 'past' : 'current',
    'createdAt': '2022-02-15T14:40:00.000',
    'items': <Map<String, dynamic>>[],
    'customerPhone': '0590000000',
    'deliveryAddress': 'رام الله',
    'paymentMethod': 'cash',
  };
}

/// The merchant shell in its dashboard state, with the figures and the recent
/// order table the `الرئيسية – 2` artboard shows.
final class _SeedDashboardApi extends _SeedMerchantApi {
  @override
  Future<BusinessDashboardData> businessDashboard({
    required String token,
  }) async {
    return BusinessDashboardData.fromJson(<String, dynamic>{
      'sales': 98000,
      'orderCount': 25,
      'activeOrderCount': 4,
      'viewCount': 3368,
      'recentOrders': <Map<String, dynamic>>[
        for (int index = 0; index < 5; index++) _seedOwnerOrder(index),
      ],
    });
  }
}

/// The merchant order list, with the ten rows `الرئيسية – 9` tabulates.
final class _SeedMerchantOrdersApi extends _SeedMerchantApi {
  @override
  Future<OwnerOrderList> ownerOrders({
    required String token,
    String statusGroup = '',
    MerchantOrderFilter filter = const MerchantOrderFilter(),
    int page = 1,
    int limit = 20,
  }) async {
    return OwnerOrderList.fromJson(<String, dynamic>{
      'orders': <Map<String, dynamic>>[
        for (int index = 0; index < 10; index++) _seedOwnerOrder(index % 5),
      ],
      'counts': const <String, dynamic>{
        'current': 6,
        'completed': 2,
        'cancelled': 2,
        'total': 10,
      },
    });
  }
}

/// The merchant catalogue, with the four cards `الرئيسية – 10` lists.
///
/// No image URL: a golden must not reach the network, so every card draws the
/// same local placeholder and the measurement stays about the card, not the
/// photograph inside it.
final class _SeedMerchantProductsApi extends _SeedMerchantApi {
  @override
  Future<List<OwnerProduct>> ownerProducts({required String token}) async {
    return <OwnerProduct>[
      for (int index = 0; index < 4; index++)
        OwnerProduct.fromJson(<String, dynamic>{
          'id': '64d0000000000000000000$index',
          'name': 'أساس فت مي',
          'description': 'وصف المنتج',
          'price': 35,
          'stockQuantity': 40,
          'unlimitedStock': false,
          'discountPercent': 0,
          'finalPrice': 35,
          'inStock': true,
          'keywords': const <String>[],
          'imageUrls': const <String>[],
          'classification': 'new',
          'isService': false,
          'isActive': true,
          'variants': const <Map<String, dynamic>>[],
        }),
    ];
  }
}

/// One catalogue row, in the shape the home sections read.
Map<String, dynamic> _seedHomeBusiness(int index, {String? discount}) {
  return <String, dynamic>{
    'id': '64e00000000000000000000$index',
    'publicId': '002010$index',
    'name': 'متجر الياسمين',
    'englishName': 'Alyasmeen',
    'category': 'مستحضرات تجميل',
    'address': 'رام الله',
    'products': const <String>[],
    'productCount': 12,
    'rating': 4,
    'ratingCount': 20,
    'followerCount': 8,
    'viewCount': 300,
    if (discount != null) 'discount': discount,
    'colorValue': 0xFFDEEEF8,
  };
}

/// Location is a platform channel, and a widget test has none: left to the
/// real services the home bloc waits forever. The nearby shelf is below the
/// fold on both artboards, so a denied permission changes nothing measured.
final class _SeedDeniedLocation extends LocationPermissionService {
  @override
  Future<bool> isLocationGranted() async => false;
}

final class _SeedNoDeviceLocation extends DeviceLocationService {
  @override
  Future<bool> isServiceEnabled() async => false;
}

/// The customer catalogue, with the shelves `الرئيسية` draws.
///
/// The promotional carousel reads the discounted shelf, so that one carries a
/// discount label and the others do not.
final class _SeedHomeApi extends ApiService {
  @override
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
    // `المتاجر` asks for a page of fifty and the home's own strips ask for
    // ten, which is how this fixture tells them apart. The board draws eight
    // cards above its fold.
    final bool storesTab = limit >= 50;
    final int count = storesTab ? 8 : 3;

    return BusinessListApiResponse.fromJson(<String, dynamic>{
      'businesses': <Map<String, dynamic>>[
        for (int index = 0; index < count; index++)
          _seedHomeBusiness(index, discount: discounted == true ? '50%' : null),
      ],
      'pagination': <String, dynamic>{
        'page': 1,
        'limit': limit,
        'total': count,
        'hasMore': false,
      },
    });
  }

  @override
  Future<FavoriteBusinessListApiResponse> favoriteBusinesses({
    required String token,
    int page = 1,
    int limit = 20,
  }) async =>
      FavoriteBusinessListApiResponse.fromJson(const <String, dynamic>{});
}

/// A checkout that succeeds, so the confirmation has a number to show.
final class _SeedPlacingApi extends _SeedDeliveryApi {
  @override
  Future<OrderApiModel> createOrder({
    required String token,
    required String businessId,
    required List<OrderItemRequest> items,
    required String deliveryAddress,
    String paymentMethod = 'cash',
    String deliveryOption = 'standard',
    String? clientOrderId,
  }) async {
    return OrderApiModel.fromJson(<String, dynamic>{
      'id': '64f000000000000000000001',
      'publicId': '222321',
      'business': <String, dynamic>{'id': businessId, 'name': 'متجر الياسمين'},
      'items': const <Map<String, dynamic>>[],
      'subtotal': 5.5,
      'deliveryFee': 10,
      'total': 15.5,
      'currency': 'ILS',
      'status': 'pending',
      'statusGroup': 'current',
      'deliveryAddress': deliveryAddress,
      'paymentMethod': paymentMethod,
      'deliveryOption': deliveryOption,
      'createdAt': '2022-02-15T14:40:00.000Z',
      'tracking': <String, dynamic>{
        'isCancelled': false,
        'currentStep': 'placed',
        'currentIndex': 0,
        'steps': <Map<String, dynamic>>[
          <String, dynamic>{
            'step': 'placed',
            'reachedAt': '2022-02-15T14:40:00.000',
            'isReached': true,
          },
        ],
        'courier': <String, dynamic>{},
        'courierLocation': null,
        'canCancel': true,
        'canChangeAddress': true,
        'canReview': false,
      },
    });
  }
}

/// The notification preference, answered locally: the merchant profile's
/// switch would otherwise reach the network and spin forever in a golden.
final class _SeedPreferenceGateway implements NotificationPreferenceGateway {
  @override
  Future<NotificationPreferenceSnapshot> load({required String token}) async =>
      const NotificationPreferenceSnapshot(
        productOffers: true,
        orderUpdates: true,
      );

  @override
  Future<NotificationPreferenceSnapshot> update({
    required String token,
    required bool value,
    String key = NotificationPreferenceKeys.productOffers,
  }) async => NotificationPreferenceSnapshot(
    productOffers: key == NotificationPreferenceKeys.productOffers
        ? value
        : true,
    orderUpdates: key == NotificationPreferenceKeys.orderUpdates ? value : true,
  );
}

/// The signed-in customer the profile form loads.
final class _SeedProfileApi extends ApiService {
  /// Whether the account has been filled in yet.
  ///
  /// `الملف الشخصي` draws the form with every placeholder still showing and
  /// `تعديل الملف الشخصي` draws the same form with an account behind it, so
  /// the two boards are one screen before and after it has been used.
  final bool filled;

  _SeedProfileApi({this.filled = true});

  @override
  Future<AuthApiUser> me({required String token}) async {
    return AuthApiUser.fromJson(<String, dynamic>{
      'id': '64a000000000000000000001',
      'name': filled ? 'ياسمين خالد' : '',
      'email': filled ? 'yasmeen@example.test' : '',
      'emailVerified': filled,
      'emails': const <Map<String, dynamic>>[],
      'phone': filled ? '0592029316' : '',
      'phones': const <Map<String, dynamic>>[],
      'address': filled ? 'أريحا' : '',
      'addresses': const <Map<String, dynamic>>[],
      'userType': 'normal',
      'gender': filled ? 'female' : 'unspecified',
      'birthDate': filled ? '1995-04-12' : null,
      'permissions': const <String, dynamic>{},
      'permissionConsents': const <String, dynamic>{},
      'canChangeName': true,
      'canChangeGender': true,
    });
  }
}

/// The catalogue search, with the results both result artboards list.
final class _SeedSearchApi extends ApiService {
  @override
  Future<SearchApiResponse> searchCatalog({
    required String query,
    int limit = 30,
  }) async {
    return SearchApiResponse.fromJson(<String, dynamic>{
      'query': query,
      'products': <Map<String, dynamic>>[
        for (int index = 0; index < 6; index++)
          <String, dynamic>{
            ..._seedDetailedProduct(),
            'id': '64c00000000000000000010$index',
            'name': 'بوت حريمي',
            'business': _seedSearchBusiness(index),
          },
      ],
      'businesses': <Map<String, dynamic>>[
        for (int index = 0; index < 6; index++) _seedSearchBusiness(index),
      ],
    });
  }
}

Map<String, dynamic> _seedSearchBusiness(int index) => <String, dynamic>{
  'id': '64b00000000000000000020$index',
  'publicId': '002010$index',
  'name': 'متجر حرير شوب',
  'englishName': 'Harir Shop',
  'category': 'أحذية',
  'address': 'رام الله',
  'products': const <String>[],
  'productCount': 8,
  'rating': 4,
  'ratingCount': 12,
  'followerCount': 5,
  'viewCount': 120,
  'colorValue': 0xFFDEEEF8,
};

/// The delivery tiers, as the order route publishes them.
final class _SeedDeliveryApi extends _SeedProductApi {
  /// The one saved address `تفاصيل المتجر – 16` shows, with the phone it puts
  /// under the name.
  @override
  Future<List<SavedAddressApiModel>> myAddresses({
    required String token,
  }) async => <SavedAddressApiModel>[
    SavedAddressApiModel.fromJson(const <String, dynamic>{
      'id': '64e000000000000000000001',
      'label': '',
      'fullName': 'ياسمين عماد',
      'phone': '0592029316',
      'altPhone': '',
      'governorate': 'أريحا',
      'city': 'أريحا',
      'details': '',
      'isDefault': true,
    }),
  ];

  /// The regions the server actually serves, copied from
  /// `backend/src/policies/address.policy.js` so the pickers are seeded on the
  /// contract rather than on a shorter invention. The three closed ones are
  /// listed on purpose: the board marks them `مغلق` rather than hiding them.
  @override
  Future<List<DeliveryRegionApiModel>> deliveryRegions() async =>
      <DeliveryRegionApiModel>[
        DeliveryRegionApiModel.fromJson(const <String, dynamic>{
          'governorate': 'رام الله والبيرة',
          'open': true,
          'cities': <String>[
            'رام الله',
            'البيرة',
            'بيرزيت',
            'الجلزون',
            'أم الشرايط',
            'بيت سيرا',
            'تل الماصيون',
            'جمالا',
            'بدرس',
            'النبي موسى',
          ],
        }),
        DeliveryRegionApiModel.fromJson(const <String, dynamic>{
          'governorate': 'أريحا',
          'open': true,
          'cities': <String>['أريحا', 'الطيبة'],
        }),
        DeliveryRegionApiModel.fromJson(const <String, dynamic>{
          'governorate': 'سلفيت',
          'open': true,
          'cities': <String>['سلفيت', 'بديا'],
        }),
        for (final String only in <String>[
          'طولكرم',
          'الخليل',
          'بيت لحم',
          'طوباس',
          'جنين',
          'قلقيلية',
        ])
          DeliveryRegionApiModel.fromJson(<String, dynamic>{
            'governorate': only,
            'open': true,
            'cities': <String>[only],
          }),
        for (final String closed in <String>['الناصرة', 'عكا', 'الجولان'])
          DeliveryRegionApiModel.fromJson(<String, dynamic>{
            'governorate': closed,
            'open': false,
            'cities': <String>[closed],
          }),
      ];

  @override
  Future<DeliveryOptionsApiResponse> deliveryOptions() async =>
      DeliveryOptionsApiResponse.fromJson(const <String, dynamic>{
        'defaultOption': 'standard',
        'options': <Map<String, dynamic>>[
          <String, dynamic>{'option': 'standard', 'fee': 10},
          <String, dynamic>{'option': 'express', 'fee': 30},
        ],
      });
}

/// One inbox row, in the shape `الرسائل – 4` lists them.
Map<String, dynamic> _seedConversation(int index, {required bool unread}) {
  return <String, dynamic>{
    'id': '64a00000000000000000000$index',
    'title': index.isEven ? 'متجر الياسمين' : 'متجر حرير شوب',
    'avatarUrl': '',
    'business': <String, dynamic>{
      'id': '64b000000000000000000001',
      'name': index.isEven ? 'متجر الياسمين' : 'متجر حرير شوب',
      'avatarUrl': '',
    },
    'lastMessage': <String, dynamic>{
      'body': index.isEven
          ? 'متى المتجر بيفتح؟'
          : 'متوفر المزيد من العروض بداخل المتجر',
      'sentAt': '2022-02-15T09:43:00.000Z',
      'senderType': 'business',
    },
    'unreadCount': unread ? 1 : 0,
    'messageCount': 6,
    'updatedAt': '2022-02-15T09:43:00.000Z',
  };
}

/// The inbox with the four rows `الرسائل – 4` draws, alternating read state.
final class _SeedMessagesApi extends ApiService {
  @override
  Future<ConversationListApiResponse> conversations({
    required String token,
    bool unreadOnly = false,
    int page = 1,
    int limit = 20,
  }) async {
    return ConversationListApiResponse.fromJson(<String, dynamic>{
      'conversations': <Map<String, dynamic>>[
        for (int index = 0; index < 4; index++)
          _seedConversation(index, unread: index.isEven),
      ],
      'unreadConversationCount': 2,
      'pagination': const <String, dynamic>{'page': 1, 'hasMore': false},
    });
  }
}

/// The same inbox with nothing in it, which `الرسائل` draws as its own board.
final class _SeedEmptyMessagesApi extends ApiService {
  @override
  Future<ConversationListApiResponse> conversations({
    required String token,
    bool unreadOnly = false,
    int page = 1,
    int limit = 20,
  }) async => ConversationListApiResponse.fromJson(const <String, dynamic>{
    'conversations': <Map<String, dynamic>>[],
    'unreadConversationCount': 0,
    'pagination': <String, dynamic>{'page': 1, 'hasMore': false},
  });
}

/// The notifications list of `الرسائل – 5`.
final class _SeedNotificationsApi extends ApiService {
  @override
  Future<NotificationListApiResponse> notifications({
    required String token,
    bool businessAudience = false,
    bool unreadOnly = false,
    int page = 1,
    int limit = 20,
  }) async {
    return NotificationListApiResponse.fromJson(<String, dynamic>{
      'notifications': <Map<String, dynamic>>[
        for (int index = 0; index < 7; index++)
          <String, dynamic>{
            'id': '64c00000000000000000000$index',
            'type': index == 1 ? 'review' : 'order',
            'title': index == 1
                ? 'قامت ياسمين خالد بتقييم المتجر'
                : 'طلبات جديده',
            'body': index == 1 ? '' : 'يوجد لديك طلبات جديدة',
            'data': const <String, dynamic>{},
            'isRead': index > 2,
            'createdAt': '2022-02-15T09:43:00.000Z',
          },
      ],
      'unreadCount': 3,
      'pagination': const <String, dynamic>{'page': 1, 'hasMore': false},
    });
  }
}

/// The single service the Store Preview artboard shows under "About".
///
/// Deterministic and entirely local: no image URL, so the About tab renders its
/// icon placeholder instead of reaching `Image.network`. Rendering it triggers
/// no customer mutation - the About tab draws services as plain, tapless tiles.
const BusinessProductApiModel _seedService = BusinessProductApiModel(
  id: '64c000000000000000000001',
  name: 'مكياج',
  description: '',
  price: 0,
  imageUrl: '',
  imageUrls: <String>[],
  classification: 'new',
  rating: 0,
  ratingCount: 0,
  likeCount: 0,
  isService: true,
);

/// One catalogue product, in the shape the strict product contract demands.
Map<String, dynamic> _seedStorefrontProduct(int index) {
  final int price = index.isEven ? 65 : 40;
  return <String, dynamic>{
    'id': '64c00000000000000000002$index',
    'name': 'أساس فت مي',
    'description': '',
    'price': price,
    'discountPercent': 0,
    'finalPrice': price,
    'inStock': true,
    'imageUrl': '',
    'imageUrls': <String>[],
    'classification': 'new',
    'rating': 4,
    'ratingCount': 12,
    'likeCount': 3,
    'isService': false,
    'hasVariants': false,
    'variants': <Map<String, dynamic>>[],
    'minPrice': price,
    'maxPrice': price,
    'minFinalPrice': price,
    'maxFinalPrice': price,
  };
}

/// Serves the PUBLIC storefront contracts the preview reads.
///
/// Every payload is chosen so the loaded storefront renders from local
/// resources only: no product carries an image URL, there are no reviews, and
/// the business has no remote logo. `BusinessProfilePage` therefore reaches its
/// placeholder branches instead of `Image.network`, and the golden needs no
/// successful HTTP.
final class _SeedStorefrontApi extends ApiService {
  @override
  Future<BusinessDetailApiModel> business({required String businessId}) async {
    return BusinessDetailApiModel(
      id: businessId,
      publicId: '0020101',
      name: 'متجر الياسمين',
      englishName: 'Merzox demo store',
      category: 'أفضل المتاجر',
      description:
          'هذا النص افتراضي ، هذا النص افتراضي ، هذا النص افتراضي ، هذا النص '
          'افتراضي ، هذا النص افتراضي هذا النص افتراضي ، هذا النص افتراضي ، '
          'هذا النص افتراضي ، هذا النص افتراضي ، هذا النص افتراضي',
      address: '',
      // The About tab draws its services from the DETAIL payload, so the one
      // service the artboard shows lives here rather than in
      // `businessProducts`, which drives the Products tab.
      products: const <BusinessProductApiModel>[_seedService],
      productCount: 200,
      rating: 4.5,
      ratingCount: 12,
      followerCount: 300,
      viewCount: 99,
      discount: null,
      colorValue: 0xffdeeef8,
    );
  }

  @override
  Future<List<BusinessProductApiModel>> businessProducts({
    required String businessId,
    required String classification,
  }) async => const <BusinessProductApiModel>[];

  @override
  Future<List<BusinessReviewApiModel>> businessReviews({
    required String businessId,
  }) async => const <BusinessReviewApiModel>[];
}

/// Answers the eligibility question the way the artboard's state implies: a
/// signed-in customer who may write a review. The verdict is still the
/// gateway's to give - the page never derives it.
final class _SeedEligibleReviewer implements ReviewEligibilityGateway {
  const _SeedEligibleReviewer();

  @override
  Future<ReviewEligibilityDecision> businessEligibility({
    required String token,
    required String businessId,
  }) async => const ReviewEligibilityDecision(eligible: true, reason: null);

  @override
  Future<ReviewEligibilityDecision> productEligibility({
    required String token,
    required String businessId,
    required String productId,
  }) async => const ReviewEligibilityDecision(eligible: true, reason: null);
}

/// The same storefront, but with the catalogue and reviews the tab artboards
/// draw. Kept separate so the About-tab seeds keep their empty sections.
final class _SeedStorefrontTabsApi extends _SeedStorefrontApi {
  @override
  Future<List<BusinessProductApiModel>> businessProducts({
    required String businessId,
    required String classification,
  }) async {
    return <BusinessProductApiModel>[
      for (int index = 0; index < 4; index++)
        BusinessProductApiModel.fromJson(_seedStorefrontProduct(index)),
    ];
  }

  @override
  Future<List<BusinessReviewApiModel>> businessReviews({
    required String businessId,
  }) async {
    return <BusinessReviewApiModel>[
      for (int index = 0; index < 3; index++)
        BusinessReviewApiModel.fromJson(<String, dynamic>{
          'id': '64e00000000000000000000$index',
          'userName': index.isEven ? 'ياسمين خالد' : 'حمود حسين',
          'rating': index.isEven ? 5 : 4,
          'comment':
              'المتجر جدًا رائع ومميز ، وأغراضه مميزة وذات جودة عالية، وراقي '
              'جدًا في التعامل',
          'createdAt': '2022-02-15T14:40:00.000',
        }),
    ];
  }
}

/// Installs the authenticated merchant session `BusinessBloc` resolves its
/// token from. Mirrors `test/auth_session_fixtures.dart`, kept local so the
/// golden owns its own preconditions.
void _useAuthenticatedMerchantSession() {
  SharedPreferences.setMockInitialValues(<String, Object>{
    AuthBloc.sessionKey: true,
    AuthBloc.tokenKey: 'seed-golden-token',
    AuthBloc.userTypeKey: 'business',
  });
}

/// Closes [bloc] without awaiting it.
///
/// `merchant_store_preview_test.dart` records why: awaiting `close()` from
/// inside `testWidgets` waits on a stream-controller completion the faked clock
/// never delivers. Dropping the future still tears the bloc down.
void _closeOnTearDown<S>(BlocBase<S> bloc) {
  addTearDown(() => unawaited(bloc.close()));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group(
    'MERZOX seed goldens - Arabic, 375x812, Windows canonical',
    () {
      setUpAll(() async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        await EasyLocalization.ensureInitialized();
        await loadMerzoxGoldenDateSymbols();
        await loadMerzoxGoldenFonts();
      });

      tearDown(() {
        SharedPreferences.setMockInitialValues(<String, Object>{});
      });

      // -- 1. Splash ------------------------------------------------------
      //
      // `lib/features/splash/presentation/pages/splash_page.dart` is commented
      // out in full and exports no `SplashPage` type, so the current stable
      // page-level splash representation is `SplashScreen`. It is instantiated
      // as shipped; nothing about it is adjusted for the capture.
      testWidgets('splash renders its Arabic seed baseline', (
        WidgetTester tester,
      ) async {
        await pumpMerzoxGoldenPage(tester, const SplashScreen());

        await expectMerzoxSeedGolden('splash_page_ar_375x812.png');

        // The capture above is the pre-navigation splash: the production 3s
        // timer has not fired, so no timer-driven navigation is part of this
        // golden. It is drained here only so the test leaves no pending timer
        // behind.
        await tester.pump(const Duration(seconds: 3, milliseconds: 100));
        await settleMerzoxGoldenFrames(tester);
      });

      // -- 2. Onboarding, initial page ------------------------------------
      testWidgets('onboarding renders its Arabic initial-state baseline', (
        WidgetTester tester,
      ) async {
        // Same mock-preferences setup `test/widget_test.dart` uses: the bloc
        // reads and writes `onboarding_completed`, and nothing may touch real
        // machine preferences.
        SharedPreferences.setMockInitialValues(<String, Object>{});

        await pumpMerzoxGoldenPage(
          tester,
          BlocProvider<OnboardingBloc>(
            // `BlocProvider` owns and disposes the bloc, exactly as the
            // existing onboarding widget tests do.
            create: (_) => OnboardingBloc(),
            child: withMerzoxGoldenDeviceInsets(
              OnboardingScreen(onFinished: () {}),
            ),
          ),
        );

        // The seed is the first page only: no swipe, no skip, no completion.
        // These are the same Arabic labels the existing onboarding widget test
        // asserts for the initial state.
        expect(find.text('أفضل الخصومات'), findsOneWidget);
        expect(find.text('تخطي'), findsOneWidget);

        await expectMerzoxSeedGolden('onboarding_initial_ar_375x812.png');
      });

      // -- 3. Login, idle customer state ----------------------------------
      testWidgets('login renders its Arabic idle-state baseline', (
        WidgetTester tester,
      ) async {
        await pumpMerzoxGoldenPage(
          tester,
          BlocProvider<AuthBloc>(
            create: (_) => AuthBloc(apiService: _OfflineAuthApiService()),
            child: withMerzoxGoldenDeviceInsets(
              LoginPage(
                onAuthenticated: () {},
                onBrowseAsGuest: () {},
                onSignupRequested: () {},
                onForgotPasswordRequested: () {},
                businessMode: false,
              ),
            ),
          ),
        );

        await expectMerzoxSeedGolden('login_idle_ar_375x812.png');
      });

      // -- 4. Signup, idle customer state ---------------------------------
      testWidgets('signup renders its Arabic idle-state baseline', (
        WidgetTester tester,
      ) async {
        await pumpMerzoxGoldenPage(
          tester,
          BlocProvider<AuthBloc>(
            create: (_) => AuthBloc(apiService: _OfflineAuthApiService()),
            child: withMerzoxGoldenDeviceInsets(
              SignupPage(onSignupCreated: () {}, onLoginRequested: () {}),
            ),
          ),
        );

        // The seed is the untouched customer form: no typing, validation,
        // submission, navigation or network request is part of this capture.
        expect(find.text('إنشاء حساب'), findsOneWidget);
        expect(find.text('إنشاء الحساب'), findsWidgets);
        expect(find.text('أنثى'), findsOneWidget);
        expect(find.text('ذكر'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);

        await expectMerzoxSeedGolden('signup_idle_ar_375x812.png');
      });

      // -- 5. Store preview, loaded state ---------------------------------
      testWidgets('store preview renders its Arabic loaded-state baseline', (
        WidgetTester tester,
      ) async {
        _useAuthenticatedMerchantSession();

        final BusinessBloc merchantBloc = BusinessBloc(
          apiService: _SeedMerchantApi(),
        );
        _closeOnTearDown(merchantBloc);

        final Future<BusinessState> merchantReady = merchantBloc.stream
            .firstWhere(
              (BusinessState state) => state.status == BusinessStatus.ready,
            );
        merchantBloc.add(const BusinessStarted());
        await merchantReady;

        final BusinessProfileBloc storefrontBloc = BusinessProfileBloc(
          apiService: _SeedStorefrontApi(),
          viewMode: BusinessProfileViewMode.merchantPreview,
        );

        final Future<BusinessProfileState> storefrontReady = storefrontBloc
            .stream
            .firstWhere(
              (BusinessProfileState state) =>
                  state.status == BusinessProfileStatus.ready,
            );
        storefrontBloc.add(const BusinessProfileStarted(_previewBusinessId));
        await storefrontReady;

        // The seed must be the real LOADED preview, not a spinner, an error or
        // an uninitialised screen. Assert that before capturing, so a silent
        // downgrade fails the test instead of producing a misleading PNG.
        expect(storefrontBloc.state.business, isNotNull);
        expect(
          storefrontBloc.state.detailsStatus,
          BusinessProfileSectionStatus.ready,
        );

        await pumpMerzoxGoldenPage(
          tester,
          BlocProvider<BusinessBloc>.value(
            value: merchantBloc,
            // `storefrontBloc` is the production test seam; the page's own
            // `BlocProvider` takes ownership and disposes it.
            child: withMerzoxGoldenDeviceInsets(
              StorePreviewPage(storefrontBloc: storefrontBloc),
            ),
          ),
        );

        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('متجر الياسمين'), findsOneWidget);

        await expectMerzoxSeedGolden('store_preview_loaded_ar_375x812.png');
      });

      // -- 6. Cart, guest state -------------------------------------------
      //
      // `السلة` in the XD corpus is the UNAUTHENTICATED cart: the guest mark,
      // the sign-in prompt, the two account actions and the shell's bottom
      // navigation. `HomeScreen` owns that state through `_CartTab`, so the
      // seed renders the real shell on tab 1 rather than a lifted-out widget.
      testWidgets('cart renders its Arabic guest-state baseline', (
        WidgetTester tester,
      ) async {
        SharedPreferences.setMockInitialValues(<String, Object>{});

        final HomeBloc homeBloc = HomeBloc(
          apiService: _OfflineHomeApiService(),
        );
        _closeOnTearDown(homeBloc);

        // Only the tab selection. `HomeStarted` is deliberately never
        // dispatched: it would begin catalog loading and the location
        // permission flow, neither of which is part of this state.
        final Future<HomeState> cartSelected = homeBloc.stream.firstWhere(
          (HomeState state) => state.selectedTab == 1,
        );
        homeBloc.add(const HomeTabChanged(1));
        await cartSelected;

        expect(homeBloc.state.shouldAskLocationPermission, isFalse);

        await pumpMerzoxGoldenPage(
          tester,
          BlocProvider<HomeBloc>.value(
            value: homeBloc,
            child: withMerzoxGoldenDeviceInsets(
              const HomeScreen(isGuest: true),
            ),
          ),
        );

        // The seed is the guest prompt, not a populated basket: assert the
        // state before capturing so a silent downgrade fails the test rather
        // than producing a misleading PNG.
        expect(find.text('السلة'), findsOneWidget);
        expect(find.text('إنشاء حساب'), findsOneWidget);
        expect(find.text('تسجيل دخول'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);

        await expectMerzoxSeedGolden('cart_guest_ar_375x812.png');
      });

      // -- 7. Order tracking, placed state --------------------------------
      testWidgets('order tracking renders its Arabic placed-state baseline', (
        WidgetTester tester,
      ) async {
        _useAuthenticatedCustomerSession();

        final OrderTrackingBloc trackingBloc = OrderTrackingBloc(
          orderId: _trackedOrderId,
          apiService: _SeedOrderTrackingApi(),
        );
        _closeOnTearDown(trackingBloc);

        final Future<OrderTrackingState> ready = trackingBloc.stream.firstWhere(
          (OrderTrackingState state) =>
              state.status == OrderTrackingStatus.ready,
        );
        trackingBloc.add(const OrderTrackingStarted());
        await ready;

        // The seed must be the real LOADED order, not a spinner or an error.
        expect(trackingBloc.state.order, isNotNull);
        expect(trackingBloc.state.order!.publicId, '222321');

        await pumpMerzoxGoldenPage(
          tester,
          BlocProvider<OrderTrackingBloc>.value(
            value: trackingBloc,
            child: withMerzoxGoldenDeviceInsets(const OrderTrackingPage()),
          ),
        );

        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('222321'), findsOneWidget);

        await expectMerzoxSeedGolden('order_tracking_placed_ar_375x812.png');
      });

      // -- 8. About Us, loaded state with every section collapsed ---------
      testWidgets('about us renders its Arabic loaded-state baseline', (
        WidgetTester tester,
      ) async {
        final AboutUsBloc aboutBloc = AboutUsBloc(
          apiService: _SeedAboutUsApi(),
        );
        _closeOnTearDown(aboutBloc);

        final Future<AboutUsState> ready = aboutBloc.stream.firstWhere(
          (AboutUsState state) => state.status == AboutUsStatus.ready,
        );
        aboutBloc.add(const AboutUsStarted('ar'));
        await ready;

        expect(aboutBloc.state.content, isNotNull);
        expect(aboutBloc.state.expandedSectionKeys, isEmpty);

        await pumpMerzoxGoldenPage(
          tester,
          BlocProvider<AboutUsBloc>.value(
            value: aboutBloc,
            child: withMerzoxGoldenDeviceInsets(const AboutUsPage()),
          ),
        );

        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('آلية العمل'), findsOneWidget);
        expect(find.text('شروط العمل'), findsOneWidget);
        expect(find.text('أحكام العمل'), findsOneWidget);

        await expectMerzoxSeedGolden('about_us_loaded_ar_375x812.png');
      });

      // -- 9. Favorites, products tab -------------------------------------
      testWidgets('favorites renders its Arabic products-tab baseline', (
        WidgetTester tester,
      ) async {
        _useAuthenticatedCustomerSession();

        final FavoritesBloc favoritesBloc = FavoritesBloc(
          apiService: _SeedFavoritesApi(),
        );
        _closeOnTearDown(favoritesBloc);

        // The artboard shows the PRODUCTS tab selected; the bloc opens on
        // businesses, so the seed selects it explicitly.
        final Future<FavoritesState> ready = favoritesBloc.stream.firstWhere(
          (FavoritesState state) =>
              state.status == FavoritesStatus.ready &&
              state.selectedTab == FavoritesTab.products &&
              state.productsLoaded,
        );
        favoritesBloc.add(const FavoritesStarted());
        favoritesBloc.add(const FavoritesTabChanged(FavoritesTab.products));
        await ready;

        expect(favoritesBloc.state.products, hasLength(4));

        await pumpMerzoxGoldenPage(
          tester,
          BlocProvider<FavoritesBloc>.value(
            value: favoritesBloc,
            child: withMerzoxGoldenDeviceInsets(const FavoritesPage()),
          ),
        );

        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('المفضلة'), findsOneWidget);

        await expectMerzoxSeedGolden('favorites_products_ar_375x812.png');
      });

      // -- 10. Store details, the CUSTOMER view of the same storefront -----
      //
      // `تفاصيل المتجر` and `معاينة المتجر` are the same page in its two view
      // modes, which is exactly the distinction `BusinessProfileViewMode`
      // draws. The customer artboard carries the notification bell, the chat
      // affordance and the shell's bottom navigation; the merchant preview
      // carries a close control and none of the three. Seeding both keeps that
      // difference measured rather than assumed.
      testWidgets('store details renders its Arabic customer-view baseline', (
        WidgetTester tester,
      ) async {
        SharedPreferences.setMockInitialValues(<String, Object>{});

        final BusinessProfileBloc storefrontBloc = BusinessProfileBloc(
          apiService: _SeedStorefrontApi(),
          viewMode: BusinessProfileViewMode.customer,
        );

        final Future<BusinessProfileState> ready = storefrontBloc.stream
            .firstWhere(
              (BusinessProfileState state) =>
                  state.status == BusinessProfileStatus.ready,
            );
        storefrontBloc.add(const BusinessProfileStarted(_previewBusinessId));
        await ready;

        expect(storefrontBloc.state.business, isNotNull);
        expect(
          storefrontBloc.state.detailsStatus,
          BusinessProfileSectionStatus.ready,
        );

        await pumpMerzoxGoldenPage(
          tester,
          withMerzoxGoldenDeviceInsets(
            BusinessProfilePage(
              // The customer route arrives with the catalog's identity and the
              // page fills the rest from the public detail payload.
              business: const HomeBusiness(
                id: _previewBusinessId,
                name: '',
                category: '',
                address: '',
                products: <String>[],
                rating: 0,
                colorValue: 0xffdeeef8,
              ),
              onNavChanged: (_) {},
              // The page's own `BlocProvider` takes ownership and disposes it.
              bloc: storefrontBloc,
            ),
          ),
        );

        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('متجر الياسمين'), findsOneWidget);

        await expectMerzoxSeedGolden('store_details_customer_ar_375x812.png');
      });

      // -- 11/12. The storefront's other two tabs -------------------------
      //
      // Both artboards are taller than the viewport because the corpus draws
      // below-the-fold content inline. The mapping crops them to the first
      // 812 rows, which is the state a first-frame golden can be compared
      // against; `below_fold_row_count` records what was left unmeasured.
      Future<BusinessProfileBloc> openStorefrontTab(int index) async {
        final BusinessProfileBloc bloc = BusinessProfileBloc(
          apiService: _SeedStorefrontTabsApi(),
          reviewEligibilityGateway: const _SeedEligibleReviewer(),
          viewMode: BusinessProfileViewMode.customer,
        );

        final Future<BusinessProfileState> ready = bloc.stream.firstWhere(
          (BusinessProfileState state) =>
              state.status == BusinessProfileStatus.ready,
        );
        bloc.add(const BusinessProfileStarted(_previewBusinessId));
        await ready;

        // Opening a tab STARTS its section load, so waiting on the tab index
        // alone would capture the spinner. Wait for the section itself.
        final Future<BusinessProfileState> loaded = bloc.stream.firstWhere(
          (BusinessProfileState state) =>
              state.mainTabIndex == index &&
              (index == 1 ? state.productsStatus : state.reviewsStatus) ==
                  BusinessProfileSectionStatus.ready,
        );
        bloc.add(BusinessProfileMainTabChanged(index));
        await loaded;

        return bloc;
      }

      Widget storefrontPage(BusinessProfileBloc bloc) {
        return withMerzoxGoldenDeviceInsets(
          BusinessProfilePage(
            business: const HomeBusiness(
              id: _previewBusinessId,
              name: '',
              category: '',
              address: '',
              products: <String>[],
              rating: 0,
              colorValue: 0xffdeeef8,
            ),
            onNavChanged: (_) {},
            bloc: bloc,
          ),
        );
      }

      testWidgets('storefront products tab renders its Arabic baseline', (
        WidgetTester tester,
      ) async {
        SharedPreferences.setMockInitialValues(<String, Object>{});

        final BusinessProfileBloc bloc = await openStorefrontTab(1);
        expect(bloc.state.products, hasLength(4));

        await pumpMerzoxGoldenPage(tester, storefrontPage(bloc));

        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('أساس فت مي'), findsWidgets);

        await expectMerzoxSeedGolden('storefront_products_ar_375x812.png');
      });

      testWidgets('storefront reviews tab renders its Arabic baseline', (
        WidgetTester tester,
      ) async {
        // The artboard draws the composer, which only a signed-in eligible
        // customer sees.
        _useAuthenticatedCustomerSession();

        final BusinessProfileBloc bloc = await openStorefrontTab(2);
        expect(bloc.state.reviews, hasLength(3));
        expect(
          bloc.state.reviewEligibilityStatus,
          ReviewEligibilityStatus.eligible,
        );

        await pumpMerzoxGoldenPage(tester, storefrontPage(bloc));

        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('ياسمين خالد'), findsWidgets);

        await expectMerzoxSeedGolden('storefront_reviews_ar_375x812.png');
      });

      // -- 13. Product details, description tab ---------------------------
      testWidgets('product details renders its Arabic description baseline', (
        WidgetTester tester,
      ) async {
        SharedPreferences.setMockInitialValues(<String, Object>{});

        final ProductDetailsBloc bloc = ProductDetailsBloc(
          apiService: _SeedProductApi(),
        );

        final BusinessProductApiModel seedProduct =
            BusinessProductApiModel.fromJson(_seedDetailedProduct());

        final Future<ProductDetailsState> ready = bloc.stream.firstWhere(
          (ProductDetailsState state) =>
              state.detailsStatus == ProductDetailsSectionStatus.ready,
        );
        bloc.add(
          ProductDetailsStarted(
            businessId: _previewBusinessId,
            initialProduct: seedProduct,
          ),
        );
        await ready;

        // The seed is the untouched description tab: quantity 1, no variant
        // chosen, nothing added to a cart.
        expect(bloc.state.selectedTabIndex, 0);
        expect(bloc.state.quantity, 1);

        await pumpMerzoxGoldenPage(
          tester,
          withMerzoxGoldenDeviceInsets(
            ProductDetailsPage(
              business: const HomeBusiness(
                id: _previewBusinessId,
                name: 'متجر الياسمين',
                category: '',
                address: 'رام الله، دوار المنارة',
                products: <String>[],
                rating: 0,
                colorValue: 0xffdeeef8,
              ),
              product: seedProduct,
              bloc: bloc,
            ),
          ),
        );

        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('أساس فت مي'), findsWidgets);

        await expectMerzoxSeedGolden('product_details_ar_375x812.png');
      });

      // -- 14/15. The two checkout steps ----------------------------------
      //
      // A basket with one line, an authenticated customer and a saved
      // delivery address: the preconditions both artboards assume.
      Future<CartBloc> loadedCart({ApiService? api}) async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          AuthBloc.sessionKey: true,
          AuthBloc.tokenKey: 'seed-golden-token',
          AuthBloc.userTypeKey: 'customer',
          AuthBloc.nameKey: 'ياسمين عماد',
          AuthBloc.addressKey: 'أريحا',
          CartStorageKeys.items: <String>[
            // The stored line is JSON, and the bloc REVALIDATES it against the
            // public product contract on load, so the seed serves that product
            // too rather than letting the line fall back to its snapshot.
            '{"businessId":"64b000000000000000000001",'
                '"productId":"64c000000000000000000099",'
                '"variantId":"64d000000000000000000100",'
                '"variantLabel":"01",'
                '"name":"أساس فت مي","price":5.5,"quantity":1,'
                '"imageUrl":""}',
          ],
        });

        final CartBloc bloc = CartBloc(apiService: api ?? _SeedDeliveryApi());
        _closeOnTearDown(bloc);

        final Future<CartState> ready = bloc.stream.firstWhere(
          (CartState state) => state.status == CartStatus.ready,
        );
        bloc.add(const CartStarted());
        await ready;

        return bloc;
      }

      testWidgets('checkout buyer step renders its Arabic baseline', (
        WidgetTester tester,
      ) async {
        final CartBloc cart = await loadedCart();

        await pumpMerzoxGoldenPage(
          tester,
          BlocProvider<CartBloc>.value(
            value: cart,
            child: withMerzoxGoldenDeviceInsets(
              CheckoutPage(apiService: _SeedDeliveryApi()),
            ),
          ),
        );

        expect(find.text('تفاصيل المشتري'), findsOneWidget);
        expect(find.text('أضف عنوان جديد'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);

        await expectMerzoxSeedGolden('checkout_buyer_ar_375x812.png');
      });

      testWidgets('checkout payment step renders its Arabic baseline', (
        WidgetTester tester,
      ) async {
        final CartBloc cart = await loadedCart();

        await pumpMerzoxGoldenPage(
          tester,
          BlocProvider<CartBloc>.value(
            value: cart,
            child: withMerzoxGoldenDeviceInsets(
              CheckoutPage(apiService: _SeedDeliveryApi()),
            ),
          ),
        );

        // Step two is reached the way a customer reaches it.
        await tester.tap(find.text('متابعة'));
        await settleMerzoxGoldenFrames(tester);

        expect(find.text('الدفع'), findsWidgets);
        expect(find.text('الدفع عند الاستلام'), findsOneWidget);
        expect(find.text('تأكيد الطلب'), findsOneWidget);
        // `تفاصيل المتجر – 26` has no cancellation rule on it: that belongs to
        // the button, and only once it has been reached for.
        expect(
          find.text('يمكن إلغاء الطلب خلال 24 ساعة من تأكيده'),
          findsNothing,
        );

        await expectMerzoxSeedGolden('checkout_payment_ar_375x812.png');
      });

      testWidgets('the checkout cancelling state renders its Arabic baseline', (
        WidgetTester tester,
      ) async {
        final CartBloc cart = await loadedCart();

        await pumpMerzoxGoldenPage(
          tester,
          BlocProvider<CartBloc>.value(
            value: cart,
            child: withMerzoxGoldenDeviceInsets(
              CheckoutPage(apiService: _SeedDeliveryApi()),
            ),
          ),
        );

        await tester.tap(find.text('متابعة'));
        await settleMerzoxGoldenFrames(tester);

        // Reached for cancel, then said no: the button keeps the emphasis and
        // the window stays on screen, which is the state between `– 26` and
        // `– 30`.
        await tester.tap(find.text('إلغاء الطلب'));
        await settleMerzoxGoldenFrames(tester);
        await tester.tap(find.text('لا'));
        await settleMerzoxGoldenFrames(tester);

        expect(find.text('هل أنت متأكد من عملية إلغاء الطلب؟'), findsNothing);
        expect(
          find.text('يمكن إلغاء الطلب خلال 24 ساعة من تأكيده'),
          findsOneWidget,
        );

        await expectMerzoxSeedGolden('checkout_cancelling_ar_375x812.png');
      });

      testWidgets('the checkout cancel question renders its Arabic baseline', (
        WidgetTester tester,
      ) async {
        final CartBloc cart = await loadedCart();

        await pumpMerzoxGoldenPage(
          tester,
          BlocProvider<CartBloc>.value(
            value: cart,
            child: withMerzoxGoldenDeviceInsets(
              CheckoutPage(apiService: _SeedDeliveryApi()),
            ),
          ),
        );

        await tester.tap(find.text('متابعة'));
        await settleMerzoxGoldenFrames(tester);

        await tester.tap(find.text('إلغاء الطلب'));
        await settleMerzoxGoldenFrames(tester);

        expect(find.text('هل أنت متأكد من عملية إلغاء الطلب؟'), findsOneWidget);
        expect(find.text('نعم'), findsOneWidget);
        expect(find.text('لا'), findsOneWidget);

        await expectMerzoxSeedGolden('checkout_cancel_ar_375x812.png');
      });

      testWidgets('checkout confirmation renders its Arabic baseline', (
        WidgetTester tester,
      ) async {
        final CartBloc cart = await loadedCart(api: _SeedPlacingApi());

        await pumpMerzoxGoldenPage(
          tester,
          BlocProvider<CartBloc>.value(
            value: cart,
            child: withMerzoxGoldenDeviceInsets(
              CheckoutPage(apiService: _SeedPlacingApi()),
            ),
          ),
        );

        // Reached the way a customer reaches it, not by setting the step.
        await tester.tap(find.text('متابعة'));
        await settleMerzoxGoldenFrames(tester);
        await tester.tap(find.text('تأكيد الطلب'));
        await settleMerzoxGoldenFrames(tester);

        expect(find.text('تم تأكيد الطلبية بنجاح'), findsOneWidget);
        expect(find.text('رقم الطلب: #222321'), findsOneWidget);

        await expectMerzoxSeedGolden('checkout_done_ar_375x812.png');
      });

      // -- 25/26/27. Search ------------------------------------------------
      //
      // `البحث` before a query, then its two result tabs.
      Future<SearchBloc> search({String query = '', int tab = 0}) async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          SearchBloc.historyKey: <String>[
            'حذاء حريمي',
            'متجر جوميا',
            'حذاء حريمي',
            'حذاء حريمي',
            'حذاء حريمي',
          ],
        });

        final SearchBloc bloc = SearchBloc(apiService: _SeedSearchApi());
        _closeOnTearDown(bloc);

        final Future<SearchState> ready = bloc.stream.firstWhere(
          (SearchState state) => state.status != SearchStatus.initial,
        );
        bloc.add(const SearchStarted());
        await ready;

        if (query.isEmpty) return bloc;

        final Future<SearchState> results = bloc.stream.firstWhere(
          (SearchState state) =>
              state.status == SearchStatus.success ||
              state.status == SearchStatus.failure,
        );
        bloc.add(SearchSubmitted(query));
        final SearchState settled = await results;
        expect(
          settled.status,
          SearchStatus.success,
          reason: 'search fixture rejected: ${settled.errorMessage}',
        );

        if (tab != 0) {
          bloc.add(SearchTabChanged(tab));
          await bloc.stream.firstWhere(
            (SearchState state) => state.selectedTab == tab,
          );
        }

        return bloc;
      }

      Future<void> pumpSearch(WidgetTester tester, SearchBloc bloc) =>
          pumpMerzoxGoldenPage(
            tester,
            BlocProvider<SearchBloc>.value(
              value: bloc,
              child: withMerzoxGoldenDeviceInsets(const SearchPage()),
            ),
          );

      testWidgets('search history renders its Arabic baseline', (
        WidgetTester tester,
      ) async {
        final SearchBloc bloc = await search();
        expect(bloc.state.history, hasLength(5));

        await pumpSearch(tester, bloc);

        expect(find.text('حذاء حريمي'), findsWidgets);
        await expectMerzoxSeedGolden('search_history_ar_375x812.png');
      });

      testWidgets('search product results render their Arabic baseline', (
        WidgetTester tester,
      ) async {
        final SearchBloc bloc = await search(query: 'بوت');
        expect(bloc.state.products, hasLength(6));

        await pumpSearch(tester, bloc);

        await expectMerzoxSeedGolden('search_products_ar_375x812.png');
      });

      testWidgets('search store results render their Arabic baseline', (
        WidgetTester tester,
      ) async {
        final SearchBloc bloc = await search(query: 'حرير', tab: 1);
        expect(bloc.state.businesses, hasLength(6));

        await pumpSearch(tester, bloc);

        await expectMerzoxSeedGolden('search_stores_ar_375x812.png');
      });

      // -- 28/29/30. The profile family ------------------------------------
      //
      // Two customer menus (guest and signed in), the merchant's, and the
      // form behind all of them.
      testWidgets('customer profile renders its Arabic guest baseline', (
        WidgetTester tester,
      ) async {
        SharedPreferences.setMockInitialValues(const <String, Object>{});

        final HomeBloc bloc = HomeBloc(
          apiService: _SeedHomeApi(),
          deviceLocationService: _SeedNoDeviceLocation(),
          locationPermissionService: _SeedDeniedLocation(),
        );
        _closeOnTearDown(bloc);

        final Future<HomeState> ready = bloc.stream.firstWhere(
          (HomeState state) =>
              state.newBusinessesStatus == HomeSectionStatus.ready,
        );
        bloc.add(const HomeStarted(isGuest: true));
        await ready;
        bloc.add(const HomeTabChanged(4));
        await bloc.stream.firstWhere(
          (HomeState state) => state.selectedTab == 4,
        );

        await pumpMerzoxGoldenPage(
          tester,
          BlocProvider<HomeBloc>.value(
            value: bloc,
            child: withMerzoxGoldenDeviceInsets(
              const HomeScreen(isGuest: true),
            ),
          ),
        );

        expect(find.byType(CircularProgressIndicator), findsNothing);

        await expectMerzoxSeedGolden('profile_guest_ar_375x812.png');
      });

      testWidgets('merchant profile renders its Arabic baseline', (
        WidgetTester tester,
      ) async {
        _useAuthenticatedMerchantSession();

        final BusinessBloc bloc = BusinessBloc(apiService: _SeedMerchantApi());
        _closeOnTearDown(bloc);

        final Future<BusinessState> ready = bloc.stream.firstWhere(
          (BusinessState state) => state.status == BusinessStatus.ready,
        );
        bloc.add(const BusinessStarted());
        await ready;
        bloc.add(const BusinessTabChanged(4));
        await bloc.stream.firstWhere(
          (BusinessState state) => state.selectedTab == 4,
        );

        await pumpMerzoxGoldenPage(
          tester,
          BlocProvider<BusinessBloc>.value(
            value: bloc,
            child: withMerzoxGoldenDeviceInsets(
              BusinessShellPage(
                onLoggedOut: () {},
                notificationPreferenceGateway: _SeedPreferenceGateway(),
                notificationPreferenceSessionReader: () async =>
                    const AuthSessionSnapshot(
                      type: AuthSessionType.business,
                      token: 'seed-golden-token',
                    ),
              ),
            ),
          ),
        );

        expect(find.byType(CircularProgressIndicator), findsNothing);

        await expectMerzoxSeedGolden('profile_merchant_ar_375x812.png');
      });

      testWidgets('profile form renders its Arabic baseline', (
        WidgetTester tester,
      ) async {
        _useAuthenticatedCustomerSession();

        final ProfileEditBloc bloc = ProfileEditBloc(
          apiService: _SeedProfileApi(),
        );
        _closeOnTearDown(bloc);

        final Future<ProfileEditState> ready = bloc.stream.firstWhere(
          (ProfileEditState state) =>
              state.status != ProfileEditStatus.initial &&
              state.status != ProfileEditStatus.loading,
        );
        bloc.add(const ProfileEditStarted());
        final ProfileEditState settled = await ready;
        expect(
          settled.status,
          ProfileEditStatus.ready,
          reason: 'profile fixture rejected: ${settled.errorMessage}',
        );

        await pumpMerzoxGoldenPage(
          tester,
          BlocProvider<ProfileEditBloc>.value(
            value: bloc,
            child: withMerzoxGoldenDeviceInsets(const ProfileEditPage()),
          ),
        );

        await expectMerzoxSeedGolden('profile_form_ar_375x812.png');
      });

      testWidgets('the empty profile form renders its Arabic baseline', (
        WidgetTester tester,
      ) async {
        _useAuthenticatedCustomerSession();

        final ProfileEditBloc bloc = ProfileEditBloc(
          apiService: _SeedProfileApi(filled: false),
        );
        _closeOnTearDown(bloc);

        final Future<ProfileEditState> ready = bloc.stream.firstWhere(
          (ProfileEditState state) =>
              state.status != ProfileEditStatus.initial &&
              state.status != ProfileEditStatus.loading,
        );
        bloc.add(const ProfileEditStarted());
        final ProfileEditState settled = await ready;
        expect(
          settled.status,
          ProfileEditStatus.ready,
          reason: 'profile fixture rejected: ${settled.errorMessage}',
        );

        await pumpMerzoxGoldenPage(
          tester,
          BlocProvider<ProfileEditBloc>.value(
            value: bloc,
            child: withMerzoxGoldenDeviceInsets(const ProfileEditPage()),
          ),
        );

        // Nothing typed yet: every field is showing what it wants.
        expect(find.text('ياسمين خالد'), findsNothing);

        await expectMerzoxSeedGolden('profile_form_empty_ar_375x812.png');
      });

      // -- 31/47/48/49. Store settings, one section at a time --------------
      //
      // One screen with four collapsible sections, and four boards that are
      // that screen with a different one open. Opening a section is what makes
      // them four surfaces rather than one, so each seed opens its own.
      Future<void> pumpStoreSettings(WidgetTester tester) async {
        _useAuthenticatedMerchantSession();

        final BusinessBloc bloc = BusinessBloc(apiService: _SeedMerchantApi());
        _closeOnTearDown(bloc);

        final Future<BusinessState> ready = bloc.stream.firstWhere(
          (BusinessState state) => state.status == BusinessStatus.ready,
        );
        bloc.add(const BusinessStarted());
        await ready;

        await pumpMerzoxGoldenPage(
          tester,
          BlocProvider<BusinessBloc>.value(
            value: bloc,
            child: withMerzoxGoldenDeviceInsets(
              StoreSettingsPage(business: bloc.state.business!),
            ),
          ),
        );
      }

      testWidgets('store settings renders its Arabic baseline', (
        WidgetTester tester,
      ) async {
        await pumpStoreSettings(tester);

        expect(find.text('شعار المتجر'), findsOneWidget);
        expect(find.text('وصف المتجر'), findsOneWidget);

        await expectMerzoxSeedGolden('store_settings_ar_375x812.png');
      });

      testWidgets('store settings renders its Arabic collapsed baseline', (
        WidgetTester tester,
      ) async {
        await pumpStoreSettings(tester);

        // Tapping the open section closes it, which is the fifth board: the
        // menu the four editors hang off.
        await tester.tap(find.text('إعدادات المتجر').last);
        await settleMerzoxGoldenFrames(tester);

        expect(find.text('اسم المتجر بالعربية أو الإنجليزية'), findsNothing);

        await expectMerzoxSeedGolden('store_settings_closed_ar_375x812.png');
      });

      testWidgets('store settings logo section renders its Arabic baseline', (
        WidgetTester tester,
      ) async {
        await pumpStoreSettings(tester);

        await tester.tap(find.text('شعار المتجر'));
        await settleMerzoxGoldenFrames(tester);

        // Only one section is ever open: the store name goes away as the logo
        // arrives.
        expect(find.text('قم بإرفاق شعار المتجر'), findsOneWidget);

        await expectMerzoxSeedGolden('store_settings_logo_ar_375x812.png');
      });

      testWidgets('store settings description renders its Arabic baseline', (
        WidgetTester tester,
      ) async {
        await pumpStoreSettings(tester);

        await tester.tap(find.text('وصف المتجر'));
        await settleMerzoxGoldenFrames(tester);

        expect(find.text('أضف عنوان المتجر'), findsOneWidget);
        expect(find.text('ما نوع المنتجات التي تبيعها'), findsOneWidget);

        await expectMerzoxSeedGolden(
          'store_settings_description_ar_375x812.png',
        );
      });

      testWidgets('store settings social renders its Arabic baseline', (
        WidgetTester tester,
      ) async {
        await pumpStoreSettings(tester);

        await tester.tap(find.text('وسائل التواصل الاجتماعي'));
        await settleMerzoxGoldenFrames(tester);

        expect(
          find.text('قم بإدخال يوزر الانستغرام او الرابط'),
          findsOneWidget,
        );
        expect(find.text('قم بإدخال رقم الواتس مع المقدمة'), findsOneWidget);

        await expectMerzoxSeedGolden('store_settings_social_ar_375x812.png');
      });

      // -- 16. Merchant dashboard -----------------------------------------
      //
      // `الرئيسية – 2` is the MERCHANT home, not the customer one: it draws
      // the sales/orders/visits figures and the recent-order table. The two
      // customer `الرئيسية` artboards carry an unsupported backdrop blur and
      // are refused by the comparator, so they are not seeded here.
      testWidgets('merchant dashboard renders its Arabic baseline', (
        WidgetTester tester,
      ) async {
        _useAuthenticatedMerchantSession();

        final BusinessBloc merchantBloc = BusinessBloc(
          apiService: _SeedDashboardApi(),
        );
        _closeOnTearDown(merchantBloc);

        final Future<BusinessState> ready = merchantBloc.stream.firstWhere(
          (BusinessState state) => state.status == BusinessStatus.ready,
        );
        merchantBloc.add(const BusinessStarted());
        await ready;

        expect(merchantBloc.state.dashboard, isNotNull);
        expect(merchantBloc.state.dashboard!.recentOrders, hasLength(5));

        await pumpMerzoxGoldenPage(
          tester,
          BlocProvider<BusinessBloc>.value(
            value: merchantBloc,
            child: withMerzoxGoldenDeviceInsets(
              BusinessShellPage(onLoggedOut: () {}),
            ),
          ),
        );

        expect(find.byType(CircularProgressIndicator), findsNothing);

        await expectMerzoxSeedGolden('merchant_dashboard_ar_375x812.png');
      });

      // -- 17/18. The two merchant browse tabs ----------------------------
      //
      // `الرئيسية – 9` and `الرئيسية – 10` are the orders and products tabs of
      // the same shell, so both seeds differ only in which tab is selected and
      // which API answers.
      Future<BusinessBloc> merchantShell(ApiService api, int tab) async {
        _useAuthenticatedMerchantSession();

        final BusinessBloc bloc = BusinessBloc(apiService: api);
        _closeOnTearDown(bloc);

        final Future<BusinessState> ready = bloc.stream.firstWhere(
          (BusinessState state) => state.status == BusinessStatus.ready,
        );
        bloc.add(const BusinessStarted());
        await ready;
        bloc.add(BusinessTabChanged(tab));
        await bloc.stream.firstWhere(
          (BusinessState state) => state.selectedTab == tab,
        );

        return bloc;
      }

      testWidgets('merchant orders tab renders its Arabic baseline', (
        WidgetTester tester,
      ) async {
        final BusinessBloc bloc = await merchantShell(
          _SeedMerchantOrdersApi(),
          1,
        );

        expect(bloc.state.orders, hasLength(10));

        await pumpMerzoxGoldenPage(
          tester,
          BlocProvider<BusinessBloc>.value(
            value: bloc,
            child: withMerzoxGoldenDeviceInsets(
              BusinessShellPage(onLoggedOut: () {}),
            ),
          ),
        );

        expect(find.text('جميع الطلبات'), findsOneWidget);
        expect(find.text('حالة الطلب'), findsWidgets);
        expect(find.byType(CircularProgressIndicator), findsNothing);

        await expectMerzoxSeedGolden('merchant_orders_ar_375x812.png');
      });

      testWidgets('merchant products tab renders its Arabic baseline', (
        WidgetTester tester,
      ) async {
        final BusinessBloc bloc = await merchantShell(
          _SeedMerchantProductsApi(),
          3,
        );

        expect(bloc.state.products, hasLength(4));

        await pumpMerzoxGoldenPage(
          tester,
          BlocProvider<BusinessBloc>.value(
            value: bloc,
            child: withMerzoxGoldenDeviceInsets(
              BusinessShellPage(onLoggedOut: () {}),
            ),
          ),
        );

        expect(find.text('جميع المنتجات'), findsOneWidget);
        expect(find.text('إضافة منتج جديد'), findsOneWidget);
        expect(find.text('منشور'), findsNWidgets(4));
        expect(find.byType(CircularProgressIndicator), findsNothing);

        await expectMerzoxSeedGolden('merchant_products_ar_375x812.png');
      });

      // -- 19/20. The customer home, guest and signed in -------------------
      //
      // `الرئيسية` and `الرئيسية – 1` differ only in their header, so the two
      // seeds share an API and differ only in the session behind them. Both
      // artboards are 1716 tall: the corpus draws what scrolling reveals as
      // one tall board, and the comparator crops to the 812 a device shows.
      Future<HomeBloc> customerHome({required bool isGuest}) async {
        final HomeBloc bloc = HomeBloc(
          apiService: _SeedHomeApi(),
          deviceLocationService: _SeedNoDeviceLocation(),
          locationPermissionService: _SeedDeniedLocation(),
        );
        _closeOnTearDown(bloc);

        final Future<HomeState> ready = bloc.stream.firstWhere(
          (HomeState state) =>
              state.newBusinessesStatus == HomeSectionStatus.ready &&
              state.discountedBusinessesStatus == HomeSectionStatus.ready,
        );
        bloc.add(HomeStarted(isGuest: isGuest));
        await ready;

        return bloc;
      }

      testWidgets('the stores tab renders its Arabic baseline', (
        WidgetTester tester,
      ) async {
        // `المتاجر` is not a tall screen: it is a grid of every registered
        // shop, and the 1492 the board is drawn at is what scrolling reveals.
        SharedPreferences.setMockInitialValues(<String, Object>{
          AuthBloc.sessionKey: true,
          AuthBloc.tokenKey: 'seed-golden-token',
          AuthBloc.userTypeKey: 'customer',
          AuthBloc.nameKey: 'ياسمين خالد',
        });

        final HomeBloc bloc = await customerHome(isGuest: false);

        // The stores grid is tab two, which is the raised button in the bar.
        bloc.add(const HomeTabChanged(2));
        await bloc.stream.firstWhere(
          (HomeState state) => state.selectedTab == 2,
        );

        expect(bloc.state.allBusinesses, hasLength(8));

        await pumpMerzoxGoldenPage(
          tester,
          BlocProvider<HomeBloc>.value(
            value: bloc,
            child: withMerzoxGoldenDeviceInsets(
              const HomeScreen(isGuest: false),
            ),
          ),
        );

        expect(find.text('ابحث عن أي متجر تريده'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);

        await expectMerzoxSeedGolden('stores_ar_375x812.png');
      });

      testWidgets('customer home renders its Arabic guest baseline', (
        WidgetTester tester,
      ) async {
        SharedPreferences.setMockInitialValues(const <String, Object>{});

        final HomeBloc bloc = await customerHome(isGuest: true);

        await pumpMerzoxGoldenPage(
          tester,
          BlocProvider<HomeBloc>.value(
            value: bloc,
            child: withMerzoxGoldenDeviceInsets(
              const HomeScreen(isGuest: true),
            ),
          ),
        );

        expect(find.text('اشتري الآن'), findsWidgets);
        expect(find.byType(CircularProgressIndicator), findsNothing);

        await expectMerzoxSeedGolden('home_guest_ar_375x812.png');
      });

      testWidgets('customer home renders its Arabic signed-in baseline', (
        WidgetTester tester,
      ) async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          AuthBloc.sessionKey: true,
          AuthBloc.tokenKey: 'seed-golden-token',
          AuthBloc.userTypeKey: 'customer',
          AuthBloc.nameKey: 'ياسمين خالد',
        });

        final HomeBloc bloc = await customerHome(isGuest: false);

        await pumpMerzoxGoldenPage(
          tester,
          BlocProvider<HomeBloc>.value(
            value: bloc,
            child: withMerzoxGoldenDeviceInsets(
              const HomeScreen(isGuest: false),
            ),
          ),
        );

        expect(find.byType(CircularProgressIndicator), findsNothing);

        await expectMerzoxSeedGolden('home_customer_ar_375x812.png');
      });

      // -- 21/22/23. The messaging family ----------------------------------
      //
      // `الرسائل` is the corpus's largest untouched family: an inbox with
      // all/unread tabs, its empty state, and the notifications list drawn as
      // `الرسائل – 5`.
      Future<MessagesBloc> inbox(ApiService api) async {
        _useAuthenticatedCustomerSession();

        final MessagesBloc bloc = MessagesBloc(apiService: api);
        _closeOnTearDown(bloc);

        final Future<MessagesState> ready = bloc.stream.firstWhere(
          (MessagesState state) => state.status == MessagesStatus.ready,
        );
        bloc.add(const MessagesStarted());
        await ready;

        return bloc;
      }

      testWidgets('messages inbox renders its Arabic baseline', (
        WidgetTester tester,
      ) async {
        final MessagesBloc bloc = await inbox(_SeedMessagesApi());
        expect(bloc.state.conversations, hasLength(4));

        await pumpMerzoxGoldenPage(
          tester,
          BlocProvider<MessagesBloc>.value(
            value: bloc,
            child: withMerzoxGoldenDeviceInsets(
              Scaffold(
                backgroundColor: Colors.white,
                body: SafeArea(
                  child: Builder(
                    builder: (BuildContext context) =>
                        MessagesInboxView(title: 'messages.title'.tr()),
                  ),
                ),
              ),
            ),
          ),
        );

        expect(find.text('متجر الياسمين'), findsWidgets);
        expect(find.byType(CircularProgressIndicator), findsNothing);

        await expectMerzoxSeedGolden('messages_inbox_ar_375x812.png');
      });

      testWidgets('empty messages inbox renders its Arabic baseline', (
        WidgetTester tester,
      ) async {
        final MessagesBloc bloc = await inbox(_SeedEmptyMessagesApi());
        expect(bloc.state.conversations, isEmpty);

        await pumpMerzoxGoldenPage(
          tester,
          BlocProvider<MessagesBloc>.value(
            value: bloc,
            child: withMerzoxGoldenDeviceInsets(
              Scaffold(
                backgroundColor: Colors.white,
                body: SafeArea(
                  child: Builder(
                    builder: (BuildContext context) =>
                        MessagesInboxView(title: 'messages.title'.tr()),
                  ),
                ),
              ),
            ),
          ),
        );

        await expectMerzoxSeedGolden('messages_empty_ar_375x812.png');
      });

      testWidgets('notifications list renders its Arabic baseline', (
        WidgetTester tester,
      ) async {
        _useAuthenticatedCustomerSession();

        final NotificationsBloc bloc = NotificationsBloc(
          apiService: _SeedNotificationsApi(),
        );
        _closeOnTearDown(bloc);

        final Future<NotificationsState> ready = bloc.stream.firstWhere(
          (NotificationsState state) =>
              state.status == NotificationsStatus.ready,
        );
        bloc.add(const NotificationsStarted());
        await ready;

        await pumpMerzoxGoldenPage(
          tester,
          BlocProvider<NotificationsBloc>.value(
            value: bloc,
            child: withMerzoxGoldenDeviceInsets(const NotificationsPage()),
          ),
        );

        expect(find.byType(CircularProgressIndicator), findsNothing);

        await expectMerzoxSeedGolden('notifications_ar_375x812.png');
      });

      // -- 32/33/34/35. طلباتي, the customer's own order history ------------
      //
      // Six boards of `تفاصيل المتجر – 21` are one screen with one of three
      // tabs selected, and `السلة – 4` is that screen with nothing in it. The
      // pairs within each tab differ only in whether the label reads
      // `رقم الطلب` or `رقم الطلبية`, so three loaded seeds cover all six.
      Future<OrdersBloc> customerOrders(
        ApiService api,
        OrdersGroup group,
      ) async {
        _useAuthenticatedCustomerSession();

        final OrdersBloc bloc = OrdersBloc(apiService: api);
        _closeOnTearDown(bloc);

        final Future<OrdersState> ready = bloc.stream.firstWhere(
          (OrdersState state) => state.status == OrdersStatus.ready,
        );
        bloc.add(const OrdersStarted());
        await ready;

        if (group != OrdersGroup.current) {
          bloc.add(OrdersGroupChanged(group));
          await bloc.stream.firstWhere(
            (OrdersState state) =>
                state.status == OrdersStatus.ready &&
                state.selectedGroup == group,
          );
        }

        return bloc;
      }

      Future<void> pumpCustomerOrders(
        WidgetTester tester,
        OrdersBloc bloc,
      ) async {
        await pumpMerzoxGoldenPage(
          tester,
          BlocProvider<OrdersBloc>.value(
            value: bloc,
            child: withMerzoxGoldenDeviceInsets(const OrdersPage()),
          ),
        );
      }

      testWidgets('current orders render their Arabic baseline', (
        WidgetTester tester,
      ) async {
        final OrdersBloc bloc = await customerOrders(
          _SeedCustomerOrdersApi(),
          OrdersGroup.current,
        );
        expect(bloc.state.orders, hasLength(3));

        await pumpCustomerOrders(tester, bloc);

        expect(find.text('الحالية'), findsOneWidget);
        expect(find.text('تتبع الطلب'), findsNWidgets(3));
        expect(find.byType(CircularProgressIndicator), findsNothing);

        await expectMerzoxSeedGolden('orders_current_ar_375x812.png');
      });

      testWidgets('completed orders render their Arabic baseline', (
        WidgetTester tester,
      ) async {
        final OrdersBloc bloc = await customerOrders(
          _SeedCustomerOrdersApi(),
          OrdersGroup.completed,
        );
        expect(bloc.state.orders, hasLength(3));

        await pumpCustomerOrders(tester, bloc);

        // The completed card carries the total and nothing to track.
        expect(find.text('تتبع الطلب'), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);

        await expectMerzoxSeedGolden('orders_completed_ar_375x812.png');
      });

      testWidgets('cancelled orders render their Arabic baseline', (
        WidgetTester tester,
      ) async {
        final OrdersBloc bloc = await customerOrders(
          _SeedCustomerOrdersApi(),
          OrdersGroup.cancelled,
        );
        expect(bloc.state.orders, hasLength(2));

        await pumpCustomerOrders(tester, bloc);

        expect(find.textContaining('قمت بشراء شي شبيه'), findsNWidgets(2));
        expect(find.byType(CircularProgressIndicator), findsNothing);

        await expectMerzoxSeedGolden('orders_cancelled_ar_375x812.png');
      });

      testWidgets('empty order history renders its Arabic baseline', (
        WidgetTester tester,
      ) async {
        final OrdersBloc bloc = await customerOrders(
          _SeedNoCustomerOrdersApi(),
          OrdersGroup.current,
        );
        expect(bloc.state.orders, isEmpty);

        await pumpCustomerOrders(tester, bloc);

        // `السلة – 4` has no tab strip: a customer with no orders has no
        // groups to move between.
        expect(find.text('الحالية'), findsNothing);
        expect(find.text('عذراً، لا يوجد لديك طلبات'), findsOneWidget);

        await expectMerzoxSeedGolden('orders_empty_ar_375x812.png');
      });

      // -- 36/37/38. إضافة منتجات, the merchant's product form ---------------
      //
      // Three boards of one screen: the form as it opens, the form with both
      // tick boxes set — which drops the quantity field and raises the
      // discounted price — and the options dialog over it. The two form boards
      // are 1334 tall and the dialog board 1251, all drawn with the shell's
      // own bar across the fold, so the comparator crops each to the 812 a
      // device shows.
      Future<BusinessBloc> productEditorBloc() async {
        _useAuthenticatedMerchantSession();

        final BusinessBloc bloc = BusinessBloc(
          apiService: _SeedMerchantProductsApi(),
        );
        _closeOnTearDown(bloc);

        return bloc;
      }

      Future<void> pumpProductEditor(
        WidgetTester tester,
        BusinessBloc bloc,
      ) async {
        await pumpMerzoxGoldenPage(
          tester,
          BlocProvider<BusinessBloc>.value(
            value: bloc,
            child: withMerzoxGoldenDeviceInsets(
              const MerchantProductEditorPage(),
            ),
          ),
        );
      }

      testWidgets('the product form renders its Arabic baseline', (
        WidgetTester tester,
      ) async {
        await pumpProductEditor(tester, await productEditorBloc());

        expect(find.text('إضافة منتجات'), findsOneWidget);
        expect(find.text('الكمية المتوفرة للمنتج'), findsOneWidget);
        // `الصور` and everything under it is what scrolling reveals, so the
        // list has not built it and this capture does not show it - which is
        // what the artboard's own fold says too.
        expect(find.text('إضافة خيارات أخرى'), findsOneWidget);

        await expectMerzoxSeedGolden('add_product_ar_375x812.png');
      });

      testWidgets('the product form renders its Arabic ticked baseline', (
        WidgetTester tester,
      ) async {
        await pumpProductEditor(tester, await productEditorBloc());

        await tester.tap(find.text('غير محدودة'));
        await tester.tap(find.text('هناك تخفيض'));
        await settleMerzoxGoldenFrames(tester);

        // Unlimited stock takes the quantity field away; a discount puts the
        // price the customer pays in its place.
        expect(find.text('الكمية المتوفرة للمنتج'), findsNothing);
        expect(find.text('السعر بعد التخفيض'), findsOneWidget);

        await expectMerzoxSeedGolden('add_product_ticked_ar_375x812.png');
      });

      testWidgets('the product options dialog renders its Arabic baseline', (
        WidgetTester tester,
      ) async {
        await pumpProductEditor(tester, await productEditorBloc());

        await tester.tap(find.text('إضافة خيارات أخرى'));
        await settleMerzoxGoldenFrames(tester);

        expect(find.text('خيارات إضافية للمنتج'), findsOneWidget);

        // The artboard draws two options already named, which is this dialog
        // after two rounds of type-and-add.
        for (final String label in <String>['الخيار1', 'الخيار2']) {
          await tester.enterText(
            find.widgetWithText(TextField, 'اسم الخيار (اللون ، الحجم)'),
            label,
          );
          // The form's own plus is still in the tree behind the dialog, so
          // the tap has to name the one inside it.
          await tester.tap(
            find.descendant(
              of: find.byType(ProductOptionsDialog),
              matching: find.byIcon(Icons.add),
            ),
          );
          await settleMerzoxGoldenFrames(tester);
        }

        expect(find.text('الخيار1'), findsOneWidget);
        expect(find.text('الخيار2'), findsOneWidget);

        await expectMerzoxSeedGolden('add_product_options_ar_375x812.png');
      });

      // -- 39/40/41/42. تفاصيل الطلب, one order in the merchant's hands -----
      //
      // The screen, its status menu open, the confirmation it raises once the
      // customer has been told, and the invoice `عرض الفاتورة` opens. All four
      // boards are 375x808 and none of them carries a page title.
      Widget orderDetail({String status = 'pending', VoidCallback? onNotify}) {
        return withMerzoxGoldenDeviceInsets(
          MerchantOrderDetailPage(
            order: _seedDetailOrder(status: status),
            businessName: 'متجر الياسمين',
            businessAddress: 'رام الله',
            onStatusSelected: (_) {},
            onNotifyCustomer: onNotify ?? () {},
          ),
        );
      }

      testWidgets('the merchant order screen renders its Arabic baseline', (
        WidgetTester tester,
      ) async {
        await pumpMerzoxGoldenPage(tester, orderDetail());

        expect(find.text('حالة الطلب'), findsOneWidget);
        expect(find.text('جديد'), findsOneWidget);
        expect(find.text('المنتجات (1)'), findsOneWidget);
        expect(find.text('إرسال إشعار'), findsOneWidget);

        await expectMerzoxSeedGolden('merchant_order_detail_ar_375x812.png');
      });

      testWidgets('the merchant order status menu renders its Arabic baseline', (
        WidgetTester tester,
      ) async {
        await pumpMerzoxGoldenPage(tester, orderDetail());

        await tester.tap(find.text('جديد'));
        await settleMerzoxGoldenFrames(tester);

        // The board lists four - قيد التجهيز, في الطريق, تم التسليم, ملغي -
        // which is every status except the one a new order can actually move
        // to next. The server enforces the lifecycle and would answer three of
        // those four with a 409, so the menu offers what is permitted rather
        // than what is drawn.
        for (final String label in <String>['تم الاستلام', 'ملغي']) {
          expect(find.text(label), findsOneWidget);
        }
        expect(find.text('تم التسليم'), findsNothing);

        await expectMerzoxSeedGolden(
          'merchant_order_status_menu_ar_375x812.png',
        );
      });

      testWidgets('the notified merchant order renders its Arabic baseline', (
        WidgetTester tester,
      ) async {
        await pumpMerzoxGoldenPage(tester, orderDetail(status: 'preparing'));

        // The bar is the screen's own confirmation, so the seed raises the one
        // the page builds rather than a copy of it.
        tester
            .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
            .showSnackBar(
              merchantOrderNoticeSnackBar(
                'merchantOrder.notificationSent'.tr(),
              ),
            );
        await settleMerzoxGoldenFrames(tester);

        expect(find.text('قيد التجهيز'), findsOneWidget);
        expect(find.text('تم إرسال إشعار بحالة الطلب'), findsOneWidget);

        await expectMerzoxSeedGolden('merchant_order_notified_ar_375x812.png');
      });

      testWidgets('the merchant invoice renders its Arabic baseline', (
        WidgetTester tester,
      ) async {
        await pumpMerzoxGoldenPage(
          tester,
          withMerzoxGoldenDeviceInsets(
            MerchantOrderInvoicePage(
              order: _seedDetailOrder(status: 'preparing'),
              businessName: 'متجر الياسمين',
              businessAddress: 'رام الله',
            ),
          ),
        );

        expect(find.text('تفاصيل الأسعار'), findsOneWidget);
        expect(
          find.text('شكراً لشرائك من المتجر، نتمنى لك يوماً رائعاً'),
          findsOneWidget,
        );

        await expectMerzoxSeedGolden('merchant_order_invoice_ar_375x812.png');
      });

      // -- 43. تفاصيل المتجر – 34, the product page on its reviews tab -----
      //
      // Three boards of one surface: `– 34`, `– 35` and `– 38`, which differ
      // only in what the header carries. All three are 1141 tall, so the
      // comparator crops to the 812 a device shows.
      testWidgets('product reviews render their Arabic baseline', (
        WidgetTester tester,
      ) async {
        // The board draws the composer, which only a signed-in eligible
        // customer sees.
        _useAuthenticatedCustomerSession();

        final ProductDetailsBloc bloc = ProductDetailsBloc(
          apiService: _SeedProductApi(withReviews: true),
          reviewEligibilityGateway: const _SeedEligibleReviewer(),
        );

        final BusinessProductApiModel seedProduct =
            BusinessProductApiModel.fromJson(_seedDetailedProduct());

        final Future<ProductDetailsState> ready = bloc.stream.firstWhere(
          (ProductDetailsState state) =>
              state.detailsStatus == ProductDetailsSectionStatus.ready &&
              state.reviews.length == 3,
        );
        bloc.add(
          ProductDetailsStarted(
            businessId: _previewBusinessId,
            initialProduct: seedProduct,
          ),
        );
        await ready;

        bloc.add(const ProductDetailsTabChanged(1));
        await bloc.stream.firstWhere(
          (ProductDetailsState state) => state.selectedTabIndex == 1,
        );

        await pumpMerzoxGoldenPage(
          tester,
          withMerzoxGoldenDeviceInsets(
            ProductDetailsPage(
              business: const HomeBusiness(
                id: _previewBusinessId,
                name: 'متجر الياسمين',
                category: '',
                address: 'رام الله، دوار المنارة',
                products: <String>[],
                rating: 0,
                colorValue: 0xffdeeef8,
              ),
              product: seedProduct,
              bloc: bloc,
            ),
          ),
        );

        expect(find.text('كل التقييمات'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);

        await expectMerzoxSeedGolden('product_reviews_ar_375x812.png');
      });

      // -- 44/45/46. The rest of step one ----------------------------------
      //
      // `تفاصيل المتجر – 16` is step one with a saved address to pick, and
      // `– 25`/`– 29`/`– 40` are the same step on the branch where there is
      // none: the form. `– 27` and `– 28` are its two pickers, drawn as sheets
      // over the step they belong to.
      Widget addressForm() {
        return withMerzoxGoldenDeviceInsets(
          AddressFormPage(
            token: 'seed-golden-token',
            apiService: _SeedDeliveryApi(),
          ),
        );
      }

      testWidgets('the address form renders its Arabic baseline', (
        WidgetTester tester,
      ) async {
        _useAuthenticatedCustomerSession();

        await pumpMerzoxGoldenPage(tester, addressForm());

        expect(find.text('تفاصيل المشتري'), findsOneWidget);
        expect(find.text('من فضلك قم باختيار محافظتك'), findsOneWidget);
        expect(find.text('تعيين كعنوان افتراضي'), findsOneWidget);

        await expectMerzoxSeedGolden('checkout_address_form_ar_375x812.png');
      });

      testWidgets('the governorate picker renders its Arabic baseline', (
        WidgetTester tester,
      ) async {
        _useAuthenticatedCustomerSession();

        await pumpMerzoxGoldenPage(tester, addressForm());

        await tester.tap(find.text('من فضلك قم باختيار محافظتك'));
        await settleMerzoxGoldenFrames(tester);

        expect(find.text('أريحا'), findsOneWidget);
        expect(find.text('رام الله والبيرة'), findsOneWidget);

        await expectMerzoxSeedGolden('checkout_governorate_ar_375x812.png');
      });

      testWidgets('the city picker renders its Arabic baseline', (
        WidgetTester tester,
      ) async {
        _useAuthenticatedCustomerSession();

        await pumpMerzoxGoldenPage(tester, addressForm());

        // The city list only ever holds cities of the governorate above it, so
        // the governorate is chosen first - which is also the only way a
        // customer reaches this sheet.
        await tester.tap(find.text('من فضلك قم باختيار محافظتك'));
        await settleMerzoxGoldenFrames(tester);
        await tester.tap(find.text('رام الله والبيرة').last);
        await settleMerzoxGoldenFrames(tester);

        await tester.tap(find.text('من فضلك قم باختيار مدينتك / قريتك'));
        await settleMerzoxGoldenFrames(tester);

        expect(find.text('بيرزيت'), findsOneWidget);

        await expectMerzoxSeedGolden('checkout_city_ar_375x812.png');
      });

      // -- 50/51. The other two onboarding slides ---------------------------
      //
      // `شاشة ترحيبية 1` and `1 – 1` are slides two and three. As with the
      // first, the Flutter wording and the XD wording are not text-identical:
      // these are semantic state matches, not text parity.
      Future<void> pumpOnboardingSlide(WidgetTester tester, int slide) async {
        SharedPreferences.setMockInitialValues(<String, Object>{});

        await pumpMerzoxGoldenPage(
          tester,
          BlocProvider<OnboardingBloc>(
            create: (_) => OnboardingBloc(),
            child: withMerzoxGoldenDeviceInsets(
              OnboardingScreen(onFinished: () {}),
            ),
          ),
        );

        // Advanced the way a customer advances it, so the page view and the
        // bloc move together; a drag moved one without the other.
        for (int step = 0; step < slide; step++) {
          await tester.tap(find.byType(FilledButton));
          await settleMerzoxGoldenFrames(tester);
        }

        // Each slide brings its own illustration, and only the first was
        // precached by the pump.
        await tester.runAsync(() => precacheMerzoxGoldenImages(tester));
        await settleMerzoxGoldenFrames(tester);
      }

      testWidgets('the map onboarding slide renders its Arabic baseline', (
        WidgetTester tester,
      ) async {
        await pumpOnboardingSlide(tester, 1);

        expect(find.text('متاجر على الخريطة'), findsOneWidget);

        await expectMerzoxSeedGolden('onboarding_map_ar_375x812.png');
      });

      testWidgets('the payment onboarding slide renders its Arabic baseline', (
        WidgetTester tester,
      ) async {
        await pumpOnboardingSlide(tester, 2);

        expect(find.text('دفع وطلبات بمرونة'), findsOneWidget);
        // The last slide drops the skip, because there is nothing left to
        // skip.
        expect(find.text('تخطي'), findsNothing);

        await expectMerzoxSeedGolden('onboarding_payment_ar_375x812.png');
      });

      // -- 52/53. The two cart states the guest gate hides ------------------
      //
      // The seeded `cart_guest` is `السلة` — the signed-out gate. `السلة – 1`
      // is a basket with something in it and `– 2` is one with nothing.
      testWidgets('the loaded cart renders its Arabic baseline', (
        WidgetTester tester,
      ) async {
        // `loadedCart` writes the stored line and the session the cart tab's
        // own bloc reads back, so the tab builds the basket the board draws
        // rather than being handed one.
        final CartBloc cart = await loadedCart();
        expect(cart.state.items, hasLength(1));

        final HomeBloc homeBloc = await customerHome(isGuest: false);

        final Future<HomeState> cartSelected = homeBloc.stream.firstWhere(
          (HomeState state) => state.selectedTab == 1,
        );
        homeBloc.add(const HomeTabChanged(1));
        await cartSelected;

        await pumpMerzoxGoldenPage(
          tester,
          BlocProvider<HomeBloc>.value(
            value: homeBloc,
            child: withMerzoxGoldenDeviceInsets(
              HomeScreen(isGuest: false, apiService: _SeedDeliveryApi()),
            ),
          ),
        );

        expect(find.text('أساس فت مي'), findsWidgets);
        expect(find.byType(CircularProgressIndicator), findsNothing);

        await expectMerzoxSeedGolden('cart_loaded_ar_375x812.png');
      });

      testWidgets('the empty cart renders its Arabic baseline', (
        WidgetTester tester,
      ) async {
        // Signed in, nothing stored: the basket a customer sees before they
        // have put anything in it, which is a different screen from the
        // signed-out gate `السلة` draws.
        SharedPreferences.setMockInitialValues(<String, Object>{
          AuthBloc.sessionKey: true,
          AuthBloc.tokenKey: 'seed-golden-token',
          AuthBloc.userTypeKey: 'customer',
          AuthBloc.nameKey: 'ياسمين خالد',
        });

        final HomeBloc homeBloc = await customerHome(isGuest: false);

        final Future<HomeState> cartSelected = homeBloc.stream.firstWhere(
          (HomeState state) => state.selectedTab == 1,
        );
        homeBloc.add(const HomeTabChanged(1));
        await cartSelected;

        await pumpMerzoxGoldenPage(
          tester,
          BlocProvider<HomeBloc>.value(
            value: homeBloc,
            child: withMerzoxGoldenDeviceInsets(
              HomeScreen(isGuest: false, apiService: _SeedDeliveryApi()),
            ),
          ),
        );

        expect(find.byType(CircularProgressIndicator), findsNothing);

        await expectMerzoxSeedGolden('cart_empty_ar_375x812.png');
      });

      // -- 54. المفضلة, the stores tab --------------------------------------
      testWidgets('favorites renders its Arabic stores-tab baseline', (
        WidgetTester tester,
      ) async {
        _useAuthenticatedCustomerSession();

        final FavoritesBloc favoritesBloc = FavoritesBloc(
          apiService: _SeedFavoritesApi(),
        );
        _closeOnTearDown(favoritesBloc);

        // The bloc opens on businesses, which is the tab this board draws.
        final Future<FavoritesState> ready = favoritesBloc.stream.firstWhere(
          (FavoritesState state) =>
              state.status == FavoritesStatus.ready &&
              state.selectedTab == FavoritesTab.businesses,
        );
        favoritesBloc.add(const FavoritesStarted());
        await ready;

        await pumpMerzoxGoldenPage(
          tester,
          BlocProvider<FavoritesBloc>.value(
            value: favoritesBloc,
            child: withMerzoxGoldenDeviceInsets(const FavoritesPage()),
          ),
        );

        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('المتاجر'), findsWidgets);

        await expectMerzoxSeedGolden('favorites_stores_ar_375x812.png');
      });

      // -- 58/59. إنشاء حساب – 1 and – 2 -----------------------------------
      //
      // Both boards say `ابدأ في إنشاء حسابك بخطوتين` and ask for a shop, so
      // they are the merchant enrolment wizard rather than the customer signup
      // `إنشاء حساب` draws: the first step is who is signing up, the second is
      // what they are opening.
      Future<void> pumpEnrollment(WidgetTester tester, int step) async {
        SharedPreferences.setMockInitialValues(const <String, Object>{});

        final BusinessEnrollmentBloc bloc = BusinessEnrollmentBloc();
        _closeOnTearDown(bloc);

        await pumpMerzoxGoldenPage(
          tester,
          BlocProvider<BusinessEnrollmentBloc>.value(
            value: bloc,
            child: withMerzoxGoldenDeviceInsets(
              BusinessEnrollmentPage(onCompleted: () {}),
            ),
          ),
        );

        if (step == 0) return;

        // Reached the way a merchant reaches it, which is also the only way:
        // the first step will not hand over an unfilled form.
        await tester.enterText(
          find.widgetWithText(TextFormField, 'رقم الجوال'),
          '592029316',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'البريد الإلكتروني'),
          'yasmeen@example.com',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'كلمة المرور الحالية'),
          'Merzox-2026',
        );
        await settleMerzoxGoldenFrames(tester);

        await tester.tap(find.text('التالي'));
        await settleMerzoxGoldenFrames(tester);
      }

      testWidgets('merchant enrolment renders its Arabic first-step baseline', (
        WidgetTester tester,
      ) async {
        await pumpEnrollment(tester, 0);

        expect(find.text('التالي'), findsOneWidget);

        await expectMerzoxSeedGolden('enrollment_account_ar_375x812.png');
      });

      testWidgets(
        'merchant enrolment renders its Arabic second-step baseline',
        (WidgetTester tester) async {
          await pumpEnrollment(tester, 1);

          expect(find.text('التالي'), findsNothing);

          await expectMerzoxSeedGolden('enrollment_store_ar_375x812.png');
        },
      );

      // -- 55/56/57. The rest of تتبع الطلب --------------------------------
      //
      // The seeded `order_tracking` is the order just placed. `– 1` is it being
      // prepared, `– 2` is it on the way with a driver named, and `تقييم` is
      // it delivered, with the review the customer is invited to leave.
      Future<OrderTrackingBloc> trackedOrder(String step) async {
        _useAuthenticatedCustomerSession();

        final OrderTrackingBloc bloc = OrderTrackingBloc(
          orderId: _trackedOrderId,
          apiService: _SeedOrderTrackingApi(step: step),
        );
        _closeOnTearDown(bloc);

        final Future<OrderTrackingState> ready = bloc.stream.firstWhere(
          (OrderTrackingState state) =>
              state.status == OrderTrackingStatus.ready,
        );
        bloc.add(const OrderTrackingStarted());
        await ready;

        return bloc;
      }

      Future<void> pumpTracking(
        WidgetTester tester,
        OrderTrackingBloc bloc,
      ) async {
        await pumpMerzoxGoldenPage(
          tester,
          BlocProvider<OrderTrackingBloc>.value(
            value: bloc,
            child: withMerzoxGoldenDeviceInsets(const OrderTrackingPage()),
          ),
        );
      }

      testWidgets('order tracking renders its Arabic preparing baseline', (
        WidgetTester tester,
      ) async {
        await pumpTracking(tester, await trackedOrder('preparing'));

        expect(find.text('يتم تحضير طلبك'), findsWidgets);
        expect(find.byType(CircularProgressIndicator), findsNothing);

        await expectMerzoxSeedGolden('order_tracking_preparing_ar_375x812.png');
      });

      testWidgets('order tracking renders its Arabic on-the-way baseline', (
        WidgetTester tester,
      ) async {
        await pumpTracking(tester, await trackedOrder('outForDelivery'));

        // The driver appears only once there is one.
        expect(find.text('Hamode Hussen'), findsOneWidget);

        await expectMerzoxSeedGolden(
          'order_tracking_on_the_way_ar_375x812.png',
        );
      });

      testWidgets('order tracking renders its Arabic delivered baseline', (
        WidgetTester tester,
      ) async {
        final OrderTrackingBloc bloc = await trackedOrder('delivered');
        expect(bloc.state.order!.tracking.canReview, isTrue);

        await pumpTracking(tester, bloc);

        // The composer is below the fold, which the board also shows: this
        // seed captures the 812 a device shows, and the reference is the same
        // screen scrolled to the same place.
        expect(find.text('تم وصول طلبك بنجاح'), findsWidgets);

        await expectMerzoxSeedGolden('order_tracking_review_ar_375x812.png');
      });

      // -- 61/62/63/64. الرسائل, past the inbox -----------------------------
      //
      // The inbox, its empty state and the notifications list are seeded. What
      // was left is the gate in front of them and the conversation itself,
      // which the corpus draws twice: once from the customer's side and once
      // from the shop's.
      testWidgets('the messages gate renders its Arabic baseline', (
        WidgetTester tester,
      ) async {
        SharedPreferences.setMockInitialValues(const <String, Object>{});

        final HomeBloc homeBloc = await customerHome(isGuest: true);

        final Future<HomeState> chatSelected = homeBloc.stream.firstWhere(
          (HomeState state) => state.selectedTab == 3,
        );
        homeBloc.add(const HomeTabChanged(3));
        await chatSelected;

        await pumpMerzoxGoldenPage(
          tester,
          BlocProvider<HomeBloc>.value(
            value: homeBloc,
            child: withMerzoxGoldenDeviceInsets(
              const HomeScreen(isGuest: true),
            ),
          ),
        );

        expect(find.text('تسجيل دخول'), findsOneWidget);

        await expectMerzoxSeedGolden('messages_gate_ar_375x812.png');
      });

      testWidgets('the unread inbox renders its Arabic baseline', (
        WidgetTester tester,
      ) async {
        final MessagesBloc bloc = await inbox(_SeedMessagesApi());

        final Future<MessagesState> filtered = bloc.stream.firstWhere(
          (MessagesState state) =>
              state.filter == MessagesFilter.unread &&
              state.status == MessagesStatus.ready,
        );
        bloc.add(const MessagesFilterChanged(MessagesFilter.unread));
        await filtered;

        await pumpMerzoxGoldenPage(
          tester,
          BlocProvider<MessagesBloc>.value(
            value: bloc,
            child: withMerzoxGoldenDeviceInsets(
              Scaffold(
                backgroundColor: Colors.white,
                body: SafeArea(
                  child: Builder(
                    builder: (BuildContext context) =>
                        MessagesInboxView(title: 'messages.title'.tr()),
                  ),
                ),
              ),
            ),
          ),
        );

        expect(find.byType(CircularProgressIndicator), findsNothing);

        await expectMerzoxSeedGolden('messages_unread_ar_375x812.png');
      });

      Future<void> pumpChat(
        WidgetTester tester, {
        required bool asCustomer,
        int lineCount = 6,
      }) async {
        _useAuthenticatedCustomerSession();

        final ChatBloc bloc = ChatBloc(
          apiService: _SeedChatApi(
            asCustomer: asCustomer,
            lineCount: lineCount,
          ),
          conversationId: 'c-seed',
        );
        _closeOnTearDown(bloc);

        final Future<ChatState> ready = bloc.stream.firstWhere(
          (ChatState state) =>
              state.status == ChatStatus.ready &&
              state.messages.length == lineCount,
        );
        bloc.add(const ChatStarted());
        await ready;

        await pumpMerzoxGoldenPage(
          tester,
          BlocProvider<ChatBloc>.value(
            value: bloc,
            child: withMerzoxGoldenDeviceInsets(const ChatPage()),
          ),
        );
      }

      testWidgets('an empty conversation renders its Arabic baseline', (
        WidgetTester tester,
      ) async {
        await pumpChat(tester, asCustomer: true, lineCount: 0);

        // `تفاصيل المتجر – 18` opens an empty thread with a banner rather than
        // a line of grey text: keep the conversation here, and here is who to
        // tell if something goes wrong.
        expect(
          find.textContaining('ننصحك بالاحتفاظ بجميع المحادثات'),
          findsOneWidget,
        );
        expect(
          find.text('فريقنا متواجد على مدار الساعة لخدمتكم'),
          findsOneWidget,
        );

        await expectMerzoxSeedGolden('chat_empty_ar_375x812.png');
      });

      testWidgets('a short conversation renders its Arabic baseline', (
        WidgetTester tester,
      ) async {
        await pumpChat(tester, asCustomer: true, lineCount: 3);

        // Three lines in, the banner is gone: it belongs to a thread nobody
        // has written in yet.
        expect(
          find.textContaining('ننصحك بالاحتفاظ بجميع المحادثات'),
          findsNothing,
        );

        await expectMerzoxSeedGolden('chat_storefront_ar_375x812.png');
      });

      testWidgets('a conversation renders its Arabic customer baseline', (
        WidgetTester tester,
      ) async {
        await pumpChat(tester, asCustomer: true);

        expect(find.text('متجر الياسمين'), findsOneWidget);
        expect(find.text('اكتب رسالتك هنا'), findsOneWidget);

        await expectMerzoxSeedGolden('chat_customer_ar_375x812.png');
      });

      testWidgets('a conversation renders its Arabic merchant baseline', (
        WidgetTester tester,
      ) async {
        await pumpChat(tester, asCustomer: false);

        // The same six lines, from the other end: the shop's own replies are
        // the ones on its side now.
        expect(find.text('ياسمين خالد'), findsOneWidget);

        await expectMerzoxSeedGolden('chat_merchant_ar_375x812.png');
      });

      // -- 65/66/67/68. The merchant overlays -------------------------------
      //
      // `الرئيسية – 12`, `– 13`, `– 16` and `– 14` are the orders filter, the
      // product menu, the product filter and the images screen. All four were
      // built in an earlier pass and none of them had ever been measured.
      testWidgets('the merchant order filter renders its Arabic baseline', (
        WidgetTester tester,
      ) async {
        final BusinessBloc bloc = await merchantShell(
          _SeedMerchantOrdersApi(),
          1,
        );

        await pumpMerzoxGoldenPage(
          tester,
          BlocProvider<BusinessBloc>.value(
            value: bloc,
            child: withMerzoxGoldenDeviceInsets(
              BusinessShellPage(onLoggedOut: () {}),
            ),
          ),
        );

        await tester.tap(find.byIcon(Icons.tune_rounded));
        await settleMerzoxGoldenFrames(tester);

        expect(find.text('تصفية'), findsOneWidget);
        expect(find.text('من تاريخ'), findsOneWidget);

        await expectMerzoxSeedGolden('merchant_order_filter_ar_375x812.png');
      });

      testWidgets('the merchant product menu renders its Arabic baseline', (
        WidgetTester tester,
      ) async {
        final BusinessBloc bloc = await merchantShell(
          _SeedMerchantProductsApi(),
          3,
        );

        await pumpMerzoxGoldenPage(
          tester,
          BlocProvider<BusinessBloc>.value(
            value: bloc,
            child: withMerzoxGoldenDeviceInsets(
              BusinessShellPage(onLoggedOut: () {}),
            ),
          ),
        );

        await tester.tap(find.byIcon(Icons.more_horiz_rounded).first);
        await settleMerzoxGoldenFrames(tester);

        // A live product is offered hiding, never showing.
        expect(find.text('إخفاء المنتج عن المتجر'), findsOneWidget);
        expect(find.text('حذف المنتج نهائيًا'), findsOneWidget);

        await expectMerzoxSeedGolden('merchant_product_menu_ar_375x812.png');
      });

      testWidgets('the merchant product filter renders its Arabic baseline', (
        WidgetTester tester,
      ) async {
        final BusinessBloc bloc = await merchantShell(
          _SeedMerchantProductsApi(),
          3,
        );

        await pumpMerzoxGoldenPage(
          tester,
          BlocProvider<BusinessBloc>.value(
            value: bloc,
            child: withMerzoxGoldenDeviceInsets(
              BusinessShellPage(onLoggedOut: () {}),
            ),
          ),
        );

        await tester.tap(find.byIcon(Icons.tune_rounded));
        await settleMerzoxGoldenFrames(tester);

        expect(find.text('قم باختيار تصنيف المنتجات'), findsOneWidget);

        await expectMerzoxSeedGolden('merchant_product_filter_ar_375x812.png');
      });

      testWidgets('the merchant images screen renders its Arabic baseline', (
        WidgetTester tester,
      ) async {
        SharedPreferences.setMockInitialValues(const <String, Object>{});

        await pumpMerzoxGoldenPage(
          tester,
          withMerzoxGoldenDeviceInsets(
            const MerchantProductImagesPage(
              // The board draws two images under the drop panel, each with its
              // own delete, crop and "primary" controls. They resolve to the
              // broken-image placeholder here, which is what a golden
              // environment with no network does; the row's own chrome is what
              // this seed measures.
              imageUrls: <String>[
                'https://merzox.test/seed/fit-me-1.png',
                'https://merzox.test/seed/fit-me-2.png',
              ],
            ),
          ),
        );

        // `حفظ` sits under both rows, which on this board and on this screen
        // is below the fold.
        expect(find.text('الصورة الأساسية'), findsNWidgets(2));

        await expectMerzoxSeedGolden('merchant_product_images_ar_375x812.png');
      });
    },
    skip: merzoxGoldenPlatformSkip,
  );
}
