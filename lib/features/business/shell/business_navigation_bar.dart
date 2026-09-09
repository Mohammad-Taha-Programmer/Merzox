import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:merzox/core/widgets/merzox_icons.dart';
import 'package:merzox/core/widgets/merzox_notched_nav_bar.dart';

/// The merchant's bottom bar, with the add-a-product button raised out of it.
///
/// Public and on its own because `إضافة منتجات` draws the same bar under the
/// product form: the artboards put that form inside the shell, with the list
/// scrolling behind the bar rather than replacing it.
///
/// The shape is [MerzoxNotchedNavBar]'s, the same one the customer's bar
/// draws. Only the five places differ, and the glyph in the button.
class BusinessNavigationBar extends StatelessWidget {
  /// Which tab reads as current. Index 2 is the raised button.
  final int selectedIndex;

  final ValueChanged<int> onChanged;

  const BusinessNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return MerzoxNotchedNavBar(
      leading: <MerzoxNavDestination>[
        MerzoxNavDestination(
          glyph: MerzoxIcons.merchantNavHome,
          label: 'nav.home'.tr(),
          selected: selectedIndex == 0,
          onTap: () => onChanged(0),
        ),
        MerzoxNavDestination(
          glyph: MerzoxIcons.merchantNavOrders,
          label: 'businessShell.orders'.tr(),
          selected: selectedIndex == 1,
          onTap: () => onChanged(1),
        ),
      ],
      trailing: <MerzoxNavDestination>[
        MerzoxNavDestination(
          glyph: MerzoxIcons.merchantNavProducts,
          label: 'businessShell.productsHeading'.tr(),
          selected: selectedIndex == 3,
          onTap: () => onChanged(3),
        ),
        MerzoxNavDestination(
          glyph: MerzoxIcons.merchantNavProfile,
          label: 'nav.profile'.tr(),
          selected: selectedIndex == 4,
          onTap: () => onChanged(4),
        ),
      ],
      buttonGlyph: MerzoxIcons.merchantNavAddProduct,
      buttonLabel: 'businessShell.addProduct'.tr(),
      buttonSelected: selectedIndex == 2,
      onButtonPressed: () => onChanged(2),
    );
  }
}
