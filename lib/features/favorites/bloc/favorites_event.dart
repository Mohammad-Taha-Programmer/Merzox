enum FavoritesTab { businesses, products }

sealed class FavoritesEvent {
  const FavoritesEvent();
}

final class FavoritesStarted extends FavoritesEvent {
  const FavoritesStarted();
}

final class FavoritesTabChanged extends FavoritesEvent {
  final FavoritesTab tab;

  const FavoritesTabChanged(this.tab);
}

final class FavoritesLoadMoreRequested extends FavoritesEvent {
  const FavoritesLoadMoreRequested();
}

final class FavoritesRefreshRequested extends FavoritesEvent {
  const FavoritesRefreshRequested();
}

final class FavoriteBusinessRemoved extends FavoritesEvent {
  final String businessId;

  const FavoriteBusinessRemoved(this.businessId);
}

final class FavoriteProductRemoved extends FavoritesEvent {
  final String businessId;
  final String productId;

  const FavoriteProductRemoved({
    required this.businessId,
    required this.productId,
  });
}

final class FavoriteProductAddedToCart extends FavoritesEvent {
  final String businessId;
  final String productId;

  const FavoriteProductAddedToCart({
    required this.businessId,
    required this.productId,
  });
}
