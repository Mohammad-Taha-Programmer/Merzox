import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/features/notification_preferences/bloc/notification_preference_bloc.dart';
import 'package:merzox/features/notification_preferences/bloc/notification_preference_event.dart';
import 'package:merzox/features/notification_preferences/bloc/notification_preference_state.dart';

class NotificationPreferenceControl extends StatelessWidget {
  const NotificationPreferenceControl({super.key});

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
          ..showSnackBar(SnackBar(content: Text(state.errorMessage)));
      },
      builder: (context, state) {
        return Container(
          height: 38,
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: MerzoxColors.kColorF5F9FC,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 10, end: 12),
            child: Row(
              children: [
                _leadingControl(context, state),
                const Spacer(),
                const Text(
                  'تنبيهات المنتجات والعروض',
                  style: TextStyle(fontSize: 12, color: Color(0xFF2B2B2B)),
                ),
                const SizedBox(width: 12),
                const Icon(
                  Icons.notifications_none_rounded,
                  color: MerzoxColors.kColor3D5A80,
                  size: 18,
                ),
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
        child: const Text('إعادة المحاولة', style: TextStyle(fontSize: 10)),
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
