import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:merzox/features/cart/cart_item_integrity.dart';
import 'package:merzox/services/api_service.dart';
import 'package:merzox/services/product_share_service.dart';
import 'package:merzox/services/review_eligibility_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../cart/cart_storage_keys.dart';
import '../../cart/checkout_failure.dart';
import 'product_details_event.dart';
import 'product_details_state.dart';

class ProductDetailsBloc
    extends Bloc<ProductDetailsEvent, ProductDetailsState> {
  static const String cartKey = CartStorageKeys.items;
  final ApiService _apiService;
  final AuthSessionService _authSessionService;
  final ProductShareGateway _productShareGateway;
  final ReviewEligibilityGateway _reviewEligibilityGateway;

  ProductDetailsBloc({
    ApiService? apiService,
    AuthSessionService authSessionService = const AuthSessionService(),
    ProductShareGateway? productShareGateway,
    ReviewEligibilityGateway? reviewEligibilityGateway,
  }) : _apiService = apiService ?? ApiService(),
       _authSessionService = authSessionService,
       _productShareGateway =
           productShareGateway ?? const ProductShareService(),
       _reviewEligibilityGateway =
           reviewEligibilityGateway ?? ReviewEligibilityService(),
       super(const ProductDetailsState()) {
    on<ProductDetailsStarted>(_onStarted);
    on<ProductDetailsImageChanged>(_onImageChanged);
    on<ProductDetailsTabChanged>(_onTabChanged);
    on<ProductDetailsQuantityIncremented>(_onQuantityIncremented);
    on<ProductDetailsQuantityDecremented>(_onQuantityDecremented);
    on<ProductDetailsShareRequested>(_onShareRequested);
    on<ProductDetailsReviewSubmitted>(_onReviewSubmitted);
    on<ProductDetailsReviewEligibilityRetryRequested>(
      _onReviewEligibilityRetryRequested,
    );
    on<ProductDetailsAddToCartPressed>(_onAddToCartPressed);
    on<ProductDetailsBuyNowPressed>(_onBuyNowPressed);
    on<ProductDetailsReloadRequested>(_onReloadRequested);
    on<ProductDetailsReviewsRetryRequested>(_onReviewsRetryRequested);
  }

  Future<void> _onStarted(
    ProductDetailsStarted event,
    Emitter<ProductDetailsState> emit,
  ) async {
    emit(
      state.copyWith(
        status: ProductDetailsStatus.loading,
        businessId: event.businessId,
        product: event.initialProduct,
        detailsStatus: ProductDetailsSectionStatus.loading,
        reviewsStatus: ProductDetailsSectionStatus.loading,
        detailsError: '',
        reviewsError: '',
      ),
    );

    await _loadProductAndReviews(emit, event.initialProduct);
  }

  Future<void> _onReloadRequested(
    ProductDetailsReloadRequested event,
    Emitter<ProductDetailsState> emit,
  ) async {
    final product = state.product;
    if (product == null) return;

    emit(
      state.copyWith(
        detailsStatus: ProductDetailsSectionStatus.loading,
        reviewsStatus: ProductDetailsSectionStatus.loading,
        detailsError: '',
        reviewsError: '',
      ),
    );
    await _loadProductAndReviews(emit, product);
  }

  Future<void> _loadProductAndReviews(
    Emitter<ProductDetailsState> emit,
    BusinessProductApiModel knownProduct,
  ) async {
    final productFuture = _capture(
      () => _apiService.businessProduct(
        businessId: state.businessId,
        productId: knownProduct.id,
      ),
    );
    final reviewsFuture = _capture(
      () => _apiService.productReviews(
        businessId: state.businessId,
        productId: knownProduct.id,
      ),
    );
    final product = await productFuture;
    final reviews = await reviewsFuture;

    emit(
      state.copyWith(
        status: ProductDetailsStatus.ready,
        product: product.value ?? knownProduct,
        reviews: reviews.value ?? const [],
        detailsStatus: product.status,
        reviewsStatus: reviews.status,
        detailsError: product.errorMessage,
        reviewsError: reviews.errorMessage,
      ),
    );
  }

  void _onImageChanged(
    ProductDetailsImageChanged event,
    Emitter<ProductDetailsState> emit,
  ) {
    emit(state.copyWith(selectedImageIndex: event.index));
  }

  Future<void> _onTabChanged(
    ProductDetailsTabChanged event,
    Emitter<ProductDetailsState> emit,
  ) async {
    emit(state.copyWith(selectedTabIndex: event.index));

    if (event.index == 1 &&
        (state.reviewEligibilityStatus == ReviewEligibilityStatus.unchecked ||
            state.reviewEligibilityStatus == ReviewEligibilityStatus.failure)) {
      await _loadReviewEligibility(emit);
    }
  }

  void _onQuantityIncremented(
    ProductDetailsQuantityIncremented event,
    Emitter<ProductDetailsState> emit,
  ) {
    emit(state.copyWith(quantity: state.quantity + 1));
  }

  void _onQuantityDecremented(
    ProductDetailsQuantityDecremented event,
    Emitter<ProductDetailsState> emit,
  ) {
    emit(
      state.copyWith(quantity: state.quantity <= 1 ? 1 : state.quantity - 1),
    );
  }

  Future<void> _onShareRequested(
    ProductDetailsShareRequested event,
    Emitter<ProductDetailsState> emit,
  ) async {
    final product = state.product;

    if (product == null ||
        state.status == ProductDetailsStatus.sharing ||
        state.status == ProductDetailsStatus.savingReview) {
      return;
    }

    emit(
      state.copyWith(
        status: ProductDetailsStatus.sharing,
        message: null,
        errorMessage: null,
      ),
    );

    try {
      final outcome = await _productShareGateway.shareProduct(
        productName: product.name,
        businessName: event.businessName,
        displayPrice: product.displayPrice,
        languageCode: event.languageCode == 'en' ? 'en' : 'ar',
        sharePositionOrigin: event.sharePositionOrigin,
      );

      emit(
        state.copyWith(
          status: ProductDetailsStatus.ready,
          message: outcome == ProductShareOutcome.dismissed
              ? null
              : 'catalog.productShareOpened',
          errorMessage: null,
        ),
      );
    } catch (_) {
      emit(
        state.copyWith(
          status: ProductDetailsStatus.failure,
          message: null,
          errorMessage: 'catalog.productShareError',
        ),
      );
    }
  }

  Future<void> _onReviewSubmitted(
    ProductDetailsReviewSubmitted event,
    Emitter<ProductDetailsState> emit,
  ) async {
    final product = state.product;
    if (product == null ||
        state.reviewEligibilityStatus != ReviewEligibilityStatus.eligible) {
      return;
    }

    emit(
      state.copyWith(
        status: ProductDetailsStatus.savingReview,
        errorMessage: null,
      ),
    );

    try {
      final token = await _token();
      final response = await _apiService.submitProductReview(
        token: token,
        businessId: state.businessId,
        productId: product.id,
        rating: event.rating,
        comment: event.comment,
      );
      final reviews = await _capture(
        () => _apiService.productReviews(
          businessId: state.businessId,
          productId: product.id,
        ),
      );
      final knownReviews =
          reviews.value ??
          <BusinessReviewApiModel>[
            response.review,
            ...state.reviews.where((review) => review.id != response.review.id),
          ];

      emit(
        state.copyWith(
          status: ProductDetailsStatus.ready,
          product: response.product,
          reviews: knownReviews,
          reviewsStatus: reviews.status,
          reviewsError: reviews.errorMessage,
          message: 'catalog.productReviewPublished',
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: ProductDetailsStatus.failure,
          errorMessage: ApiService.messageFromError(error),
        ),
      );
    }
  }

  Future<void> _onReviewEligibilityRetryRequested(
    ProductDetailsReviewEligibilityRetryRequested event,
    Emitter<ProductDetailsState> emit,
  ) async {
    await _loadReviewEligibility(emit);
  }

  Future<void> _loadReviewEligibility(Emitter<ProductDetailsState> emit) async {
    final product = state.product;
    if (product == null) return;

    try {
      final session = await _authSessionService.read();

      if (!session.isAuthenticated) {
        emit(
          state.copyWith(
            reviewEligibilityStatus: ReviewEligibilityStatus.loginRequired,
          ),
        );
        return;
      }

      if (session.isBusiness) {
        emit(
          state.copyWith(
            reviewEligibilityStatus:
                ReviewEligibilityStatus.customerAccountRequired,
          ),
        );
        return;
      }

      final token = session.token;
      if (token == null || token.isEmpty) {
        emit(
          state.copyWith(
            reviewEligibilityStatus: ReviewEligibilityStatus.loginRequired,
          ),
        );
        return;
      }

      emit(
        state.copyWith(
          reviewEligibilityStatus: ReviewEligibilityStatus.checking,
        ),
      );

      final decision = await _reviewEligibilityGateway.productEligibility(
        token: token,
        businessId: state.businessId,
        productId: product.id,
      );

      emit(
        state.copyWith(
          reviewEligibilityStatus: statusForReviewDecision(decision),
        ),
      );
    } catch (_) {
      emit(
        state.copyWith(
          reviewEligibilityStatus: ReviewEligibilityStatus.failure,
        ),
      );
    }
  }

  Future<void> _onReviewsRetryRequested(
    ProductDetailsReviewsRetryRequested event,
    Emitter<ProductDetailsState> emit,
  ) async {
    final product = state.product;
    if (product == null) return;

    emit(
      state.copyWith(
        reviewsStatus: ProductDetailsSectionStatus.loading,
        reviewsError: '',
      ),
    );
    final result = await _capture(
      () => _apiService.productReviews(
        businessId: state.businessId,
        productId: product.id,
      ),
    );
    emit(
      state.copyWith(
        reviews: result.value ?? const [],
        reviewsStatus: result.status,
        reviewsError: result.errorMessage,
      ),
    );
  }

  Future<void> _onAddToCartPressed(
    ProductDetailsAddToCartPressed event,
    Emitter<ProductDetailsState> emit,
  ) async {
    final product = state.product;
    if (product == null) return;

    if (!_hasRealCommerceIds(product.id)) {
      emit(
        state.copyWith(
          status: ProductDetailsStatus.failure,
          errorMessage: 'catalog.invalidCartItem',
        ),
      );
      return;
    }

    // Refused at the event layer, so hiding the button is defence in depth
    // rather than the only guard. Nothing is written to the cart.
    if (!product.inStock) {
      emit(
        state.copyWith(
          status: ProductDetailsStatus.failure,
          errorMessage: 'catalog.outOfStock',
        ),
      );
      return;
    }

    try {
      await _token();
      final prefs = await SharedPreferences.getInstance();
      final items = prefs.getStringList(cartKey) ?? [];
      await prefs.remove(CartStorageKeys.checkoutId);
      items.add(
        jsonEncode({
          'businessId': state.businessId,
          'productId': product.id,
          'name': product.name,
          // The server-derived sale price, never the list price. The backend
          // reprices at checkout regardless, so this is the display snapshot.
          'price': product.displayPrice,
          'imageUrl': product.imageUrl,
          'quantity': state.quantity,
          'addedAt': DateTime.now().toIso8601String(),
        }),
      );
      await prefs.setStringList(cartKey, items);
      emit(
        state.copyWith(
          status: ProductDetailsStatus.action,
          message: 'catalog.addedToCart',
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: ProductDetailsStatus.failure,
          errorMessage: ApiService.messageFromError(error),
        ),
      );
    }
  }

  Future<void> _onBuyNowPressed(
    ProductDetailsBuyNowPressed event,
    Emitter<ProductDetailsState> emit,
  ) async {
    final product = state.product;
    if (product == null || !_hasRealCommerceIds(product.id)) {
      emit(
        state.copyWith(
          status: ProductDetailsStatus.failure,
          errorMessage: 'catalog.invalidCartItem',
        ),
      );
      return;
    }

    if (!product.inStock) {
      emit(
        state.copyWith(
          status: ProductDetailsStatus.failure,
          errorMessage: 'catalog.outOfStock',
        ),
      );
      return;
    }

    try {
      final token = await _token();
      final prefs = await SharedPreferences.getInstance();
      final address = prefs.getString(AuthBloc.addressKey)?.trim() ?? '';
      await _apiService.createOrder(
        token: token,
        businessId: state.businessId,
        deliveryAddress: address,
        clientOrderId:
            'buy-${DateTime.now().microsecondsSinceEpoch}-${product.id}',
        items: [
          OrderItemRequest(productId: product.id, quantity: state.quantity),
        ],
      );
      emit(
        state.copyWith(
          status: ProductDetailsStatus.action,
          message: 'orders.checkoutSuccess',
        ),
      );
    } catch (error) {
      // A stock refusal is a different fact from a network failure, and the
      // customer is told which one happened.
      emit(
        state.copyWith(
          status: ProductDetailsStatus.failure,
          errorMessage: checkoutFailureMessage(error),
        ),
      );
    }
  }

  bool _hasRealCommerceIds(String productId) {
    return isMongoBackedEntityId(state.businessId) &&
        isMongoBackedEntityId(productId);
  }

  Future<String> _token() async {
    final session = await _authSessionService.read();
    final token = session.token;
    if (token == null) {
      throw StateError('Authentication required');
    }
    return token;
  }

  Future<_LoadResult<T>> _capture<T>(Future<T> Function() request) async {
    try {
      return _LoadResult.success(await request());
    } catch (error) {
      return _LoadResult.failure(ApiService.messageFromError(error));
    }
  }
}

final class _LoadResult<T> {
  final T? value;
  final String errorMessage;

  const _LoadResult._({this.value, this.errorMessage = ''});

  const _LoadResult.success(T value) : this._(value: value);

  const _LoadResult.failure(String errorMessage)
    : this._(errorMessage: errorMessage);

  ProductDetailsSectionStatus get status => value == null
      ? ProductDetailsSectionStatus.failure
      : ProductDetailsSectionStatus.ready;
}
