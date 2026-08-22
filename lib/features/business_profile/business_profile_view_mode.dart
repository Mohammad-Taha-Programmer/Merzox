/// How the shared business storefront is being viewed.
///
/// The merchant preview renders the *same* storefront a customer sees, from the
/// same public API contracts. It differs only in interaction: a merchant must
/// not be able to follow, like, review, chat with, or buy from their own store
/// simply because they are looking at it.
///
/// This is presentation and interaction policy only. It is never authorization:
/// the route guard decides who may reach the preview, and the backend
/// independently enforces ownership on every request.
enum BusinessProfileViewMode {
  /// The normal customer storefront, fully interactive.
  customer,

  /// The merchant looking at their own store as customers see it. Read only.
  merchantPreview;

  bool get isPreview => this == BusinessProfileViewMode.merchantPreview;

  /// Customer-side mutations are refused in preview, and the protected
  /// favourite-status read is skipped so opening the preview issues no
  /// customer request at all.
  bool get allowsCustomerActions => this == BusinessProfileViewMode.customer;
}
