import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/features/recommendation_preferences/bloc/recommendation_preference_bloc.dart';
import 'package:merzox/features/recommendation_preferences/bloc/recommendation_preference_event.dart';
import 'package:merzox/features/recommendation_preferences/bloc/recommendation_preference_state.dart';

class RecommendationPreferenceControl extends StatelessWidget {
  const RecommendationPreferenceControl({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<
      RecommendationPreferenceBloc,
      RecommendationPreferenceState
    >(
      listenWhen: (previous, current) =>
          previous.errorMessage != current.errorMessage &&
          current.errorMessage.isNotEmpty &&
          current.enabled != null,
      listener: (context, state) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(state.errorMessage.tr())));
      },
      builder: (context, state) {
        return Container(
          constraints: const BoxConstraints(minHeight: 48),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: MerzoxColors.kColorF5F9FC,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.only(
              start: 10,
              end: 12,
              top: 5,
              bottom: 5,
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.auto_awesome_outlined,
                  color: MerzoxColors.kColor3D5A80,
                  size: 18,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'recommendationPreferences.personalization'.tr(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF2B2B2B),
                        ),
                      ),
                      Text(
                        'recommendationPreferences.description'.tr(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9,
                          height: 1.2,
                          color: MerzoxColors.kColor767676,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _control(context, state),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _control(BuildContext context, RecommendationPreferenceState state) {
    if (state.status == RecommendationPreferenceStatus.loading ||
        state.status == RecommendationPreferenceStatus.initial) {
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

    if (state.status == RecommendationPreferenceStatus.failure ||
        state.enabled == null) {
      return TextButton(
        onPressed: () {
          context.read<RecommendationPreferenceBloc>().add(
            const RecommendationPreferenceRetryRequested(),
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
        value: state.enabled!,
        activeThumbColor: Colors.white,
        activeTrackColor: MerzoxColors.kColorEE6C4D,
        inactiveThumbColor: Colors.white,
        inactiveTrackColor: MerzoxColors.kColorC7C7C7,
        onChanged: state.status == RecommendationPreferenceStatus.saving
            ? null
            : (value) {
                context.read<RecommendationPreferenceBloc>().add(
                  RecommendationPreferenceChanged(value),
                );
              },
      ),
    );
  }
}
