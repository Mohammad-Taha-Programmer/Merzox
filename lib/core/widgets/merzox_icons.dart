import 'package:flutter/widgets.dart';

/// The designer's own glyphs.
///
/// Each arrived as its own `.ttf` holding one real icon and a handful of
/// leftovers the generator puts in every file, so each one is its own font
/// family and the family name is the file name. That is why every constant
/// below names a family of its own rather than sharing one - it is how the
/// set was exported, not a choice made here. Merging them into a single font
/// is worth doing when the rest of the screens are converted; the whole map
/// lives in this one file so that day is a change to this file alone.
///
/// The fonts sit under `assets/fonts/icons_fonts/<screen>/`, each file named
/// for the section it serves rather than for the picture it happens to be.
/// So [campaignsProductsNotifications] is its own font although it is, today,
/// the same bell the library keeps as `Notifications.ttf` - the day the
/// offers row wants a drawing of its own, one file changes and one screen
/// with it.
///
/// The code points are read out of each font's own `cmap`, not guessed. What
/// the filenames could not tell was whether each glyph draws what its name
/// says, so they were rendered and looked at before any of them went onto a
/// screen.
///
/// There is deliberately no chevron here. The set has no arrow of any kind,
/// and the row chevron has to keep `matchTextDirection` so Material leans it
/// into an Arabic reading - which Material's own glyph already does and a
/// hand-built [IconData] would not.
abstract final class MerzoxIcons {
  const MerzoxIcons._();

  /// `تعديل الملف الشخصي`
  static const IconData editProfile = IconData(
    0xe809,
    fontFamily: 'EditProfileIcon',
  );

  /// `طلباتي`
  static const IconData myOrders = IconData(0xe80a, fontFamily: 'MyOrdersIcon');

  /// `الخريطة`
  static const IconData map = IconData(0xe80b, fontFamily: 'MapIcon');

  /// `المفضلة`
  static const IconData favorites = IconData(0xe80c, fontFamily: 'Favorites');

  /// `من نحن`
  static const IconData whoWeAre = IconData(0xe80d, fontFamily: 'WhoWeAreIcon');

  /// `شارك التطبيق مع أصدقائك`
  static const IconData shareApp = IconData(0xe80f, fontFamily: 'ShareAppIcon');

  /// `تسجيل خروج`
  static const IconData signOut = IconData(0xe812, fontFamily: 'SignOutIcon');

  /// Against Material's `logout_rounded`, which the bars drew beside it.
  ///
  /// The home bar and the profile's own button are two ways out of the same
  /// account, and they were two different marks until this.
  static const double signOutSizeFactor = 0.750 / 0.834;

  /// `التسجيل كتاجر`
  static const IconData stores = IconData(0xe808, fontFamily: 'BusinessesIcon');

  /// The account, where no picture was ever stored for one.
  static const IconData profile = IconData(0xe804, fontFamily: 'ProfileIcon');

  static const IconData facebook = IconData(
    0xe810,
    fontFamily: 'FacebookLogoIcon',
  );

  static const IconData instagram = IconData(
    0xe811,
    fontFamily: 'InstagramLogoIcon',
  );

  /// `تنبيهات المنتجات والعروض`
  static const IconData campaignsProductsNotifications = IconData(
    0xe80a,
    fontFamily: 'CampaignsProductsNotifications',
  );

  /// The bell, wherever one is drawn.
  ///
  /// The one glyph here that is not a section's own. It is the same bell on
  /// the home bar, the notifications board, a storefront, a merchant's order
  /// and the preference switches, and it is meant to stay the same on all of
  /// them - so it is read from the library's own file rather than copied per
  /// screen the way the rest are.
  ///
  /// Its ink fills 0.835 of the em box where Material's fills nearly all of
  /// one, so a site swapping from `Icons.notifications_none_rounded` divides
  /// its old size by that to keep the mark the size it was.
  static const IconData notifications = IconData(
    0xe80a,
    fontFamily: 'Notifications',
  );

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

  // -- Rating stars ---------------------------------------------------------
  //
  // Four drawings, read from the library rather than copied per screen: a
  // rating looks the same wherever one is shown, and that is the point.
  //
  // The first three are the display set. The fourth is the star of the bar a
  // reader taps to leave a rating - it is a different outline from
  // [ratingStarFull], not a copy of it, which was checked rather than assumed.
  //
  // Their code points are the only ones in this set that are not in the
  // private-use range the rest of the library uses: the generator left three
  // of its own glyphs in each file, and in three of the four the real star is
  // not the last entry in the `cmap`. They were rendered and looked at.

  /// A whole star, in a rating that is being read.
  static const IconData ratingStarFull = IconData(
    0xf005,
    fontFamily: 'FullRoundedRatingStar',
  );

  /// Half a star, for an average that lands between two.
  static const IconData ratingStarHalf = IconData(
    0xf5c0,
    fontFamily: 'HalfRoundedRatingStar',
  );

  /// A star not reached.
  static const IconData ratingStarEmpty = IconData(
    0xe801,
    fontFamily: 'OutlinedRatingStar',
  );

  /// The star of the bar a reader taps to leave a rating.
  static const IconData ratingBarStar = IconData(
    0xe816,
    fontFamily: 'RatingBarStar',
  );

  // -- Ways of being reached ------------------------------------------------
  //
  // Four marks, and the set is the reason to take them together: three of
  // these places were drawing a plain speech bubble for WhatsApp, which is a
  // service with a mark of its own that everybody already knows.
  //
  // The two handsets are not interchangeable. [phoneNumber] is a handset with
  // signal waves and belongs beside a number; [contactUs] is a bare handset
  // and belongs on the action that reaches somebody. The designer drew them
  // separately and the file names say which is which.

  /// WhatsApp's own mark, where a generic bubble used to stand for it.
  static const IconData whatsapp = IconData(0xf232, fontFamily: 'WatsappIcon');

  /// A handset with signal waves: beside a phone number.
  static const IconData phoneNumber = IconData(
    0xe80b,
    fontFamily: 'PhoneNumberIcon',
  );

  /// A bare handset: on the action that reaches somebody.
  static const IconData contactUs = IconData(0xe809, fontFamily: 'ContactUs');

  /// A speech bubble: a conversation, and the way into one.
  static const IconData chat = IconData(0xe805, fontFamily: 'ChatIcon');

  /// Against Material's `chat_outlined`, which these WhatsApp places drew.
  static const double whatsappSizeFactor = 0.832 / 0.857;

  /// Against Material's `phone_outlined`.
  static const double phoneNumberSizeFactor = 0.750 / 0.833;

  /// Against Material's `phone_outlined` too - the mark is different but the
  /// size it has to match is the same one.
  static const double contactUsSizeFactor = 0.750 / 1.0;

  /// Against Material's `chat_bubble_outline_rounded`.
  static const double chatSizeFactor = 0.832 / 1.0;

  // -- The eye on a password field ------------------------------------------
  //
  // The names are the designer's and they settle a question the app was of two
  // minds about: which eye stands beside a password that is hidden. This one -
  // "show password" - is what a reader presses to reveal it, so it is the one
  // drawn while the field is obscured. The crossed eye is what they press to
  // put it back.
  //
  // `EyeIconHidePassword` also carries a stray box glyph the generator left
  // behind, so the code points here were read out of each `cmap` and the
  // glyphs rendered before either went on a field.

  /// The open eye: press it to reveal a hidden password.
  static const IconData showPassword = IconData(
    0xe803,
    fontFamily: 'EyeIconShowPassword',
  );

  /// The crossed eye: press it to hide a revealed one.
  static const IconData hidePassword = IconData(
    0xe802,
    fontFamily: 'EyeIconHidePassword',
  );

  /// What to multiply a Material eye's size by to get these at the same
  /// apparent size.
  ///
  /// Width, not height: an eye is wide and short, and Material's two differ in
  /// height from each other - the crossed one is taller for its slash - while
  /// these two are the same height. Anchoring on width is what keeps the pair
  /// the same size as each other when a press swaps one for the other.
  static const double passwordEyeSizeFactor = 0.918 / 1.24;

  // -- Search ---------------------------------------------------------------

  /// The magnifier, on every field that searches something.
  ///
  /// There is no companion for Material's `search_off_rounded` - the crossed
  /// magnifier a screen shows when a search found nothing - so those keep
  /// theirs. The set has nothing that draws an absence.
  static const IconData search = IconData(0xe815, fontFamily: 'SearchIcon');

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

  // -- Keeping a product -----------------------------------------------------
  //
  // What a merchant does to one of their own products: edit it, delete it,
  // look at it the way a customer will, and put pictures on it. The count of
  // them is here too, because it is the same drawing and it is read off the
  // same idea of a product.
  //
  // `EditProductIcon.ttf` is not like the others in this set: the generator
  // shipped it with the whole Material library inside it and the designer's
  // own mark appended at the very end, at U+EBA4. Taking the last entry in a
  // `cmap` is a habit that would have been right here and wrong three times
  // already, so this one was rendered and looked at like the rest.
  //
  // `CropProductPic.ttf` has no constant. Nothing in the app crops a picture
  // yet - the image manager says so in its own header - and a mark for an
  // action that does not exist is not an icon, it is a promise.

  /// The pencil on a product's row: opens the editor.
  static const IconData editProduct = IconData(
    0xeba4,
    fontFamily: 'EditProductIcon',
  );

  /// The bin: removes a product, one of its variants, or one of its pictures.
  static const IconData deleteProductForever = IconData(
    0xe805,
    fontFamily: 'DeleteProductForever',
  );

  /// The eye: shows a merchant what a customer would see.
  static const IconData previewProduct = IconData(
    0xe801,
    fontFamily: 'PreviewProductIcon',
  );

  /// The cloud with an arrow, on the panel that takes pictures.
  static const IconData uploadProductImage = IconData(
    0xe800,
    fontFamily: 'UploadProductImage',
  );

  /// A parcel, beside a number of products.
  static const IconData productsCount = IconData(
    0xe802,
    fontFamily: 'ProductsCount',
  );

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

  // -- An order, and what is done with one ----------------------------------
  //
  // The checkout's three steps and the printed invoice. Two of the three steps
  // convert; the third is a tick in a circle and the set has nothing that
  // draws one, so it keeps Material's.
  //
  // `PrintInvoice.ttf` is the second file in this library shipped with the
  // whole Material set inside it and the designer's mark appended at U+EBA4,
  // after `EditProductIcon.ttf`. Two out of forty is enough to make rendering
  // every glyph the rule rather than a precaution.
  //
  // `ILSIcon.ttf` has no constant, and the reason is worth writing down: the
  // shekel in this app is not an icon. `merzoxPrice` builds a string - `65 ₪`
  // - and every price on every screen is that string inside a `Text`. Putting
  // the drawn mark there means an inline span at each of them, which changes
  // how prices align, select and read aloud. That is a typography decision
  // about money, not an icon swap, and it is left for its own day.

  /// The printer, on the invoice a merchant sends to paper.
  static const IconData printInvoice = IconData(
    0xeba4,
    fontFamily: 'PrintInvoice',
  );

  /// A written page: the checkout step where the buyer's details are given.
  static const IconData orderData = IconData(
    0xe80d,
    fontFamily: 'OrderDataIcon',
  );

  /// A wallet: the checkout step where the order is paid for.
  static const IconData orderPayment = IconData(
    0xe80c,
    fontFamily: 'OrderPaymentIcon',
  );

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

  /// Against Material's `account_balance_wallet_outlined`.
  ///
  /// Width. The designer's wallet is square where Material's is wider than it
  /// is tall, and at 22 the two anchorings differ by a single pixel - so the
  /// one that keeps the mark's width is the one to take.
  static const double orderPaymentSizeFactor = 0.792 / 1.002;

  // -- Liking, filtering, and a shop's own settings -------------------------

  /// A filled heart: a product that is liked, or one already in the list.
  ///
  /// [favorites] is the same heart drawn as an outline, and the two are a
  /// matched pair - same silhouette, same highlight, same ink to three
  /// decimal places - which is what makes them usable as the two faces of one
  /// toggle. Material's pair matches too, but mixing one from each set would
  /// have changed the mark's shape on a tap and not only its fill.
  static const IconData favoriteProduct = IconData(
    0xe80e,
    fontFamily: 'FavoriteProduct',
  );

  /// The sliders on the button that filters a merchant's own products.
  ///
  /// A third file shipped with the whole Material set inside it, the mark
  /// appended at U+EBA4. Its ink fills only 0.417 of the em box - far less
  /// than anything else in this library - so its factor is above 1.7 where
  /// every other one here is below 1.1. That is the glyph, not a mistake.
  static const IconData filter = IconData(0xeba4, fontFamily: 'FilterIcon');

  /// The gear on the row that opens a shop's settings.
  static const IconData businessSettings = IconData(
    0xe808,
    fontFamily: 'BusinessSettings',
  );

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

  // -- A product, and adding one --------------------------------------------
  //
  // These two files close the library out, and the four left beside them are
  // accounted for rather than unused: HomeIcon.ttf, CartIcon.ttf,
  // ProductsIcon.ttf and AddProductsIcon.ttf are byte-for-byte the originals
  // that were copied into the two bottom-bar folders. They were checked by
  // hash, not by name. Nothing in the app draws a house or a trolley outside
  // those bars, so HomeIcon and CartIcon get no constant here and are not
  // orphans either - they are already on screen under their bars' families.
  //
  // The two parcels are not a duplicate. [productsCount] is a box seen from a
  // corner and stands beside a number; this one is a box seen face on and is
  // the mark the bar uses for `المنتجات`. The designer drew both, and which
  // is which was settled by rendering them side by side.

  /// A parcel: a product, where its own picture is missing.
  static const IconData products = IconData(0xe813, fontFamily: 'ProductsIcon');

  /// A plus in a rounded square: add a product.
  ///
  /// Only on the button that carries no words. The labelled `إضافة منتج`
  /// button keeps Material's bare plus: a plus beside a word is a typographic
  /// mark, and boxing it makes the button a different button rather than the
  /// same one drawn by the designer. At that button's 18 the box is either
  /// illegible or louder than its own label - both were rendered before this
  /// was decided.
  static const IconData addProduct = IconData(
    0xe814,
    fontFamily: 'AddProductsIcon',
  );

  /// Against Material's `inventory_2_outlined`, the archive box five
  /// placeholders were drawing.
  static const double productsSizeFactor = 0.835 / 1.002;

  /// Against Material's `add_circle_outline_rounded`.
  ///
  /// A circle becomes a rounded square at the same size, which is as close to
  /// a like-for-like swap as this library gets.
  static const double addProductSizeFactor = 0.835 / 1.005;

  // -- The customer's bottom bar --------------------------------------------
  //
  // Five places, the middle one raised out of the bar. Home and the account
  // are the same drawings the merchant's bar uses, kept in their own folder
  // and under their own family for the reason the file header gives.

  static const IconData customerNavHome = IconData(
    0xe807,
    fontFamily: 'CustomerNavHome',
  );

  static const IconData customerNavCart = IconData(
    0xe806,
    fontFamily: 'CustomerNavCart',
  );

  /// The raised button: `المتاجر`, drawn as a shop awning.
  static const IconData customerNavStores = IconData(
    0xe808,
    fontFamily: 'CustomerNavStores',
  );

  static const IconData customerNavMessages = IconData(
    0xe805,
    fontFamily: 'CustomerNavMessages',
  );

  static const IconData customerNavProfile = IconData(
    0xe804,
    fontFamily: 'CustomerNavProfile',
  );

  // -- The merchant's bottom bar --------------------------------------------

  static const IconData merchantNavHome = IconData(
    0xe807,
    fontFamily: 'MerchantNavHome',
  );

  static const IconData merchantNavOrders = IconData(
    0xe80a,
    fontFamily: 'MerchantNavOrders',
  );

  /// The raised button: `إضافة منتجات`, a cross in a rounded square.
  static const IconData merchantNavAddProduct = IconData(
    0xe814,
    fontFamily: 'MerchantNavAddProduct',
  );

  static const IconData merchantNavProducts = IconData(
    0xe813,
    fontFamily: 'MerchantNavProducts',
  );

  static const IconData merchantNavProfile = IconData(
    0xe804,
    fontFamily: 'MerchantNavProfile',
  );
}
