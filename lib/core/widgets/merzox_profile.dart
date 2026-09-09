import 'package:flutter/material.dart';

import 'package:merzox/core/constants/colors.dart';

/// The two profile screens, which are one board drawn twice.
///
/// The merchant's and the customer's differ in what their rows say and which
/// glyph stands beside each - nothing else. They were built separately all the
/// same, and the customer's drifted: rows 10 shorter, corners 2 tighter, words
/// a point smaller, and a menu laid out by hand rather than by the reading, so
/// in Arabic its icon and its chevron stood on the wrong sides of the row and
/// the chevron pointed back at the words it was meant to lead away from.
///
/// So the board lives here once and both screens draw from it.

/// The board's own measurements.
const double kProfileFieldHeight = 290;
const double kProfileSheetTop = 113;
const double kProfileSheetRadius = 20;
const double kProfileGutter = 16;
const double kProfileRowHeight = 48;
const double kProfileRowRadius = 6;
const double kProfileRowGap = 16;
const double kProfileAvatarDiameter = 37;
const double kProfileAvatarRing = 5;

/// The size a row's words are set in.
///
/// Named because two of the rows on the customer profile are not
/// [MerzoxProfileMenuRow] at all - the two preference switches are their own
/// widgets, shared with another screen - and they have to be told this rather
/// than happening to agree with it. They did not: they were set a point
/// smaller, and stood out among rows that were otherwise identical.
const double kProfileRowLabelSize = 13;

/// The band the title sits in, under the status bar.
const double kProfileTitleBand = 44;

/// The strip of blue between the title and the sheet.
///
/// The board leaves 25 here, which put the sheet's edge at 113. Widened on the
/// reader's eye: they wanted more blue above the picture than the board gives,
/// and the numbers below it keep the board's own spacing rather than being
/// squeezed to hold the rows at their original marks.
const double kProfileSheetGap = 45;

/// A whole profile screen: the blue field, the title, and the white sheet
/// everything else stands on.
///
/// Drawn as one scrolling list so a taller system font or a shorter phone
/// moves the sheet rather than clipping it.
class MerzoxProfileScaffold extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const MerzoxProfileScaffold({
    super.key,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Container(
          height: kProfileFieldHeight,
          width: double.infinity,
          color: MerzoxColors.kColor98C1D9,
        ),
        ListView(
          // No inset for the bottom bar. A `Scaffold` with a
          // `bottomNavigationBar` already ends its body above the bar - the
          // raised button's overhang included, since the bar reports that as
          // part of its own height - so room kept here is room kept twice,
          // and it showed as 122px of nothing under the last control.
          padding: EdgeInsets.zero,
          children: <Widget>[
            MerzoxProfileHeader(title: title),
            MerzoxProfileSheet(children: children),
          ],
        ),
      ],
    );
  }
}

/// The blue field's title, and the strip of blue under it that the sheet is
/// lifted onto.
class MerzoxProfileHeader extends StatelessWidget {
  final String title;

  const MerzoxProfileHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        // The blue field runs behind the status bar on the board, so the title
        // sits under whatever the device reserves there rather than at a fixed
        // offset from the top of the app.
        SizedBox(
          height: kProfileTitleBand,
          width: double.infinity,
          child: Center(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: kProfileSheetGap),
      ],
    );
  }
}

/// The white sheet the menu sits on, lifted onto the blue field.
class MerzoxProfileSheet extends StatelessWidget {
  final List<Widget> children;

  const MerzoxProfileSheet({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(kProfileSheetRadius),
        ),
      ),
      child: Column(children: children),
    );
  }
}

/// The picture, ringed in the field's own blue.
///
/// Neither screen has a photograph for everyone - a shop may have no logo and
/// an account has no picture stored at all - so the fallback is the first
/// letter of whatever the name is, which at least differs between people.
class MerzoxProfileAvatar extends StatelessWidget {
  final Widget child;

  const MerzoxProfileAvatar({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(kProfileAvatarRing),
      decoration: const BoxDecoration(
        color: MerzoxColors.kColor98C1D9,
        shape: BoxShape.circle,
      ),
      child: child,
    );
  }
}

/// One row of a profile menu.
///
/// Two board rules, and both were broken on one screen or the other before
/// this was shared. The icon stands at the READING edge with the words beside
/// it - which in Arabic is the right - and it is a plain [Row], so the reading
/// decides that rather than a hand-written order that only looks right in one
/// language. The chevron stands alone at the far end and is named for where
/// the row goes, not for where the glyph points: `chevron_right` carries
/// `matchTextDirection`, so Material leans it left for an Arabic reading, as
/// the board draws it. Naming the left one instead turns it a second time and
/// leaves it pointing back at the words.
class MerzoxProfileMenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// The board keeps the chevron for the rows that open a screen with more of
  /// the same behind it, and drops it from the ones that do a single thing.
  final bool showChevron;

  const MerzoxProfileMenuRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.showChevron = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        kProfileGutter,
        0,
        kProfileGutter,
        kProfileRowGap,
      ),
      child: Material(
        color: MerzoxColors.kColorF5F9FC,
        borderRadius: BorderRadius.circular(kProfileRowRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(kProfileRowRadius),
          child: Container(
            // A floor, not a fixed height: a reader who turns the system font
            // up needs the row to grow rather than clip.
            constraints: const BoxConstraints(minHeight: kProfileRowHeight),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: <Widget>[
                Icon(icon, size: 20, color: MerzoxColors.kColor3D5A80),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: kProfileRowLabelSize,
                      color: MerzoxColors.kColor2B2B2B,
                    ),
                  ),
                ),
                if (showChevron)
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: MerzoxColors.kColor3D5A80,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A pill the board draws rather than a row: the one that signs out, and the
/// one that turns the reader into the other kind of user.
class MerzoxProfilePill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final double width;

  /// Filled for the one that changes who you are, quiet for signing out.
  final bool prominent;

  const MerzoxProfilePill({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.width = 162,
    this.prominent = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color foreground = prominent
        ? Colors.white
        : MerzoxColors.kColor3D5A80;

    return Center(
      child: Material(
        color: prominent
            ? MerzoxColors.kColor3D5A80
            : MerzoxColors.kColorF5F9FC,
        borderRadius: BorderRadius.circular(kProfileRowRadius),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(kProfileRowRadius),
          child: Container(
            width: width,
            constraints: const BoxConstraints(minHeight: kProfileRowHeight),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(icon, size: 20, color: foreground),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: prominent ? 14 : 13,
                      fontWeight: prominent
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: prominent ? Colors.white : const Color(0xFF292828),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
