import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../constants/colors.dart';

/// Flips the app between Arabic and English.
///
/// The control lived inline on the profile screen and the home screen wanted
/// the same one, so the choice was to copy the locale flip or to share it.
/// Copying it means two places that can disagree about which languages the app
/// offers, so it lives here instead - beside the rest of the localization
/// plumbing rather than inside either screen.
class LanguageToggleButton extends StatelessWidget {
  final double? iconSize;
  final Color color;
  final EdgeInsetsGeometry padding;
  final BoxConstraints? constraints;

  const LanguageToggleButton({
    super.key,
    this.iconSize,
    this.color = MerzoxColors.kColor3D5A80,
    this.padding = const EdgeInsets.all(8),
    this.constraints,
  });

  /// The locale a tap moves to. Exposed so a test can state the pair without
  /// having to drive a real `EasyLocalization` tree.
  static Locale nextLocale(Locale current) {
    return current.languageCode == 'ar'
        ? const Locale('en')
        : const Locale('ar');
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'common.changeLanguage'.tr(),
      onPressed: () => context.setLocale(nextLocale(context.locale)),
      padding: padding,
      constraints: constraints,
      icon: Icon(Icons.language_rounded, size: iconSize, color: color),
    );
  }
}
