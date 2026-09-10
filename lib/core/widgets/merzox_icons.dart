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
