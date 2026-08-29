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

  // Every constant below is an Adobe XD *application-space* coordinate inside
  // the `OnboardingPage.designWidth` x `OnboardingPage.designHeight` canvas.
  // The operating-system chrome the XD artboard reserves is deliberately not
  // reproduced in Flutter, so these are canvas coordinates, never screen ones.

  static const double _skipLeft = 16.0;
  static const double _skipBaseline = 32.0;
  static const double _skipFontSize = 12.0;

  static const double _indicatorTop = 538.0;
  static const double _indicatorHeight = 8.0;
  static const double _activeIndicatorWidth = 18.0;
  static const double _inactiveIndicatorWidth = 8.0;
  static const double _indicatorSpacing = 8.0;

  static const double _nextButtonDiameter = 40.0;
  static const double _nextButtonCenterX = 188.0;
  static const double _nextButtonCenterY = 629.0;
  static const double _nextButtonIconSize = 16.0;

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

  void _advance(OnboardingBloc bloc, int currentPage) {
    if (currentPage == _lastPage) {
      _finish(bloc);
      return;
    }

    _pageController.nextPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  Widget _buildSkip(OnboardingBloc bloc) {
    return Positioned(
      left: _skipLeft,
      top: 0.0,
      child: Baseline(
        baseline: _skipBaseline,
        baselineType: TextBaseline.alphabetic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _finish(bloc),
          child: Text(
            'onboarding.skip'.tr(),
            style: const TextStyle(
              fontSize: _skipFontSize,
              color: MerzoxColors.kColor3B3B3B,
            ),
          ),
        ),
      ),
    );
  }

  /// The dot row, centered on the canvas.
  ///
  /// The `Row` reads the ambient direction, so the Arabic reference keeps its
  /// right-to-left dot order without any manual index flipping.
  Widget _buildIndicators(int currentPage) {
    return Positioned(
      top: _indicatorTop,
      left: 0.0,
      right: 0.0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_pageCount, (index) {
          final isActive = index == currentPage;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(
              horizontal: _indicatorSpacing / 2,
            ),
            width: isActive ? _activeIndicatorWidth : _inactiveIndicatorWidth,
            height: _indicatorHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_indicatorHeight),
              border: Border.all(color: MerzoxColors.kColor98C1D9),
              color: isActive ? MerzoxColors.kColor3D5A80 : Colors.transparent,
            ),
          );
        }),
      ),
    );
  }

  Widget _buildNextButton(OnboardingBloc bloc, int currentPage) {
    return Positioned(
      left: _nextButtonCenterX - _nextButtonDiameter / 2,
      top: _nextButtonCenterY - _nextButtonDiameter / 2,
      width: _nextButtonDiameter,
      height: _nextButtonDiameter,
      child: FilledButton(
        style: FilledButton.styleFrom(
          shape: const CircleBorder(),
          padding: EdgeInsets.zero,
          backgroundColor: MerzoxColors.kColorEE6C4D,
          minimumSize: const Size.square(_nextButtonDiameter),
          // Without this the button reserves a 48px tap target and would no
          // longer measure the nominal 40px circle the reference locks.
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: () => _advance(bloc, currentPage),
        child: const Icon(
          Icons.arrow_back_ios_new_rounded,
          color: Colors.white,
          size: _nextButtonIconSize,
        ),
      ),
    );
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
              // `BoxFit.contain` is exactly the locked
              // `min(availableWidth / 375, availableHeight / 734)` scale, so
              // the design canvas is only ever scaled uniformly, and
              // `topCenter` pins it to the top of the safe area.
              child: FittedBox(
                fit: BoxFit.contain,
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: OnboardingPage.designWidth,
                  height: OnboardingPage.designHeight,
                  child: Stack(
                    children: <Widget>[
                      Positioned.fill(
                        child: PageView(
                          controller: _pageController,
                          onPageChanged: (page) => bloc.add(NextPage(page)),
                          children: <Widget>[
                            OnboardingPage(
                              imagePath:
                                  'assets/images/Onboarding/onboarding1.png',
                              title: 'onboarding.page1Title'.tr(),
                              subtitle: 'onboarding.page1Subtitle'.tr(),
                            ),
                            OnboardingPage(
                              imagePath:
                                  'assets/images/Onboarding/onboarding2.png',
                              title: 'onboarding.page2Title'.tr(),
                              subtitle: 'onboarding.page2Subtitle'.tr(),
                            ),
                            OnboardingPage(
                              imagePath:
                                  'assets/images/Onboarding/onboarding3.png',
                              title: 'onboarding.page3Title'.tr(),
                              subtitle: 'onboarding.page3Subtitle'.tr(),
                            ),
                          ],
                        ),
                      ),
                      if (state.currentPage != _lastPage) _buildSkip(bloc),
                      _buildIndicators(state.currentPage),
                      _buildNextButton(bloc, state.currentPage),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
