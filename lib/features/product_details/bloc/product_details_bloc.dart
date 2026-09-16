import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:merzox/features/cart/cart_item_integrity.dart';
import 'package:merzox/services/api_service.dart';
import 'package:merzox/services/product_share_service.dart';
import 'package:merzox/services/review_eligibility_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../cart/cart_storage_keys.dart';
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
    on<ProductDetailsVariantSelected>(_onVariantSelected);
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
        selectedVariantId: null,
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

    final resolvedProduct = product.value ?? knownProduct;

    emit(
      state.copyWith(
        status: ProductDetailsStatus.ready,
        product: resolvedProduct,
        selectedVariantId: _selectionForProduct(resolvedProduct),
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
    // The screen already freezes the two buttons for a service. This is the
    // same rule where it cannot be walked around - the event is what the
    // buttons send, and it is reachable from anywhere.
    if (state.quantityIsFixed) return;

    emit(state.copyWith(quantity: state.quantity + 1));
  }

  void _onQuantityDecremented(
    ProductDetailsQuantityDecremented event,
    Emitter<ProductDetailsState> emit,
  ) {
    if (state.quantityIsFixed) return;

    emit(
      state.copyWith(quantity: state.quantity <= 1 ? 1 : state.quantity - 1),
    );
  }

  void _onVariantSelected(
    ProductDetailsVariantSelected event,
    Emitter<ProductDetailsState> emit,
  ) {
    final product = state.product;

    if (product == null || !product.hasVariants) return;

    BusinessProductVariantApiModel? selected;

    for (final variant in product.variants) {
      if (variant.id == event.variantId) {
        selected = variant;
        break;
      }
    }

    if (selected == null) {
      emit(
        state.copyWith(
          status: ProductDetailsStatus.failure,
          errorMessage: 'catalog.variantUnavailable',
        ),
      );
      return;
    }

    if (!selected.inStock) {
      emit(
        state.copyWith(
          status: ProductDetailsStatus.failure,
          errorMessage: 'catalog.outOfStock',
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        status: ProductDetailsStatus.ready,
        selectedVariantId: selected.id,
        message: null,
        errorMessage: null,
      ),
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
          selectedVariantId: _selectionForProduct(response.product),
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

  /// Whether the basket already carries a line for [productId].
  ///
  /// Read off the stored lines rather than the cart bloc, because the product
  /// page does not own one and the basket is the file on disk either way.
  bool _cartHolds(List<String> items, String productId) {
    for (final String raw in items) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic> &&
            decoded['productId'] == productId) {
          return true;
        }
      } catch (_) {
        // An unreadable line is dropped by the basket anyway.
      }
    }

    return false;
  }

  /// One line of a basket, however it is going to be paid for.
  ///
  /// `Add to basket` writes it to storage and `Buy now` hands it straight to
  /// checkout, and the two must describe the same purchase - one builder, so a
  /// field added for one of them cannot go missing from the other.
  String _purchaseLine(
    BusinessProductApiModel product,
    BusinessProductVariantApiModel? selectedVariant,
  ) {
    return jsonEncode({
      'businessId': state.businessId,
      'productId': product.id,
      if (selectedVariant != null) 'variantId': selectedVariant.id,
      if (selectedVariant != null) 'variantLabel': selectedVariant.label,
      'name': product.name,

      // Display snapshot only. The backend independently resolves this exact
      // product/variant identity at checkout.
      'price': selectedVariant?.finalPrice ?? product.displayPrice,

      'imageUrl': product.imageUrl,
      'quantity': state.orderQuantity,
      // So the basket knows it may not raise this line.
      if (product.isService) 'isService': true,
      'addedAt': DateTime.now().toIso8601String(),
    });
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

    if (!product.inStock) {
      emit(
        state.copyWith(
          status: ProductDetailsStatus.failure,
          errorMessage: 'catalog.outOfStock',
        ),
      );
      return;
    }

    final selectedVariant = state.selectedVariant;

    if (product.hasVariants && selectedVariant == null) {
      emit(
        state.copyWith(
          status: ProductDetailsStatus.failure,
          errorMessage: 'catalog.selectVariant',
        ),
      );
      return;
    }

    if (selectedVariant != null && !isMongoBackedEntityId(selectedVariant.id)) {
      emit(
        state.copyWith(
          status: ProductDetailsStatus.failure,
          errorMessage: 'catalog.invalidCartItem',
        ),
      );
      return;
    }

    if (selectedVariant != null && !selectedVariant.inStock) {
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

      // A second line for the same service is a second request for one thing.
      // The two would be summed at checkout into a quantity the server now
      // refuses, and the shopper would have no way to see why - so it is
      // stopped here, where it can be said plainly.
      if (product.isService && _cartHolds(items, product.id)) {
        emit(
          state.copyWith(
            status: ProductDetailsStatus.action,
            message: 'catalog.serviceAlreadyInCart',
          ),
        );
        return;
      }

      await prefs.remove(CartStorageKeys.checkoutId);

      items.add(_purchaseLine(product, selectedVariant));

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

    final selectedVariant = state.selectedVariant;

    if (product.hasVariants && selectedVariant == null) {
      emit(
        state.copyWith(
          status: ProductDetailsStatus.failure,
          errorMessage: 'catalog.selectVariant',
        ),
      );
      return;
    }

    if (selectedVariant != null && !isMongoBackedEntityId(selectedVariant.id)) {
      emit(
        state.copyWith(
          status: ProductDetailsStatus.failure,
          errorMessage: 'catalog.invalidCartItem',
        ),
      );
      return;
    }

    if (selectedVariant != null && !selectedVariant.inStock) {
      emit(
        state.copyWith(
          status: ProductDetailsStatus.failure,
          errorMessage: 'catalog.outOfStock',
        ),
      );
      return;
    }

    // It used to place the order here and then say so: it read the account's
    // address book, took whichever address was marked default, and posted the
    // order. Two things were wrong with that. The buyer was never shown where
    // their order was going or what the delivery would cost, and an account
    // with an empty book was refused at the press of a button with nowhere to
    // go and nothing to fix.
    //
    // It hands the purchase to checkout instead - the same three steps the
    // basket goes through, where the address is chosen and the fee is shown
    // before anything is ordered. Without touching the basket: the line goes
    // with the reader rather than into storage, so a customer who buys one
    // thing directly still has whatever they had put aside.
    emit(
      state.copyWith(
        status: ProductDetailsStatus.action,
        checkoutLine: _purchaseLine(product, selectedVariant),
      ),
    );
  }

  String? _selectionForProduct(BusinessProductApiModel product) {
    if (!product.hasVariants) return null;

    final currentId = state.selectedVariantId;
    if (currentId == null) return null;

    for (final variant in product.variants) {
      if (variant.id == currentId) return currentId;
    }

    // Never substitute another variant after a reload.
    return null;
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
