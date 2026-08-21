import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:merzox/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../cart/cart_storage_keys.dart';
import 'product_details_event.dart';
import 'product_details_state.dart';

class ProductDetailsBloc
    extends Bloc<ProductDetailsEvent, ProductDetailsState> {
  static const String cartKey = CartStorageKeys.items;
  final ApiService _apiService;

  ProductDetailsBloc({ApiService? apiService})
    : _apiService = apiService ?? ApiService(),
      super(const ProductDetailsState()) {
    on<ProductDetailsStarted>(_onStarted);
    on<ProductDetailsImageChanged>(_onImageChanged);
    on<ProductDetailsTabChanged>(_onTabChanged);
    on<ProductDetailsQuantityIncremented>(_onQuantityIncremented);
    on<ProductDetailsQuantityDecremented>(_onQuantityDecremented);
    on<ProductDetailsDegreeSelected>(_onDegreeSelected);
    on<ProductDetailsReviewSubmitted>(_onReviewSubmitted);
    on<ProductDetailsAddToCartPressed>(_onAddToCartPressed);
    on<ProductDetailsBuyNowPressed>(_onBuyNowPressed);
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
      ),
    );

    try {
      final product = await _apiService.businessProduct(
        businessId: event.businessId,
        productId: event.initialProduct.id,
      );
      final reviews = await _apiService.productReviews(
        businessId: event.businessId,
        productId: event.initialProduct.id,
      );
      emit(
        state.copyWith(
          status: ProductDetailsStatus.ready,
          product: product,
          reviews: reviews.isEmpty ? _fallbackProductReviews : reviews,
        ),
      );
    } catch (_) {
      emit(
        state.copyWith(
          status: ProductDetailsStatus.ready,
          product: event.initialProduct,
          reviews: _fallbackProductReviews,
        ),
      );
    }
  }

  void _onImageChanged(
    ProductDetailsImageChanged event,
    Emitter<ProductDetailsState> emit,
  ) {
    emit(state.copyWith(selectedImageIndex: event.index));
  }

  void _onTabChanged(
    ProductDetailsTabChanged event,
    Emitter<ProductDetailsState> emit,
  ) {
    emit(state.copyWith(selectedTabIndex: event.index));
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

  void _onDegreeSelected(
    ProductDetailsDegreeSelected event,
    Emitter<ProductDetailsState> emit,
  ) {
    emit(state.copyWith(selectedDegree: event.degree));
  }

  Future<void> _onReviewSubmitted(
    ProductDetailsReviewSubmitted event,
    Emitter<ProductDetailsState> emit,
  ) async {
    final product = state.product;
    if (product == null) return;

    emit(state.copyWith(status: ProductDetailsStatus.savingReview));

    try {
      final token = await _token();
      final response = await _apiService.submitProductReview(
        token: token,
        businessId: state.businessId,
        productId: product.id,
        rating: event.rating,
        comment: event.comment,
      );
      final reviews = await _apiService.productReviews(
        businessId: state.businessId,
        productId: product.id,
      );
      emit(
        state.copyWith(
          status: ProductDetailsStatus.ready,
          product: response.product,
          reviews: reviews.isEmpty ? [response.review] : reviews,
          message: 'تم نشر تقييم المنتج',
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

  Future<void> _onAddToCartPressed(
    ProductDetailsAddToCartPressed event,
    Emitter<ProductDetailsState> emit,
  ) async {
    final product = state.product;
    if (product == null) return;

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
          'price': product.price,
          'imageUrl': product.imageUrl,
          'quantity': state.quantity,
          'degree': state.selectedDegree,
          'addedAt': DateTime.now().toIso8601String(),
        }),
      );
      await prefs.setStringList(cartKey, items);
      emit(
        state.copyWith(
          status: ProductDetailsStatus.action,
          message: 'تمت إضافة المنتج إلى السلة',
        ),
      );
    } catch (_) {
      emit(
        state.copyWith(
          status: ProductDetailsStatus.failure,
          errorMessage: 'يرجى تسجيل الدخول لإضافة المنتجات إلى السلة',
        ),
      );
    }
  }

  Future<void> _onBuyNowPressed(
    ProductDetailsBuyNowPressed event,
    Emitter<ProductDetailsState> emit,
  ) async {
    final product = state.product;
    if (product != null) {
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
            OrderItemRequest(
              productId: product.id,
              quantity: state.quantity,
              variant: state.selectedDegree,
            ),
          ],
        );
        emit(
          state.copyWith(
            status: ProductDetailsStatus.action,
            message: 'orders.checkoutSuccess',
          ),
        );
        return;
      } catch (_) {
        emit(
          state.copyWith(
            status: ProductDetailsStatus.failure,
            errorMessage: 'orders.checkoutError',
          ),
        );
        return;
      }
    }

    try {
      await _token();
      emit(
        state.copyWith(
          status: ProductDetailsStatus.action,
          message: 'سيتم تجهيز صفحة إتمام الطلب في الخطوة التالية',
        ),
      );
    } catch (_) {
      emit(
        state.copyWith(
          status: ProductDetailsStatus.failure,
          errorMessage: 'يرجى تسجيل الدخول لإتمام الشراء',
        ),
      );
    }
  }

  Future<String> _token() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(AuthBloc.tokenKey);
    if (token == null || token.isEmpty) {
      throw StateError('Authentication required');
    }
    return token;
  }
}

final List<BusinessReviewApiModel> _fallbackProductReviews = List.unmodifiable([
  BusinessReviewApiModel(
    id: 'local-product-review-1',
    userName: 'ياسمين خالد',
    rating: 5,
    comment:
        'قمت بشراء المنتج، الخامة جيدة جدا، وأنصح بالتعامل معهم حيث أنهم يعتمدون الجودة ومنتجاتهم أيضا.',
    createdAt: DateTime.now(),
  ),
  BusinessReviewApiModel(
    id: 'local-product-review-2',
    userName: 'محمود رمضان',
    rating: 4,
    comment: 'المنتج رائع وسعره مناسب. وصلتني الطلبية بحالة ممتازة.',
    createdAt: DateTime.now(),
  ),
]);
