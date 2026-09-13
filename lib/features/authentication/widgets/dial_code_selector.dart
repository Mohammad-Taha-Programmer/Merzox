import 'package:flutter/material.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/core/widgets/merzox_icons.dart';

/// The country half of a phone field, and the list it offers.
///
/// Both screens that ask for a phone number draw this, which is the point of
/// it being here: the two were separate copies of the same idea, with their
/// own list, their own default and their own arrangement, and they had already
/// drifted into two different-looking fields for the same question. Shared,
/// they cannot drift again.
///
/// What each screen still owns is the box it lives in - how tall it is and
/// what colour its border is - because that belongs to the screen's own set of
/// fields and not to this.

/// One country: the flag a reader recognises and the code that is sent.
class DialCode {
  final String flag;
  final String prefix;

  const DialCode({required this.flag, required this.prefix});
}

/// The country the list opens on.
///
/// A default is a guess about who is signing in, and the guess is the reader
/// Merzox is for. Anyone it guesses wrong about changes it in one tap.
const String kDefaultDialPrefix = '+970';

const List<DialCode> kDialCodes = <DialCode>[
  DialCode(flag: '🇵🇸', prefix: '+970'),
  DialCode(flag: '🇮🇱', prefix: '+972'),
  DialCode(flag: '🇯🇴', prefix: '+962'),
  DialCode(flag: '🇪🇬', prefix: '+20'),
  DialCode(flag: '🇸🇦', prefix: '+966'),
  DialCode(flag: '🇦🇪', prefix: '+971'),
  DialCode(flag: '🇺🇸', prefix: '+1'),
];

/// The country the two screens start on.
DialCode get defaultDialCode =>
    kDialCodes.firstWhere((DialCode code) => code.prefix == kDefaultDialPrefix);

/// The block's outer inset, the gap between it and its line, and the line.
///
/// The outer inset matches the fields' own `contentPadding`, so the dial code
/// starts where text on the other side of the line would.
const double _kOuterInset = 14;
const double _kToLine = 12;
const double _kLineWidth = 1;
const double _kFlagToChevron = 6;

/// The country, the flag and the chevron, with a line dividing them from the
/// number.
class DialCodeSelector extends StatelessWidget {
  final DialCode value;
  final ValueChanged<DialCode?> onChanged;

  /// The height of the field this sits inside, which the line runs the whole
  /// of.
  final double fieldHeight;

  /// The field's own border colour, so the line reads as part of the box
  /// rather than as something laid over it.
  final Color lineColor;

  final Key? lineKey;

  const DialCodeSelector({
    super.key,
    required this.value,
    required this.onChanged,
    required this.fieldHeight,
    required this.lineColor,
    this.lineKey,
  });

  @override
  Widget build(BuildContext context) {
    // Left to right whatever the page around it is doing. A dial code is a
    // left-to-right thing wherever it sits, and the order - the code, then the
    // flag, then the chevron - is that order on the glass and not a
    // start-to-end one that would turn round with the language.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: _kOuterInset, right: _kToLine),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<DialCode>(
                value: value,
                isDense: true,
                menuMaxHeight: 300,
                dropdownColor: Colors.white,
                onChanged: onChanged,
                // Material sets the icon hard against the chip; the chevron is
                // a mark about the list rather than part of the reading of the
                // flag, so it is given air of its own.
                icon: const Padding(
                  padding: EdgeInsets.only(left: _kFlagToChevron),
                  child: Icon(
                    MerzoxIcons.authCountryChevron,
                    color: MerzoxColors.kColor3D5A80,
                    // The size Material's triangle drew at, converted.
                    size: 18 * MerzoxIcons.countryChevronSizeFactor,
                  ),
                ),
                selectedItemBuilder: (BuildContext context) {
                  return kDialCodes
                      .map((DialCode code) => _DialCodeView(code: code))
                      .toList();
                },
                items: kDialCodes.map((DialCode code) {
                  return DropdownMenuItem<DialCode>(
                    value: code,
                    child: _DialCodeView(code: code),
                  );
                }).toList(),
              ),
            ),
          ),
          // The two halves of the box, told apart. Full height, so it reads as
          // a division of the field rather than a mark floating inside it.
          Container(
            key: lineKey,
            width: _kLineWidth,
            height: fieldHeight,
            color: lineColor,
          ),
        ],
      ),
    );
  }
}

class _DialCodeView extends StatelessWidget {
  final DialCode code;

  const _DialCodeView({required this.code});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      textDirection: TextDirection.ltr,
      children: <Widget>[
        Text(
          code.prefix,
          textDirection: TextDirection.ltr,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: MerzoxColors.kColor2B2B2B,
          ),
        ),
        const SizedBox(width: 6),
        Text(code.flag, style: const TextStyle(fontSize: 16)),
      ],
    );
  }
}
