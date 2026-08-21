import '../../../services/api_service.dart';
import 'favorites_event.dart';

enum FavoritesStatus { initial, loading, ready, loadingMore, mutating, failure }

final class FavoritesState {
  final FavoritesStatus status;
  final FavoritesTab selectedTab;
  final List<SearchBusinessApiModel> businesses;
  final List<FavoriteProductApiModel> products;
  final int businessPage;
  final int productPage;
  final bool businessHasMore;
  final bool productHasMore;
  final bool businessesLoaded;
  final bool productsLoaded;
  final String messageCode;
  final String errorMessage;

  const FavoritesState({
    this.status = FavoritesStatus.initial,
    this.selectedTab = FavoritesTab.businesses,
    this.businesses = const [],
    this.products = const [],
    this.businessPage = 0,
    this.productPage = 0,
    this.businessHasMore = false,
    this.productHasMore = false,
    this.businessesLoaded = false,
    this.productsLoaded = false,
    this.messageCode = '',
    this.errorMessage = '',
  });

  FavoritesState copyWith({
    FavoritesStatus? status,
    FavoritesTab? selectedTab,
    List<SearchBusinessApiModel>? businesses,
    List<FavoriteProductApiModel>? products,
    int? businessPage,
    int? productPage,
    bool? businessHasMore,
    bool? productHasMore,
    bool? businessesLoaded,
    bool? productsLoaded,
    String? messageCode,
    String? errorMessage,
  }) {
    return FavoritesState(
      status: status ?? this.status,
      selectedTab: selectedTab ?? this.selectedTab,
      businesses: businesses ?? this.businesses,
      products: products ?? this.products,
      businessPage: businessPage ?? this.businessPage,
      productPage: productPage ?? this.productPage,
      businessHasMore: businessHasMore ?? this.businessHasMore,
      productHasMore: productHasMore ?? this.productHasMore,
      businessesLoaded: businessesLoaded ?? this.businessesLoaded,
      productsLoaded: productsLoaded ?? this.productsLoaded,
      messageCode: messageCode ?? this.messageCode,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
