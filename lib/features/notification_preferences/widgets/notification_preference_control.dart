import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/features/notification_preferences/bloc/notification_preference_bloc.dart';
import 'package:merzox/features/notification_preferences/bloc/notification_preference_event.dart';
import 'package:merzox/features/notification_preferences/bloc/notification_preference_state.dart';

class NotificationPreferenceControl extends StatelessWidget {
  /// Which row this is. One control drives one preference, so it names it.
  final String labelKey;

  /// The two profile screens draw their rows to different boards, and this
  /// row has to sit in a line with the ones beside it on either.
  final double height;
  final double cornerRadius;
  final double gap;

  /// The glyph beside the words.
  ///
  /// A parameter because the two screens that draw this row are being moved
  /// onto the designer's own set one at a time, and the one still on
  /// Material's must not change under a conversion of the other. The default
  /// is what both drew before either moved.
  final IconData icon;

  /// How large to draw it, which is not the same question as how large it
  /// looks. A glyph fills as much of its em box as its designer chose to
  /// fill: the row icons on the customer profile fill all of theirs, this
  /// bell fills 0.834 of its, and Material's fills 0.75. Set to the same
  /// number they would all draw at different sizes, so the caller passes what
  /// makes this one match the rows beside it rather than what matches on
  /// paper.
  final double iconSize;

  /// The size of the words, which the screen sets for the same reason it sets
  /// the row's height: this row stands in a column of others and has to be
  /// set in the same type as they are.
  final double labelSize;

  const NotificationPreferenceControl({
    super.key,
    this.labelKey = 'notificationPreferences.productOffers',
    this.icon = Icons.notifications_none_rounded,
    this.iconSize = 18,
    this.labelSize = 12,
    this.height = 38,
    this.cornerRadius = 4,
    this.gap = 10,
  });

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<
      NotificationPreferenceBloc,
      NotificationPreferenceState
    >(
      listenWhen: (previous, current) =>
          previous.errorMessage != current.errorMessage &&
          current.errorMessage.isNotEmpty &&
          current.productOffers != null,
      listener: (context, state) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(state.errorMessage.tr())));
      },
      builder: (context, state) {
        return Container(
          height: height,
          margin: EdgeInsets.only(bottom: gap),
          decoration: BoxDecoration(
            color: MerzoxColors.kColorF5F9FC,
            borderRadius: BorderRadius.circular(cornerRadius),
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 10, end: 12),
            child: Row(
              children: [
                Icon(icon, color: MerzoxColors.kColor3D5A80, size: iconSize),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    labelKey.tr(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: labelSize,
                      color: const Color(0xFF2B2B2B),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _leadingControl(context, state),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _leadingControl(
    BuildContext context,
    NotificationPreferenceState state,
  ) {
    if (state.status == NotificationPreferenceStatus.loading ||
        state.status == NotificationPreferenceStatus.initial) {
      return const SizedBox(
        width: 34,
        height: 34,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (state.status == NotificationPreferenceStatus.failure ||
        state.productOffers == null) {
      return TextButton(
        onPressed: () {
          context.read<NotificationPreferenceBloc>().add(
            const NotificationPreferenceRetryRequested(),
          );
        },
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          minimumSize: const Size(0, 32),
        ),
        child: Text('common.retry'.tr(), style: const TextStyle(fontSize: 10)),
      );
    }

    return Transform.scale(
      scale: 0.72,
      child: Switch(
        value: state.productOffers!,
        activeThumbColor: Colors.white,
        activeTrackColor: MerzoxColors.kColorEE6C4D,
        inactiveThumbColor: Colors.white,
        inactiveTrackColor: MerzoxColors.kColorC7C7C7,
        onChanged: state.status == NotificationPreferenceStatus.saving
            ? null
            : (value) {
                context.read<NotificationPreferenceBloc>().add(
                  NotificationPreferenceChanged(value),
                );
              },
      ),
    );
  }
}
