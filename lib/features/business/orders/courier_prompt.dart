import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Who is carrying this order, and on what number.
class CourierDetails {
  final String name;
  final String phone;

  const CourierDetails({required this.name, required this.phone});
}

/// Asks for a courier's name and number, and hands back what was written.
///
/// Returns null when the merchant backed out.
///
/// It exists for the same reason `askForOrderText` does, and the crash it
/// fixes is the same one: the caller used to make two
/// `TextEditingController`s, hand them to the fields inside `showDialog`, and
/// dispose them on the line after the `await`. `showDialog` returns the moment
/// the route is popped, not when it is gone - the box is still on screen fading
/// out, its fields still mounted and still holding those controllers. The
/// build of the dying box then touches a controller that no longer exists and
/// throws, which leaves the subtree half-updated, and when the overlay finally
/// drops the entry an inherited element still has dependents. The framework
/// raises `'_dependents.isEmpty': is not true`, which is the red screen a
/// merchant saw the instant they pressed save - several steps downstream of
/// the cause, and naming none of it.
///
/// The controllers belong to the box, and go when the box goes.
Future<CourierDetails?> askForCourier(
  BuildContext context, {
  required String initialName,
  required String initialPhone,
}) {
  return showDialog<CourierDetails>(
    context: context,
    builder: (BuildContext dialogContext) =>
        _CourierPrompt(initialName: initialName, initialPhone: initialPhone),
  );
}

class _CourierPrompt extends StatefulWidget {
  final String initialName;
  final String initialPhone;

  const _CourierPrompt({required this.initialName, required this.initialPhone});

  @override
  State<_CourierPrompt> createState() => _CourierPromptState();
}

class _CourierPromptState extends State<_CourierPrompt> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );

  late final TextEditingController _phone = TextEditingController(
    text: widget.initialPhone,
  );

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.of(
      context,
    ).pop(CourierDetails(name: _name.text.trim(), phone: _phone.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('merchantOrder.assignCourier'.tr()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            key: const ValueKey<String>('courierPrompt.name'),
            controller: _name,
            decoration: InputDecoration(
              labelText: 'merchantOrder.courierName'.tr(),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey<String>('courierPrompt.phone'),
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'merchantOrder.courierPhone'.tr(),
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          key: const ValueKey<String>('courierPrompt.dismiss'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(
          key: const ValueKey<String>('courierPrompt.confirm'),
          onPressed: _save,
          child: Text('common.save'.tr()),
        ),
      ],
    );
  }
}
