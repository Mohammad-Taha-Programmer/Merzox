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
}
