import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:merzox/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'business_profile_event.dart';
import 'business_profile_state.dart';

class BusinessProfileBloc
    extends Bloc<BusinessProfileEvent, BusinessProfileState> {
  final ApiService _apiService;

  BusinessProfileBloc({ApiService? apiService})
    : _apiService = apiService ?? ApiService(),
      super(const BusinessProfileState()) {
    on<BusinessProfileStarted>(_onStarted);
    on<BusinessProfileMainTabChanged>(_onMainTabChanged);
    on<BusinessProfileProductFilterChanged>(_onProductFilterChanged);
    on<BusinessProfileProductLikeToggled>(_onProductLikeToggled);
    on<BusinessProfileReviewSubmitted>(_onReviewSubmitted);
  }

  Future<void> _onStarted(
    BusinessProfileStarted event,
    Emitter<BusinessProfileState> emit,
  ) async {
    emit(
      state.copyWith(
        status: BusinessProfileStatus.loading,
        businessId: event.businessId,
      ),
    );
    await _loadProducts(emit, event.businessId, state.productClassification);
    await _loadFavoriteStatus(emit, event.businessId);
  }

  Future<void> _onMainTabChanged(
    BusinessProfileMainTabChanged event,
    Emitter<BusinessProfileState> emit,
  ) async {
    emit(state.copyWith(mainTabIndex: event.index));

    if (event.index == 1 && state.products.isEmpty) {
      await _loadProducts(emit, state.businessId, state.productClassification);
    }

    if (event.index == 2 && state.reviews.isEmpty) {
      await _loadReviews(emit, state.businessId);
    }
  }

  Future<void> _onProductFilterChanged(
    BusinessProfileProductFilterChanged event,
    Emitter<BusinessProfileState> emit,
  ) async {
    emit(
      state.copyWith(
        productClassification: event.classification,
        products: const [],
      ),
    );
    await _loadProducts(emit, state.businessId, event.classification);
  }

  Future<void> _onProductLikeToggled(
    BusinessProfileProductLikeToggled event,
    Emitter<BusinessProfileState> emit,
  ) async {
    final likedIds = Set<String>.from(state.likedProductIds);
    final shouldLike = !likedIds.contains(event.productId);

    if (shouldLike) {
      likedIds.add(event.productId);
    } else {
      likedIds.remove(event.productId);
    }

    emit(state.copyWith(likedProductIds: likedIds));

    try {
      final token = await _token();
      await _apiService.setProductLiked(
        token: token,
        businessId: state.businessId,
        productId: event.productId,
        liked: shouldLike,
      );
    } catch (_) {
      final revertedIds = Set<String>.from(state.likedProductIds);
      if (shouldLike) {
        revertedIds.remove(event.productId);
      } else {
        revertedIds.add(event.productId);
      }
      emit(state.copyWith(likedProductIds: revertedIds));
    }
  }

  Future<void> _onReviewSubmitted(
    BusinessProfileReviewSubmitted event,
    Emitter<BusinessProfileState> emit,
  ) async {
    emit(state.copyWith(status: BusinessProfileStatus.savingReview));

    try {
      final token = await _token();
      await _apiService.submitBusinessReview(
        token: token,
        businessId: state.businessId,
        rating: event.rating,
        comment: event.comment,
      );
      await _loadReviews(emit, state.businessId);
    } catch (error) {
      emit(
        state.copyWith(
          status: BusinessProfileStatus.failure,
          errorMessage: ApiService.messageFromError(error),
        ),
      );
    }
  }

  Future<void> _loadProducts(
    Emitter<BusinessProfileState> emit,
    String businessId,
    String classification,
  ) async {
    try {
      final products = await _apiService.businessProducts(
        businessId: businessId,
        classification: classification,
      );
      emit(
        state.copyWith(
          status: BusinessProfileStatus.ready,
          products: products.isEmpty
              ? _fallbackProducts(classification)
              : products,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: BusinessProfileStatus.ready,
          products: _fallbackProducts(classification),
          errorMessage: null,
        ),
      );
    }
  }

  Future<void> _loadReviews(
    Emitter<BusinessProfileState> emit,
    String businessId,
  ) async {
    try {
      final reviews = await _apiService.businessReviews(businessId: businessId);
      emit(
        state.copyWith(
          status: BusinessProfileStatus.ready,
          reviews: reviews.isEmpty ? _fallbackReviews : reviews,
        ),
      );
    } catch (_) {
      emit(
        state.copyWith(
          status: BusinessProfileStatus.ready,
          reviews: _fallbackReviews,
        ),
      );
    }
  }

  Future<void> _loadFavoriteStatus(
    Emitter<BusinessProfileState> emit,
    String businessId,
  ) async {
    try {
      final response = await _apiService.favoriteStatus(
        token: await _token(),
        businessId: businessId,
      );
      emit(state.copyWith(likedProductIds: response.productIds));
    } catch (_) {
      // Guests and offline users can still browse the public business profile.
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

List<BusinessProductApiModel> _fallbackProducts(String classification) {
  return List.generate(6, (index) {
    return BusinessProductApiModel(
      id: 'local-$classification-$index',
      name: 'أساس متين',
      description: 'منتج تجريبي',
      price: 35,
      imageUrl: '',
      imageUrls: const [],
      classification: classification,
      rating: 4,
      ratingCount: 14,
      likeCount: 0,
    );
  });
}

final List<BusinessReviewApiModel> _fallbackReviews = List.unmodifiable([
  BusinessReviewApiModel(
    id: 'local-review-1',
    userName: 'إبراهيم خالد',
    rating: 5,
    comment: 'المتجر رائع ومميز. وفرت منتجات ممتازة وبخدمة مناسبة للغاية.',
    createdAt: DateTime.now(),
  ),
  BusinessReviewApiModel(
    id: 'local-review-2',
    userName: 'محمود رمضان',
    rating: 4,
    comment: 'خدمة جيدة وتعامل لطيف، والأسعار مناسبة.',
    createdAt: DateTime.now(),
  ),
]);
