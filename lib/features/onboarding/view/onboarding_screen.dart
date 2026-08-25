import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/features/onboarding/bloc/onboarding_bloc.dart';
import 'package:merzox/features/onboarding/bloc/onboarding_event.dart';
import 'package:merzox/features/onboarding/bloc/onboarding_state.dart';
import 'package:merzox/features/onboarding/view/onboarding_page.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onFinished;

  const OnboardingScreen({super.key, required this.onFinished});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const int _pageCount = 3;
  static const int _lastPage = _pageCount - 1;

  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _finish(OnboardingBloc bloc) {
    bloc.add(SkipOnboarding());
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: Directionality.of(context),
      child: BlocConsumer<OnboardingBloc, OnboardingState>(
        listener: (context, state) {
          if (state.isCompleted) {
            widget.onFinished();
          }
        },
        builder: (context, state) {
          final bloc = context.read<OnboardingBloc>();

          return Scaffold(
            backgroundColor: Colors.white,
            body: SafeArea(
              child: Column(
                children: [
                  SizedBox(
                    height: 48,
                    child: state.currentPage == _lastPage
                        ? null
                        : Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: () => _finish(bloc),
                              child: Text(
                                'onboarding.skip'.tr(),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: MerzoxColors.kColor3B3B3B,
                                ),
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(height: 48),
                  Expanded(
                    flex: 7,
                    child: PageView(
                      controller: _pageController,
                      onPageChanged: (page) => bloc.add(NextPage(page)),
                      children: [
                        OnboardingPage(
                          imagePath: 'assets/images/Onboarding/onboarding1.png',
                          title: 'onboarding.page1Title'.tr(),
                          subtitle: 'onboarding.page1Subtitle'.tr(),
                        ),
                        OnboardingPage(
                          imagePath: 'assets/images/Onboarding/onboarding2.png',
                          title: 'onboarding.page2Title'.tr(),
                          subtitle: 'onboarding.page2Subtitle'.tr(),
                        ),
                        OnboardingPage(
                          imagePath: 'assets/images/Onboarding/onboarding3.png',
                          title: 'onboarding.page3Title'.tr(),
                          subtitle: 'onboarding.page3Subtitle'.tr(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_pageCount, (index) {
                      final isActive = index == state.currentPage;

                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: isActive ? 22 : 10,
                        height: 10,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: MerzoxColors.kColor98C1D9),
                          color: isActive
                              ? MerzoxColors.kColor3D5A80
                              : Colors.transparent,
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 36),
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        height: 72,
                        width: 72,
                        child: CircularProgressIndicator(
                          value: (state.currentPage + 1) / _pageCount,
                          strokeWidth: 3,
                          valueColor: const AlwaysStoppedAnimation(
                            MerzoxColors.kColor3D5A80,
                          ),
                          backgroundColor: MerzoxColors.kColorFEE3DC,
                        ),
                      ),
                      SizedBox(
                        width: 58,
                        height: 58,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            shape: const CircleBorder(),
                            padding: EdgeInsets.zero,
                            backgroundColor: MerzoxColors.kColorEE6C4D,
                          ),
                          onPressed: () {
                            if (state.currentPage == _lastPage) {
                              _finish(bloc);
                              return;
                            }

                            _pageController.nextPage(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOut,
                            );
                          },
                          child: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 72),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
