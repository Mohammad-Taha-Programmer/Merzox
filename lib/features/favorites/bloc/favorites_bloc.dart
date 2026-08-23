import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/api_service.dart';
import '../../../core/auth/auth_session_service.dart';
import '../../cart/cart_storage_keys.dart';
import '../../cart/cart_item_integrity.dart';
import 'favorites_event.dart';
import 'favorites_state.dart';

class FavoritesBloc extends Bloc<FavoritesEvent, FavoritesState> {
  final ApiService _apiService;
  final AuthSessionService _authSessionService;

  FavoritesBloc({
    ApiService? apiService,
    AuthSessionService authSessionService = const AuthSessionService(),
  }) : _apiService = apiService ?? ApiService(),
       _authSessionService = authSessionService,
       super(const FavoritesState()) {
    on<FavoritesStarted>(_onStarted);
    on<FavoritesTabChanged>(_onTabChanged);
    on<FavoritesLoadMoreRequested>(_onLoadMoreRequested);
    on<FavoritesRefreshRequested>(_onRefreshRequested);
    on<FavoriteBusinessRemoved>(_onBusinessRemoved);
    on<FavoriteProductRemoved>(_onProductRemoved);
    on<FavoriteProductAddedToCart>(_onProductAddedToCart);
  }

  Future<void> _onStarted(
    FavoritesStarted event,
    Emitter<FavoritesState> emit,
  ) async {
    await _loadBusinesses(emit, reset: true);
  }

  Future<void> _onTabChanged(
    FavoritesTabChanged event,
    Emitter<FavoritesState> emit,
  ) async {
    if (event.tab == state.selectedTab) return;
    emit(
      state.copyWith(
        selectedTab: event.tab,
        status: FavoritesStatus.ready,
        messageCode: '',
        errorMessage: '',
      ),
    );

    if (event.tab == FavoritesTab.businesses && !state.businessesLoaded) {
      await _loadBusinesses(emit, reset: true);
    }
    if (event.tab == FavoritesTab.products && !state.productsLoaded) {
      await _loadProducts(emit, reset: true);
    }
  }

  Future<void> _onRefreshRequested(
    FavoritesRefreshRequested event,
    Emitter<FavoritesState> emit,
  ) async {
    if (state.selectedTab == FavoritesTab.businesses) {
      await _loadBusinesses(emit, reset: true);
    } else {
      await _loadProducts(emit, reset: true);
    }
  }

  Future<void> _onLoadMoreRequested(
    FavoritesLoadMoreRequested event,
    Emitter<FavoritesState> emit,
  ) async {
    if (state.status == FavoritesStatus.loading ||
        state.status == FavoritesStatus.loadingMore) {
      return;
    }

    if (state.selectedTab == FavoritesTab.businesses && state.businessHasMore) {
      await _loadBusinesses(emit, reset: false);
    }
    if (state.selectedTab == FavoritesTab.products && state.productHasMore) {
      await _loadProducts(emit, reset: false);
    }
  }

  Future<void> _loadBusinesses(
    Emitter<FavoritesState> emit, {
    required bool reset,
  }) async {
    emit(
      state.copyWith(
        status: reset ? FavoritesStatus.loading : FavoritesStatus.loadingMore,
        messageCode: '',
        errorMessage: '',
      ),
    );

    try {
      final page = reset ? 1 : state.businessPage + 1;
      final response = await _apiService.favoriteBusinesses(
        token: await _token(),
        page: page,
      );
      emit(
        state.copyWith(
          status: FavoritesStatus.ready,
          businesses: reset
              ? response.businesses
              : [...state.businesses, ...response.businesses],
          businessPage: response.page,
          businessHasMore: response.hasMore,
          businessesLoaded: true,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: state.businesses.isEmpty
              ? FavoritesStatus.failure
              : FavoritesStatus.ready,
          errorMessage: ApiService.messageFromError(error),
        ),
      );
    }
  }

  Future<void> _loadProducts(
    Emitter<FavoritesState> emit, {
    required bool reset,
  }) async {
    emit(
      state.copyWith(
        status: reset ? FavoritesStatus.loading : FavoritesStatus.loadingMore,
        messageCode: '',
        errorMessage: '',
      ),
    );

    try {
      final page = reset ? 1 : state.productPage + 1;
      final response = await _apiService.favoriteProducts(
        token: await _token(),
        page: page,
      );
      emit(
        state.copyWith(
          status: FavoritesStatus.ready,
          products: reset
              ? response.products
              : [...state.products, ...response.products],
          productPage: response.page,
          productHasMore: response.hasMore,
          productsLoaded: true,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: state.products.isEmpty
              ? FavoritesStatus.failure
              : FavoritesStatus.ready,
          errorMessage: ApiService.messageFromError(error),
        ),
      );
    }
  }

  Future<void> _onBusinessRemoved(
    FavoriteBusinessRemoved event,
    Emitter<FavoritesState> emit,
  ) async {
    final previous = state.businesses;
    emit(
      state.copyWith(
        status: FavoritesStatus.mutating,
        businesses: previous
            .where((business) => business.id != event.businessId)
            .toList(),
        messageCode: '',
        errorMessage: '',
      ),
    );

    try {
      await _apiService.setBusinessFavorited(
        token: await _token(),
        businessId: event.businessId,
        favorited: false,
      );
      emit(
        state.copyWith(
          status: FavoritesStatus.ready,
          messageCode: 'favorites.removed',
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: FavoritesStatus.ready,
          businesses: previous,
          errorMessage: ApiService.messageFromError(error),
        ),
      );
    }
  }

  Future<void> _onProductRemoved(
    FavoriteProductRemoved event,
    Emitter<FavoritesState> emit,
  ) async {
    final previous = state.products;
    emit(
      state.copyWith(
        status: FavoritesStatus.mutating,
        products: previous
            .where((item) => item.product.id != event.productId)
            .toList(),
        messageCode: '',
        errorMessage: '',
      ),
    );

    try {
      await _apiService.setProductLiked(
        token: await _token(),
        businessId: event.businessId,
        productId: event.productId,
        liked: false,
      );
      emit(
        state.copyWith(
          status: FavoritesStatus.ready,
          messageCode: 'favorites.removed',
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: FavoritesStatus.ready,
          products: previous,
          errorMessage: ApiService.messageFromError(error),
        ),
      );
    }
  }

  Future<void> _onProductAddedToCart(
    FavoriteProductAddedToCart event,
    Emitter<FavoritesState> emit,
  ) async {
    FavoriteProductApiModel? favorite;
    for (final item in state.products) {
      if (item.product.id == event.productId &&
          item.business.id == event.businessId) {
        favorite = item;
        break;
      }
    }
    if (favorite == null) return;

    if (!isMongoBackedEntityId(favorite.business.id) ||
        !isMongoBackedEntityId(favorite.product.id)) {
      emit(
        state.copyWith(
          status: FavoritesStatus.ready,
          errorMessage: 'catalog.invalidCartItem',
        ),
      );
      return;
    }

    // The second cart-write site in the app, and it needs the same stock guard
    // as the product page: an out-of-stock favourite must not enter the cart.
    if (!favorite.product.inStock) {
      emit(
        state.copyWith(
          status: FavoritesStatus.ready,
          errorMessage: 'catalog.outOfStock',
        ),
      );
      return;
    }

    try {
      await _token();
      final prefs = await SharedPreferences.getInstance();
      final items = prefs.getStringList(CartStorageKeys.items) ?? [];
      await prefs.remove(CartStorageKeys.checkoutId);
      items.add(
        jsonEncode({
          'businessId': favorite.business.id,
          'productId': favorite.product.id,
          'name': favorite.product.name,
          // Same rule as the product page: the sale price, never the list one.
          'price': favorite.product.displayPrice,
          'imageUrl': favorite.product.imageUrl,
          'quantity': 1,
          'addedAt': DateTime.now().toIso8601String(),
        }),
      );
      await prefs.setStringList(CartStorageKeys.items, items);
      emit(
        state.copyWith(
          status: FavoritesStatus.ready,
          messageCode: 'favorites.addedToCart',
          errorMessage: '',
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: FavoritesStatus.ready,
          errorMessage: ApiService.messageFromError(error),
        ),
      );
    }
  }

  /// Session truth lives in [AuthSessionService]: a stale token left behind
  /// after logout, or a blank one, resolves to unauthenticated here rather
  /// than being re-interpreted per bloc.
  Future<String> _token() async {
    final session = await _authSessionService.read();
    final token = session.token;

    if (token == null) {
      throw StateError('Authentication required');
    }

    return token;
  }
}
