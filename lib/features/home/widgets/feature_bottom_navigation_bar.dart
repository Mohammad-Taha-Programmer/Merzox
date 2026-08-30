import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/colors.dart';

/// The active-tab marker every Merzox bottom navigation bar draws.
///
/// Measured from the artboards, not chosen here: a 24x2 bar sitting above the
/// icon, never a disc behind it.
const double kMerzoxNavIndicatorWidth = 24;
const double kMerzoxNavIndicatorHeight = 2;
const double kMerzoxNavIndicatorGap = 13;

/// The marker itself, so the three bars cannot render it differently.
class MerzoxNavIndicator extends StatelessWidget {
  final bool selected;

  const MerzoxNavIndicator({super.key, required this.selected});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: kMerzoxNavIndicatorWidth,
      height: kMerzoxNavIndicatorHeight,
      decoration: BoxDecoration(
        color: selected ? MerzoxColors.kColorEE6C4D : Colors.transparent,
        borderRadius: BorderRadius.circular(kMerzoxNavIndicatorHeight),
      ),
    );
  }
}

class FeatureBottomNavigationBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const FeatureBottomNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 92,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            Positioned.fill(
              top: 22,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 22,
                      offset: const Offset(0, -7),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 0,
              child: Container(
                width: 86,
                height: 86,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 18,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
              ),
            ),
            Positioned.fill(
              top: 22,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  children: [
                    Expanded(
                      child: _NavButton(
                        label: 'nav.home'.tr(),
                        icon: Icons.home_outlined,
                        selectedIcon: Icons.home_rounded,
                        selected: selectedIndex == 0,
                        onTap: () => onChanged(0),
                      ),
                    ),
                    Expanded(
                      child: _NavButton(
                        label: 'nav.cart'.tr(),
                        icon: Icons.shopping_bag_outlined,
                        selectedIcon: Icons.shopping_bag_rounded,
                        selected: selectedIndex == 1,
                        onTap: () => onChanged(1),
                      ),
                    ),
                    const SizedBox(width: 92),
                    Expanded(
                      child: _NavButton(
                        label: 'nav.messages'.tr(),
                        icon: Icons.chat_bubble_outline_rounded,
                        selectedIcon: Icons.chat_bubble_rounded,
                        selected: selectedIndex == 3,
                        onTap: () => onChanged(3),
                      ),
                    ),
                    Expanded(
                      child: _NavButton(
                        label: 'nav.profile'.tr(),
                        icon: Icons.person_outline_rounded,
                        selectedIcon: Icons.person_rounded,
                        selected: selectedIndex == 4,
                        onTap: () => onChanged(4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 7,
              child: Semantics(
                button: true,
                selected: selectedIndex == 2,
                label: 'nav.stores'.tr(),
                child: InkResponse(
                  onTap: () => onChanged(2),
                  radius: 36,
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: MerzoxColors.kColorEE6C4D,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.16),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.storefront_outlined,
                      color: Colors.white,
                      size: 27,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool selected;
  final VoidCallback onTap;

  const _NavButton({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      selected: selected,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MerzoxNavIndicator(selected: selected),
              const SizedBox(height: kMerzoxNavIndicatorGap),
              Icon(
                selected ? selectedIcon : icon,
                color: selected
                    ? MerzoxColors.kColorEE6C4D
                    : MerzoxColors.kColor8D99AE,
                size: 25,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
