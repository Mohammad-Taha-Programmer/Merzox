import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:merzox/services/api_service.dart';

import 'business_profile_event.dart';
import 'business_profile_state.dart';

class BusinessProfileBloc
    extends Bloc<BusinessProfileEvent, BusinessProfileState> {
  final ApiService _apiService;
  final AuthSessionService _authSessionService;

  BusinessProfileBloc({
    ApiService? apiService,
    AuthSessionService authSessionService = const AuthSessionService(),
  }) : _apiService = apiService ?? ApiService(),
       _authSessionService = authSessionService,
       super(const BusinessProfileState()) {
    on<BusinessProfileStarted>(_onStarted);
    on<BusinessProfileMainTabChanged>(_onMainTabChanged);
    on<BusinessProfileProductFilterChanged>(_onProductFilterChanged);
    on<BusinessProfileProductLikeToggled>(_onProductLikeToggled);
    on<BusinessProfileReviewSubmitted>(_onReviewSubmitted);
    on<BusinessProfileDetailsRetryRequested>(_onDetailsRetryRequested);
    on<BusinessProfileProductsRetryRequested>(_onProductsRetryRequested);
    on<BusinessProfileReviewsRetryRequested>(_onReviewsRetryRequested);
  }

  Future<void> _onStarted(
    BusinessProfileStarted event,
    Emitter<BusinessProfileState> emit,
  ) async {
    emit(
      state.copyWith(
        status: BusinessProfileStatus.loading,
        businessId: event.businessId,
        detailsStatus: BusinessProfileSectionStatus.loading,
        productsStatus: BusinessProfileSectionStatus.loading,
        detailsError: '',
        productsError: '',
        errorMessage: '',
      ),
    );

    final detailsFuture = _capture(
      () => _apiService.business(businessId: event.businessId),
    );
    final productsFuture = _capture(
      () => _apiService.businessProducts(
        businessId: event.businessId,
        classification: state.productClassification,
      ),
    );
    final details = await detailsFuture;
    final products = await productsFuture;

    emit(
      state.copyWith(
        status: BusinessProfileStatus.ready,
        business: details.value,
        products: products.value ?? const [],
        detailsStatus: details.status,
        productsStatus: products.status,
        detailsError: details.errorMessage,
        productsError: products.errorMessage,
      ),
    );

    await _loadFavoriteStatus(emit, event.businessId);
  }

  Future<void> _onMainTabChanged(
    BusinessProfileMainTabChanged event,
    Emitter<BusinessProfileState> emit,
  ) async {
    emit(state.copyWith(mainTabIndex: event.index.clamp(0, 2)));

    if (event.index == 1 &&
        state.productsStatus == BusinessProfileSectionStatus.initial) {
      await _loadProducts(emit, state.productClassification);
    }

    if (event.index == 2 &&
        state.reviewsStatus == BusinessProfileSectionStatus.initial) {
      await _loadReviews(emit);
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
    await _loadProducts(emit, event.classification);
  }

  Future<void> _onProductLikeToggled(
    BusinessProfileProductLikeToggled event,
    Emitter<BusinessProfileState> emit,
  ) async {
    late final String token;
    try {
      token = await _token();
    } catch (_) {
      return;
    }

    final likedIds = Set<String>.from(state.likedProductIds);
    final shouldLike = !likedIds.contains(event.productId);

    if (shouldLike) {
      likedIds.add(event.productId);
    } else {
      likedIds.remove(event.productId);
    }

    emit(state.copyWith(likedProductIds: likedIds));

    try {
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
    emit(
      state.copyWith(
        status: BusinessProfileStatus.savingReview,
        errorMessage: '',
      ),
    );

    try {
      final token = await _token();
      final submittedReview = await _apiService.submitBusinessReview(
        token: token,
        businessId: state.businessId,
        rating: event.rating,
        comment: event.comment,
      );
      final reviews = await _capture(
        () => _apiService.businessReviews(businessId: state.businessId),
      );

      if (reviews.value != null) {
        emit(
          state.copyWith(
            status: BusinessProfileStatus.ready,
            reviews: reviews.value,
            reviewsStatus: BusinessProfileSectionStatus.ready,
            reviewsError: '',
          ),
        );
      } else {
        final knownReviews = <String, BusinessReviewApiModel>{
          submittedReview.id: submittedReview,
          for (final review in state.reviews) review.id: review,
        };
        emit(
          state.copyWith(
            status: BusinessProfileStatus.ready,
            reviews: knownReviews.values.toList(),
            reviewsStatus: BusinessProfileSectionStatus.failure,
            reviewsError: reviews.errorMessage,
          ),
        );
      }
    } catch (error) {
      emit(
        state.copyWith(
          status: BusinessProfileStatus.failure,
          errorMessage: ApiService.messageFromError(error),
        ),
      );
    }
  }

  Future<void> _onDetailsRetryRequested(
    BusinessProfileDetailsRetryRequested event,
    Emitter<BusinessProfileState> emit,
  ) async {
    await _loadDetails(emit);
  }

  Future<void> _onProductsRetryRequested(
    BusinessProfileProductsRetryRequested event,
    Emitter<BusinessProfileState> emit,
  ) async {
    await _loadProducts(emit, state.productClassification);
  }

  Future<void> _onReviewsRetryRequested(
    BusinessProfileReviewsRetryRequested event,
    Emitter<BusinessProfileState> emit,
  ) async {
    await _loadReviews(emit);
  }

  Future<void> _loadDetails(Emitter<BusinessProfileState> emit) async {
    emit(
      state.copyWith(
        detailsStatus: BusinessProfileSectionStatus.loading,
        detailsError: '',
      ),
    );
    final result = await _capture(
      () => _apiService.business(businessId: state.businessId),
    );
    emit(
      state.copyWith(
        business: result.value,
        detailsStatus: result.status,
        detailsError: result.errorMessage,
      ),
    );
  }

  Future<void> _loadProducts(
    Emitter<BusinessProfileState> emit,
    String classification,
  ) async {
    emit(
      state.copyWith(
        productsStatus: BusinessProfileSectionStatus.loading,
        productsError: '',
      ),
    );

    final result = await _capture(
      () => _apiService.businessProducts(
        businessId: state.businessId,
        classification: classification,
      ),
    );
    emit(
      state.copyWith(
        products: result.value ?? const [],
        productsStatus: result.status,
        productsError: result.errorMessage,
      ),
    );
  }

  Future<void> _loadReviews(Emitter<BusinessProfileState> emit) async {
    emit(
      state.copyWith(
        reviewsStatus: BusinessProfileSectionStatus.loading,
        reviewsError: '',
      ),
    );

    final result = await _capture(
      () => _apiService.businessReviews(businessId: state.businessId),
    );
    emit(
      state.copyWith(
        reviews: result.value ?? const [],
        reviewsStatus: result.status,
        reviewsError: result.errorMessage,
      ),
    );
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

  BusinessProfileSectionStatus get status => value == null
      ? BusinessProfileSectionStatus.failure
      : BusinessProfileSectionStatus.ready;
}
