import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';

import '../../../core/constants/colors.dart';

/// The count and the two arrows that walk between occurrences.
///
/// It stands at the reading edge of the thread, clear of both the bubbles and
/// the notification bell at the far corner. Without it a phrase said nine
/// times would open at the first and leave the other eight unreachable except
/// by scrolling and reading.
///
/// Shown only when there is more than one place to stand: a single result
/// needs no counter, and two arrows that would only ever return to where the
/// reader already is are worse than nothing.
class MatchNavigator extends StatelessWidget {
  /// Which occurrence is showing, counted from one for the reader.
  final int current;

  final int total;

  /// Forward through the conversation, in the direction it was written.
  final VoidCallback onNext;

  final VoidCallback onPrevious;

  const MatchNavigator({
    required this.current,
    required this.total,
    required this.onNext,
    required this.onPrevious,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 2,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(kMatchNavigatorRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'messages.matchPosition'.tr(
                namedArgs: <String, String>{
                  'current': '${current + 1}',
                  'total': '$total',
                },
              ),
              key: const ValueKey<String>('merzox.chat.matchCounter'),
              style: const TextStyle(
                fontFamily: 'Tajawal',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: MerzoxColors.kColor3D5A80,
              ),
            ),
            const SizedBox(height: 4),
            _Step(
              // Back towards the start of the conversation.
              icon: Icons.keyboard_arrow_up_rounded,
              label: 'messages.matchPrevious'.tr(),
              valueKey: 'merzox.chat.matchPrevious',
              onTap: onPrevious,
            ),
            _Step(
              icon: Icons.keyboard_arrow_down_rounded,
              label: 'messages.matchNext'.tr(),
              valueKey: 'merzox.chat.matchNext',
              onTap: onNext,
            ),
          ],
        ),
      ),
    );
  }
}

const double kMatchNavigatorRadius = 18;

/// Where the navigator sits from the reading edge and the bottom of the thread.
const double kMatchNavigatorInset = 10;

class _Step extends StatelessWidget {
  final IconData icon;
  final String label;
  final String valueKey;
  final VoidCallback onTap;

  const _Step({
    required this.icon,
    required this.label,
    required this.valueKey,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        key: ValueKey<String>(valueKey),
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 28,
          height: 26,
          child: Icon(icon, size: 20, color: MerzoxColors.kColor3D5A80),
        ),
      ),
    );
  }
}
