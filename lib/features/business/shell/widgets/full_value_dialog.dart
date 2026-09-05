import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';

/// How long a shown value stays up before it takes itself away.
const Duration merchantFullValueDuration = Duration(seconds: 3);

/// Shows a value the table had to cut short.
///
/// Five columns on a phone means text gets clipped, and clipped text is worse
/// than blank: `تم التسل...` looks like data and is not. Every value in a row
/// that can be cut - the status badge included, which is 58 wide and cuts the
/// longest statuses - hands its full text over on a tap, and they all come
/// here so a merchant meets the same box wherever they tap.
///
/// It carries no heading and no button. A merchant who tapped a word to read
/// it does not need to be told they are looking at the word, and does not need
/// to dismiss it: the box goes away by itself. Tapping outside still closes it
/// early, for a reader who is already done.
Future<void> showMerchantFullValue(BuildContext context, String value) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) => _TransientValue(value: value),
  );
}

class _TransientValue extends StatefulWidget {
  final String value;

  const _TransientValue({required this.value});

  @override
  State<_TransientValue> createState() => _TransientValueState();
}

class _TransientValueState extends State<_TransientValue> {
  Timer? _closing;

  @override
  void initState() {
    super.initState();
    _closing = Timer(merchantFullValueDuration, () {
      // The reader may have closed it already, or navigated away, so the pop
      // is guarded rather than assumed.
      if (!mounted) return;
      Navigator.of(context).maybePop();
    });
  }

  @override
  void dispose() {
    _closing?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Text(
          widget.value,
          key: const ValueKey<String>('merchantOrders.fullValue'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 15,
            color: MerzoxColors.kColor2B2B2B,
          ),
        ),
      ),
    );
  }
}
