import 'package:flutter/widgets.dart';

/// The designer's own glyphs, one copy per screen.
///
/// Every screen that draws a mark owns its own font file, in its own folder,
/// under its own family, named for that screen. A drawing used on five
/// screens is five files - `FavoritesRatingStarFull.ttf`,
/// `SearchPageRatingStarFull.ttf`, and so on - and they are byte-identical
/// today.
///
/// That is the point. When one screen wants a different star, its file is
/// replaced and no other screen moves. Sharing one file would have made every
/// such change a decision about five screens at once, and the reason a screen
/// looks the way it does would have lived somewhere other than that screen.
///
/// What it costs is worth saying too: a change meant for every screen is now
/// as many edits as there are screens, and the bundle carries the repeats.
/// The repeats are small - the whole set is under 600 KB - because the three
/// files the generator shipped with all of Material inside them happen to be
/// drawn on one screen each.
///
/// The code points are read out of each font's own `cmap`, not guessed, and
/// every glyph was rendered and looked at before it went on a screen: in
/// three of these files the real mark is not the last entry in the `cmap`,
/// and in three more it sits at the end of the entire Material library.
///
/// There is deliberately no chevron here. The set has no arrow of any kind,
/// and the row chevron has to keep `matchTextDirection` so Material leans it
/// into an Arabic reading - which Material's own glyph already does and a
/// hand-built [IconData] would not.
///
/// The sizes are at the foot of the file. A factor is a measurement of one
/// drawing against the Material mark it replaced, so it is shared by every
/// screen drawing that mark; a screen that swaps its copy for a different
/// drawing needs a factor of its own measured with it.
abstract final class MerzoxIcons {
  const MerzoxIcons._();

  // -- A storefront, as a customer sees it ---------------------------------
  //
  // `business_profile/`

  static const IconData businessProfileChat = IconData(
    0xe805,
    fontFamily: 'BusinessProfileChat',
  );

  static const IconData businessProfileContactUs = IconData(
    0xe809,
    fontFamily: 'BusinessProfileContactUs',
  );

  static const IconData businessProfileFavoriteOutline = IconData(
    0xe80c,
    fontFamily: 'BusinessProfileFavoriteOutline',
  );

  static const IconData businessProfileFavoriteProduct = IconData(
    0xe80e,
    fontFamily: 'BusinessProfileFavoriteProduct',
  );

  static const IconData businessProfileNotifications = IconData(
    0xe80a,
    fontFamily: 'BusinessProfileNotifications',
  );

  static const IconData businessProfileProductsCount = IconData(
    0xe802,
    fontFamily: 'BusinessProfileProductsCount',
  );

  static const IconData businessProfileRatingBarStar = IconData(
    0xe816,
    fontFamily: 'BusinessProfileRatingBarStar',
  );

  static const IconData businessProfileRatingStarEmpty = IconData(
    0xe801,
    fontFamily: 'BusinessProfileRatingStarEmpty',
  );

  static const IconData businessProfileRatingStarFull = IconData(
    0xf005,
    fontFamily: 'BusinessProfileRatingStarFull',
  );

  // -- The shared star strip on a business card ----------------------------
  //
  // `business_rating_stars/`

  static const IconData businessRatingStarsRatingStarEmpty = IconData(
    0xe801,
    fontFamily: 'BusinessRatingStarsRatingStarEmpty',
  );

  static const IconData businessRatingStarsRatingStarFull = IconData(
    0xf005,
    fontFamily: 'BusinessRatingStarsRatingStarFull',
  );

  static const IconData businessRatingStarsRatingStarHalf = IconData(
    0xf5c0,
    fontFamily: 'BusinessRatingStarsRatingStarHalf',
  );

  // -- The checkout step strip ---------------------------------------------
  //
  // `checkout_steps/`

  static const IconData checkoutStepsOrderData = IconData(
    0xe80d,
    fontFamily: 'CheckoutStepsOrderData',
  );

  /// A tick in a circle: the order is placed.
  ///
  /// The one mark in this library the designer did not draw. The set has
  /// no tick of any kind, so the strip carried Material's - heavier than
  /// the two beside it, and visibly a guest among them. This one is drawn
  /// at the weight the family uses, which was measured off its own
  /// outlines rather than guessed: between 62 and 79 units of the 1000
  /// the em is divided into.
  ///
  /// Its outline is straight segments where the rest are curves, so it is
  /// the one glyph here that would not survive being blown up to a poster.
  /// At the 22 the strip draws it, and at every size a phone will ever
  /// ask for, the difference is not there to see.
  ///
  /// It is a stand-in, and a good one. If the designer draws a tick, this
  /// file is what gets replaced and nothing else moves.
  static const IconData checkoutStepsOrderDone = IconData(
    0xe80e,
    fontFamily: 'CheckoutStepsOrderDone',
  );

  static const IconData checkoutStepsOrderPayment = IconData(
    0xe80c,
    fontFamily: 'CheckoutStepsOrderPayment',
  );

  // -- The customer's bottom bar -------------------------------------------
  //
  // `customer_navigation_bar/`

  static const IconData customerNavigationBarCart = IconData(
    0xe806,
    fontFamily: 'CustomerNavigationBarCart',
  );

  static const IconData customerNavigationBarHome = IconData(
    0xe807,
    fontFamily: 'CustomerNavigationBarHome',
  );

  static const IconData customerNavigationBarMessages = IconData(
    0xe805,
    fontFamily: 'CustomerNavigationBarMessages',
  );

  static const IconData customerNavigationBarProfile = IconData(
    0xe804,
    fontFamily: 'CustomerNavigationBarProfile',
  );

  static const IconData customerNavigationBarStores = IconData(
    0xe808,
    fontFamily: 'CustomerNavigationBarStores',
  );

  // -- المفضلة -------------------------------------------------------------
  //
  // `favorites/`

  static const IconData favoritesFavoriteOutline = IconData(
    0xe80c,
    fontFamily: 'FavoritesFavoriteOutline',
  );

  static const IconData favoritesFavoriteProduct = IconData(
    0xe80e,
    fontFamily: 'FavoritesFavoriteProduct',
  );

  static const IconData favoritesProducts = IconData(
    0xe813,
    fontFamily: 'FavoritesProducts',
  );

  static const IconData favoritesRatingStarEmpty = IconData(
    0xe801,
    fontFamily: 'FavoritesRatingStarEmpty',
  );

  static const IconData favoritesRatingStarFull = IconData(
    0xf005,
    fontFamily: 'FavoritesRatingStarFull',
  );

  // -- The bell that sits above every route --------------------------------
  //
  // `global_bell/`

  static const IconData globalBellNotifications = IconData(
    0xe80a,
    fontFamily: 'GlobalBellNotifications',
  );

  // -- The customer home screen and the profile tab inside it --------------
  //
  // `home_screen/`

  static const IconData homeScreenCampaignsProductsNotifications = IconData(
    0xe80a,
    fontFamily: 'HomeScreenCampaignsProductsNotifications',
  );

  static const IconData homeScreenEditProfile = IconData(
    0xe809,
    fontFamily: 'HomeScreenEditProfile',
  );

  static const IconData homeScreenFacebook = IconData(
    0xe810,
    fontFamily: 'HomeScreenFacebook',
  );

  static const IconData homeScreenFavoriteOutline = IconData(
    0xe80c,
    fontFamily: 'HomeScreenFavoriteOutline',
  );

  static const IconData homeScreenInstagram = IconData(
    0xe811,
    fontFamily: 'HomeScreenInstagram',
  );

  static const IconData homeScreenMap = IconData(
    0xe80b,
    fontFamily: 'HomeScreenMap',
  );

  static const IconData homeScreenMyOrders = IconData(
    0xe80a,
    fontFamily: 'HomeScreenMyOrders',
  );

  static const IconData homeScreenNotifications = IconData(
    0xe80a,
    fontFamily: 'HomeScreenNotifications',
  );

  static const IconData homeScreenProfile = IconData(
    0xe804,
    fontFamily: 'HomeScreenProfile',
  );

  static const IconData homeScreenSearch = IconData(
    0xe815,
    fontFamily: 'HomeScreenSearch',
  );

  static const IconData homeScreenShareApp = IconData(
    0xe80f,
    fontFamily: 'HomeScreenShareApp',
  );

  static const IconData homeScreenSignOut = IconData(
    0xe812,
    fontFamily: 'HomeScreenSignOut',
  );

  static const IconData homeScreenStores = IconData(
    0xe808,
    fontFamily: 'HomeScreenStores',
  );

  static const IconData homeScreenWhoWeAre = IconData(
    0xe80d,
    fontFamily: 'HomeScreenWhoWeAre',
  );

  // -- Signing in ----------------------------------------------------------
  //
  // `login/`

  static const IconData loginHidePassword = IconData(
    0xe802,
    fontFamily: 'LoginHidePassword',
  );

  static const IconData loginShowPassword = IconData(
    0xe803,
    fontFamily: 'LoginShowPassword',
  );

  // -- The merchant's own products and orders ------------------------------
  //
  // `merchant_browse/`

  static const IconData merchantBrowseDeleteProductForever = IconData(
    0xe805,
    fontFamily: 'MerchantBrowseDeleteProductForever',
  );

  static const IconData merchantBrowseEditProduct = IconData(
    0xeba4,
    fontFamily: 'MerchantBrowseEditProduct',
  );

  static const IconData merchantBrowseFilter = IconData(
    0xeba4,
    fontFamily: 'MerchantBrowseFilter',
  );

  static const IconData merchantBrowseProducts = IconData(
    0xe813,
    fontFamily: 'MerchantBrowseProducts',
  );

  static const IconData merchantBrowseSearch = IconData(
    0xe815,
    fontFamily: 'MerchantBrowseSearch',
  );

  // -- The merchant's dashboard controls -----------------------------------
  //
  // `merchant_dashboard/`

  static const IconData merchantDashboardSearch = IconData(
    0xe815,
    fontFamily: 'MerchantDashboardSearch',
  );

  // -- The merchant's bottom bar -------------------------------------------
  //
  // `merchant_navigation_bar/`

  static const IconData merchantNavigationBarAddProduct = IconData(
    0xe814,
    fontFamily: 'MerchantNavigationBarAddProduct',
  );

  static const IconData merchantNavigationBarHome = IconData(
    0xe807,
    fontFamily: 'MerchantNavigationBarHome',
  );

  static const IconData merchantNavigationBarOrders = IconData(
    0xe80a,
    fontFamily: 'MerchantNavigationBarOrders',
  );

  static const IconData merchantNavigationBarProducts = IconData(
    0xe813,
    fontFamily: 'MerchantNavigationBarProducts',
  );

  static const IconData merchantNavigationBarProfile = IconData(
    0xe804,
    fontFamily: 'MerchantNavigationBarProfile',
  );

  // -- One order, in the merchant hands ------------------------------------
  //
  // `merchant_order_detail/`

  static const IconData merchantOrderDetailNotifications = IconData(
    0xe80a,
    fontFamily: 'MerchantOrderDetailNotifications',
  );

  static const IconData merchantOrderDetailProducts = IconData(
    0xe813,
    fontFamily: 'MerchantOrderDetailProducts',
  );

  // -- The invoice ---------------------------------------------------------
  //
  // `merchant_order_invoice/`

  static const IconData merchantOrderInvoicePrintInvoice = IconData(
    0xeba4,
    fontFamily: 'MerchantOrderInvoicePrintInvoice',
  );

  // -- Adding or editing a product -----------------------------------------
  //
  // `merchant_product_editor/`

  static const IconData merchantProductEditorPreviewProduct = IconData(
    0xe801,
    fontFamily: 'MerchantProductEditorPreviewProduct',
  );

  static const IconData merchantProductEditorUploadProductImage = IconData(
    0xe800,
    fontFamily: 'MerchantProductEditorUploadProductImage',
  );

  // -- A product's pictures ------------------------------------------------
  //
  // `merchant_product_images/`

  static const IconData merchantProductImagesDeleteProductForever = IconData(
    0xe805,
    fontFamily: 'MerchantProductImagesDeleteProductForever',
  );

  static const IconData merchantProductImagesUploadProductImage = IconData(
    0xe800,
    fontFamily: 'MerchantProductImagesUploadProductImage',
  );

  // -- A product's options -------------------------------------------------
  //
  // `merchant_product_options/`

  static const IconData merchantProductOptionsDeleteProductForever = IconData(
    0xe805,
    fontFamily: 'MerchantProductOptionsDeleteProductForever',
  );

  // -- The merchant's profile tab ------------------------------------------
  //
  // `merchant_profile/`

  static const IconData merchantProfileAddProduct = IconData(
    0xe814,
    fontFamily: 'MerchantProfileAddProduct',
  );

  static const IconData merchantProfileBusinessSettings = IconData(
    0xe808,
    fontFamily: 'MerchantProfileBusinessSettings',
  );

  static const IconData merchantProfileChat = IconData(
    0xe805,
    fontFamily: 'MerchantProfileChat',
  );

  static const IconData merchantProfileContactUs = IconData(
    0xe809,
    fontFamily: 'MerchantProfileContactUs',
  );

  static const IconData merchantProfilePreviewProduct = IconData(
    0xe801,
    fontFamily: 'MerchantProfilePreviewProduct',
  );

  // -- The bar above the messages ------------------------------------------
  //
  // `messages_header/`

  static const IconData messagesHeaderSearch = IconData(
    0xe815,
    fontFamily: 'MessagesHeaderSearch',
  );

  // -- The map -------------------------------------------------------------
  //
  // `nearby_map/`

  static const IconData nearbyMapSearch = IconData(
    0xe815,
    fontFamily: 'NearbyMapSearch',
  );

  // -- The notification switches -------------------------------------------
  //
  // `notification_preferences/`

  static const IconData notificationPreferencesNotifications = IconData(
    0xe80a,
    fontFamily: 'NotificationPreferencesNotifications',
  );

  // -- The notifications board ---------------------------------------------
  //
  // `notifications_page/`

  static const IconData notificationsPageNotifications = IconData(
    0xe80a,
    fontFamily: 'NotificationsPageNotifications',
  );

  // -- Following one order -------------------------------------------------
  //
  // `order_tracking/`

  /// The handset on the button that calls the courier.
  static const IconData orderTrackingPhoneNumber = IconData(
    0xe80b,
    fontFamily: 'OrderTrackingPhoneNumber',
  );

  static const IconData orderTrackingRatingBarStar = IconData(
    0xe816,
    fontFamily: 'OrderTrackingRatingBarStar',
  );

  static const IconData orderTrackingRatingStarEmpty = IconData(
    0xe801,
    fontFamily: 'OrderTrackingRatingStarEmpty',
  );

  // -- طلباتي --------------------------------------------------------------
  //
  // `orders/`

  static const IconData ordersProducts = IconData(
    0xe813,
    fontFamily: 'OrdersProducts',
  );

  // -- One product ---------------------------------------------------------
  //
  // `product_details/`

  static const IconData productDetailsChat = IconData(
    0xe805,
    fontFamily: 'ProductDetailsChat',
  );

  static const IconData productDetailsRatingBarStar = IconData(
    0xe816,
    fontFamily: 'ProductDetailsRatingBarStar',
  );

  static const IconData productDetailsRatingStarEmpty = IconData(
    0xe801,
    fontFamily: 'ProductDetailsRatingStarEmpty',
  );

  static const IconData productDetailsRatingStarFull = IconData(
    0xf005,
    fontFamily: 'ProductDetailsRatingStarFull',
  );

  // -- Setting a new password ----------------------------------------------
  //
  // `reset_password/`

  static const IconData resetPasswordHidePassword = IconData(
    0xe802,
    fontFamily: 'ResetPasswordHidePassword',
  );

  static const IconData resetPasswordShowPassword = IconData(
    0xe803,
    fontFamily: 'ResetPasswordShowPassword',
  );

  // -- Search --------------------------------------------------------------
  //
  // `search_page/`

  static const IconData searchPageProductsCount = IconData(
    0xe802,
    fontFamily: 'SearchPageProductsCount',
  );

  static const IconData searchPageRatingStarFull = IconData(
    0xf005,
    fontFamily: 'SearchPageRatingStarFull',
  );

  static const IconData searchPageSearch = IconData(
    0xe815,
    fontFamily: 'SearchPageSearch',
  );

  // -- Sharing the app -----------------------------------------------------
  //
  // `share_app/`

  static const IconData shareAppWhatsapp = IconData(
    0xf232,
    fontFamily: 'ShareAppWhatsapp',
  );

  // -- Registering ---------------------------------------------------------
  //
  // `signup/`

  static const IconData signupHidePassword = IconData(
    0xe802,
    fontFamily: 'SignupHidePassword',
  );

  static const IconData signupShowPassword = IconData(
    0xe803,
    fontFamily: 'SignupShowPassword',
  );

  // -- How a shop can be reached -------------------------------------------
  //
  // `store_contact/`

  static const IconData storeContactContactUs = IconData(
    0xe809,
    fontFamily: 'StoreContactContactUs',
  );

  static const IconData storeContactPhoneNumber = IconData(
    0xe80b,
    fontFamily: 'StoreContactPhoneNumber',
  );

  static const IconData storeContactWhatsapp = IconData(
    0xf232,
    fontFamily: 'StoreContactWhatsapp',
  );

  // -- A shop's own settings -----------------------------------------------
  //
  // `store_settings/`

  static const IconData storeSettingsWhatsapp = IconData(
    0xf232,
    fontFamily: 'StoreSettingsWhatsapp',
  );

  // -- Sizes ----------------------------------------------------------------

  /// Against Material's `person_rounded`, the figure the home bar's avatar
  /// used to draw.
  ///
  /// Width. Material's figure is square in its ink and this one is half again
  /// as tall as it is wide, so anchoring on height put a small mark in the
  /// middle of a 28 circle with room all round it. Both were drawn inside the
  /// circle before this was chosen.
  static const double accountFigureSizeFactor = 0.670 / 0.833;

  /// Against Material's `logout_rounded`, which the bars drew beside it.
  ///
  /// The home bar and the profile's own button are two ways out of the same
  /// account, and they were two different marks until this.
  static const double signOutSizeFactor = 0.750 / 0.834;

  /// What to multiply a Material bell's size by to get [notifications] at the
  /// same apparent size.
  ///
  /// Material's bell stands 0.812 of its em box tall and this one 0.834 of
  /// its, so the swap is very nearly a wash - which is worth saying, because
  /// the first version of this number was 1/0.835 and grew every bell by a
  /// fifth. That came from a comment on the offers row, where the bell sits
  /// beside *other glyphs from this library* and those fill their whole em
  /// box: a true statement about a different comparison. The reference is
  /// Material here, and it had to be measured rather than borrowed.
  ///
  /// Height, not width: icons in a row line up by how tall they stand, and
  /// this bell is drawn slightly wider for its height than Material's.
  static const double notificationsSizeFactor = 0.812 / 0.834;

  /// Against Material's `chat_outlined`, which these WhatsApp places drew.
  static const double whatsappSizeFactor = 0.832 / 0.857;

  /// Against Material's `phone_outlined`.
  static const double phoneNumberSizeFactor = 0.750 / 0.833;

  /// Against Material's `phone_outlined` too - the mark is different but the
  /// size it has to match is the same one.
  static const double contactUsSizeFactor = 0.750 / 1.0;

  /// Against Material's `chat_bubble_outline_rounded`.
  static const double chatSizeFactor = 0.832 / 1.0;

  /// What to multiply a Material eye's size by to get these at the same
  /// apparent size.
  ///
  /// Width, not height: an eye is wide and short, and Material's two differ in
  /// height from each other - the crossed one is taller for its slash - while
  /// these two are the same height. Anchoring on width is what keeps the pair
  /// the same size as each other when a press swaps one for the other.
  static const double passwordEyeSizeFactor = 0.918 / 1.24;

  /// What to multiply a Material magnifier's size by to get [search] at the
  /// same apparent size.
  ///
  /// Material's fills 0.711 of its em box and this one fills all of its, so
  /// the number comes down by nearly a third. Measured, not borrowed - the
  /// bells were sized from a factor taken off another comparison and came out
  /// a fifth too big.
  static const double searchSizeFactor = 0.711 / 1.0;

  /// What to multiply a Material star's size by to get these at the same
  /// apparent size.
  ///
  /// Material's star fills 0.712 of its em box; these fill 1.086 of theirs, so
  /// a straight swap would have grown every star by half again and pushed the
  /// rows they sit in out of shape. One factor serves all four: they were
  /// rendered at the size it gives and measured, and their ink came out within
  /// a pixel of each other and of Material's - the designer drew them to
  /// match, so scaling each to its own ink would have pulled them apart.
  static const double ratingStarSizeFactor = 0.712 / 1.086;

  /// Against Material's `edit_outlined`.
  ///
  /// Both marks are square and both fill their box the same way, so this swap
  /// is the one place in the set where the arithmetic barely matters - which
  /// is worth saying only because it is the exception.
  static const double editProductSizeFactor = 0.750 / 1.000;

  /// Against Material's `delete_outline_rounded`.
  ///
  /// Height, not width: a bin is read by how tall it stands, and this one is
  /// drawn wider for its height than Material's. Anchoring on width instead
  /// made it visibly the smaller mark of the two on the board.
  static const double deleteProductSizeFactor = 0.750 / 1.000;

  /// Against Material's `visibility_outlined`.
  ///
  /// Width, for the reason [passwordEyeSizeFactor] gives: an eye is wide and
  /// short, and its width is what the reader registers. Anchored on height it
  /// came out plainly smaller than the eye it replaces.
  static const double previewProductSizeFactor = 0.920 / 0.835;

  /// Against Material's `cloud_upload_outlined`.
  ///
  /// Width. The two clouds are drawn to different proportions - this one is
  /// taller for its width - and the drop panel it stands in is sized by its
  /// own box, so the width is what has to stay put.
  static const double uploadProductImageSizeFactor = 1.000 / 1.288;

  /// Against Material's `inventory_2_outlined` and `shopping_bag_outlined`,
  /// the two different marks the two places counting products were drawing.
  ///
  /// Height, which is what makes one number serve both: the parcel is square,
  /// the bag is tall and narrow, and no single factor can match both in width.
  /// Matching their height is what puts the two counts on the same footing.
  static const double productsCountSizeFactor = 0.835 / 0.990;

  /// Against Material's `print_outlined`.
  ///
  /// Width, and it happens to be exactly one: the two printers are drawn to
  /// the same width and the designer's is the taller. A printer is a wide
  /// machine and its width is its outline; anchored on height it came out the
  /// plainly smaller mark.
  static const double printInvoiceSizeFactor = 0.835 / 0.835;

  /// Against Material's `description_outlined`.
  ///
  /// Height: a page is read by how tall it stands.
  static const double orderDataSizeFactor = 0.835 / 1.002;

  /// Against Material's `check_circle_outline_rounded`.
  ///
  /// Both are circles and both fill their box the same way in either
  /// direction, so this is the rare swap where the two anchorings agree to
  /// three decimals. Drawn to that size on purpose: the mark was made for this
  /// one place and could have been made any size, so it was made the size of
  /// the thing it replaces.
  static const double orderDoneSizeFactor = 0.835 / 1.000;

  /// Against Material's `account_balance_wallet_outlined`.
  ///
  /// Width. The designer's wallet is square where Material's is wider than it
  /// is tall, and at 22 the two anchorings differ by a single pixel - so the
  /// one that keeps the mark's width is the one to take.
  static const double orderPaymentSizeFactor = 0.792 / 1.002;

  /// Against Material's `favorite_rounded` and `favorite_border_rounded`.
  ///
  /// One number for both faces, because the designer drew the pair to the
  /// same ink and Material did too. A toggle that changed size on a tap would
  /// be the one thing worse than a toggle that changed shape.
  ///
  /// Width: a heart is a wide mark. These are drawn squarer than Material's,
  /// so anchoring on width keeps the mark's presence and lets it stand a
  /// little taller, which is the shape the designer drew.
  static const double favoriteHeartSizeFactor = 0.835 / 1.005;

  /// Against Material's `tune_rounded`.
  ///
  /// Width, which is what a row of sliders is read by. The designer draws two
  /// rows where Material draws three, so the two marks are not the same
  /// picture; matching their widths is what keeps the button looking the same.
  static const double filterSizeFactor = 0.750 / 0.417;

  /// Against Material's `settings_outlined`.
  ///
  /// Both gears are square and the two anchorings differ by two parts in a
  /// hundred, so this one is width by convention rather than by argument.
  static const double businessSettingsSizeFactor = 0.815 / 0.955;

  /// Against Material's `inventory_2_outlined`, the archive box five
  /// placeholders were drawing.
  static const double productsSizeFactor = 0.835 / 1.002;

  /// Against Material's `add_circle_outline_rounded`.
  ///
  /// A circle becomes a rounded square at the same size, which is as close to
  /// a like-for-like swap as this library gets.
  static const double addProductSizeFactor = 0.835 / 1.005;
}
