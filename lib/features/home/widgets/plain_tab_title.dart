import 'package:flutter/material.dart';

/// The centred heading a tab wears when it has no search field above it.
///
/// Shared rather than duplicated: the cart tab moved out of `home_screen` and
/// took this with it, and the tab left behind uses the very same heading.
class PlainTabTitle extends StatelessWidget {
  final String title;

  const PlainTabTitle({required this.title, super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Center(
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: Color(0xFF2B2B2B),
          ),
        ),
      ),
    );
  }
}
