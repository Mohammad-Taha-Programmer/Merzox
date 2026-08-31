import 'package:flutter/material.dart';
import 'package:merzox/core/constants/colors.dart';

/// The merchant's bottom bar, with the add-a-product button raised out of it.
///
/// Public and on its own because `إضافة منتجات` draws the same bar under the
/// product form: the artboards put that form inside the shell, with the list
/// scrolling behind the bar rather than replacing it.
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
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SizedBox(
      height: 82,
      child: Stack(
        alignment: Alignment.topCenter,
        clipBehavior: Clip.none,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 14),
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Color(0x18000000),
                  blurRadius: 14,
                  offset: Offset(0, -4),
                ),
              ],
            ),
            child: Row(
              children: [
                _nav(Icons.home_outlined, Icons.home_rounded, 0),
                _nav(
                  Icons.receipt_long_outlined,
                  Icons.receipt_long_rounded,
                  1,
                ),
                const SizedBox(width: 72),
                _nav(Icons.inventory_2_outlined, Icons.inventory_2_rounded, 3),
                _nav(Icons.person_outline_rounded, Icons.person_rounded, 4),
              ],
            ),
          ),
          Positioned(
            top: -4,
            child: InkWell(
              onTap: () => onChanged(2),
              customBorder: const CircleBorder(),
              child: Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: MerzoxColors.kColorEE6C4D,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 5),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x30000000),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.add_rounded,
                  size: 30,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _nav(IconData icon, IconData selectedIcon, int index) => Expanded(
    child: InkWell(
      onTap: () => onChanged(index),
      child: Center(
        child: Icon(
          selectedIndex == index ? selectedIcon : icon,
          color: selectedIndex == index
              ? MerzoxColors.kColorEE6C4D
              : MerzoxColors.kColor8D99AE,
        ),
      ),
    ),
  );
}
