import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/colors.dart';
import '../../../services/api_service.dart';
import '../bloc/about_us_bloc.dart';
import '../bloc/about_us_event.dart';
import '../bloc/about_us_state.dart';

class AboutUsPage extends StatefulWidget {
  const AboutUsPage({super.key});

  @override
  State<AboutUsPage> createState() => _AboutUsPageState();
}

class _AboutUsPageState extends State<AboutUsPage> {
  String? _requestedLanguageCode;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final languageCode = context.locale.languageCode == 'en' ? 'en' : 'ar';
    if (_requestedLanguageCode == languageCode) return;

    _requestedLanguageCode = languageCode;
    context.read<AboutUsBloc>().add(AboutUsStarted(languageCode));
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AboutUsBloc, AboutUsState>(
      builder: (context, state) {
        final title =
            state.status == AboutUsStatus.ready &&
                state.content?.pageTitle.isNotEmpty == true
            ? state.content!.pageTitle
            : 'aboutUs.title'.tr();

        return Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: Column(
              children: [
                _AboutUsHeader(title: title),
                Expanded(child: _buildContent(state)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildContent(AboutUsState state) {
    if (state.status == AboutUsStatus.initial ||
        state.status == AboutUsStatus.loading) {
      return const Center(
        child: CircularProgressIndicator(color: MerzoxColors.kColor3D5A80),
      );
    }

    if (state.status == AboutUsStatus.failure || state.content == null) {
      return _AboutUsFailure(
        onRetry: () =>
            context.read<AboutUsBloc>().add(const AboutUsRefreshRequested()),
      );
    }

    final content = state.content!;
    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 21, 20, 28),
      children: [
        _AboutIntroduction(content: content),
        const SizedBox(height: 44),
        if (content.sections.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 42),
            child: Text(
              'aboutUs.empty'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MerzoxColors.kColor707070,
                fontSize: 13,
              ),
            ),
          )
        else
          for (var index = 0; index < content.sections.length; index++) ...[
            _AboutAccordion(
              section: content.sections[index],
              expanded: state.expandedSectionKeys.contains(
                content.sections[index].key,
              ),
              onPressed: () => context.read<AboutUsBloc>().add(
                AboutUsSectionToggled(content.sections[index].key),
              ),
            ),
            if (index != content.sections.length - 1)
              const SizedBox(height: 12),
          ],
      ],
    );
  }
}

class _AboutUsHeader extends StatelessWidget {
  final String title;

  const _AboutUsHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      // Measured against the artboard's title band (y=64..76).
      height: 65,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: MerzoxColors.kColor2B2B2B,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const PositionedDirectional(
            start: 8,
            child: BackButton(color: MerzoxColors.kColor5E5E5E),
          ),
        ],
      ),
    );
  }
}

class _AboutIntroduction extends StatelessWidget {
  final AboutUsApiModel content;

  const _AboutIntroduction({required this.content});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: content.appLabel),
              const TextSpan(text: '  '),
              TextSpan(text: content.appName),
            ],
          ),
          textAlign: TextAlign.start,
          style: const TextStyle(
            color: MerzoxColors.kColor2B2B2B,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          content.introduction,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: MerzoxColors.kColor3B3B3B,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            height: 1.85,
          ),
        ),
      ],
    );
  }
}

class _AboutAccordion extends StatelessWidget {
  final AboutUsSectionApiModel section;
  final bool expanded;
  final VoidCallback onPressed;

  const _AboutAccordion({
    required this.section,
    required this.expanded,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      expanded: expanded,
      label: section.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: MerzoxColors.kColorF5F9FC,
            borderRadius: BorderRadius.circular(4),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          section.title,
                          style: const TextStyle(
                            color: MerzoxColors.kColor2B2B2B,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      AnimatedRotation(
                        turns: expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        child: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 19,
                          color: MerzoxColors.kColor3D5A80,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          ClipRect(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: expanded
                  ? Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        16,
                        14,
                        16,
                        16,
                      ),
                      decoration: const BoxDecoration(
                        color: MerzoxColors.kColorF9F9F9,
                        borderRadius: BorderRadius.vertical(
                          bottom: Radius.circular(4),
                        ),
                      ),
                      child: Text(
                        section.content,
                        style: const TextStyle(
                          color: MerzoxColors.kColor464646,
                          fontSize: 13,
                          height: 1.75,
                        ),
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutUsFailure extends StatelessWidget {
  final VoidCallback onRetry;

  const _AboutUsFailure({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.info_outline_rounded,
              color: MerzoxColors.kColor3D5A80,
              size: 46,
            ),
            const SizedBox(height: 14),
            Text(
              'aboutUs.loadError'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MerzoxColors.kColor464646,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 18),
            OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                foregroundColor: MerzoxColors.kColor3D5A80,
                side: const BorderSide(color: MerzoxColors.kColor3D5A80),
              ),
              child: Text('common.retry'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}
