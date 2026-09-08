import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:merzox/core/widgets/merzox_nav_icons.dart';
import 'package:merzox/core/widgets/merzox_notched_nav_bar.dart';

/// The marker and its measurements live in core now, beside the bar that
/// draws them. Re-exported so the screens that already import them from here
/// keep reading them from the place they always did.
export 'package:merzox/core/widgets/merzox_notched_nav_bar.dart'
    show
        MerzoxNavIndicator,
        kMerzoxNavIndicatorGap,
        kMerzoxNavIndicatorHeight,
        kMerzoxNavIndicatorWidth;

/// The customer's bottom bar.
///
/// Every screen a customer can reach draws this one, so the shape, the bite
/// and the button in it are described once - in [MerzoxNotchedNavBar] - and
/// this says only which five places the bar leads to.
class FeatureBottomNavigationBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  /// Hangs the waiting-conversation count on the messages glyph. Absent on
  /// the screens that do not carry the counter.
  final Widget Function(Widget glyph)? decorateMessages;

  const FeatureBottomNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onChanged,
    this.decorateMessages,
  });

  @override
  Widget build(BuildContext context) {
    return MerzoxNotchedNavBar(
      leading: <MerzoxNavDestination>[
        MerzoxNavDestination(
          glyph: MerzoxNavGlyph.home,
          label: 'nav.home'.tr(),
          selected: selectedIndex == 0,
          onTap: () => onChanged(0),
        ),
        MerzoxNavDestination(
          glyph: MerzoxNavGlyph.cart,
          label: 'nav.cart'.tr(),
          selected: selectedIndex == 1,
          onTap: () => onChanged(1),
        ),
      ],
      trailing: <MerzoxNavDestination>[
        MerzoxNavDestination(
          glyph: MerzoxNavGlyph.messages,
          label: 'nav.messages'.tr(),
          selected: selectedIndex == 3,
          onTap: () => onChanged(3),
          decorate: decorateMessages,
        ),
        MerzoxNavDestination(
          glyph: MerzoxNavGlyph.profile,
          label: 'nav.profile'.tr(),
          selected: selectedIndex == 4,
          onTap: () => onChanged(4),
        ),
      ],
      buttonGlyph: MerzoxNavGlyph.storefront,
      buttonLabel: 'nav.stores'.tr(),
      buttonSelected: selectedIndex == 2,
      onButtonPressed: () => onChanged(2),
    );
  }
}
