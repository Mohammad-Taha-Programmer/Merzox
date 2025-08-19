import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:merzox/features/onboarding/bloc/onboarding_bloc.dart';
import 'package:merzox/features/onboarding/bloc/onboarding_event.dart';
import 'package:merzox/features/onboarding/bloc/onboarding_state.dart';
import 'package:merzox/features/onboarding/view/onboarding_page.dart';
import 'package:merzox/core/constants/colors.dart';

class OnboardingScreen extends StatelessWidget {
  OnboardingScreen({super.key});
  final PageController _pageController = PageController(
    viewportFraction: 1,
    keepPage: true,
    initialPage: 0,
  );
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<OnboardingBloc, OnboardingState>(
      builder: (BuildContext context, OnboardingState state) {
        final bloc = context.read<OnboardingBloc>();
        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                // Skip button (Arabic: تخطي) — hidden on last page
                if (state.currentPage != 2) // last page index is 2
                  Align(
                    alignment: Alignment.topLeft,
                    child: TextButton(
                      onPressed: () {
                        bloc.add(SkipOnboarding());
                      },
                      child: Text(
                        'تخطي',
                        style: TextStyle(
                          fontSize: 12.0,
                          color: MerzoxColors.kColor3B3B3B,
                        ),
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 48), // placeholder to keep layout
                const SizedBox(height: 60.0),
                // Main content with PageView filling available space
                Expanded(
                  flex: 2,
                  child: PageView(
                    scrollDirection: Axis.horizontal,
                    controller: _pageController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    allowImplicitScrolling: true,
                    padEnds: true,
                    pageSnapping: true,
                    onPageChanged: (page) {
                      bloc.add(NextPage(page));
                    },
                    // new
                    children: const [
                      OnboardingPage(
                        imagePath: 'assets/images/Onboarding/onboarding1.png',
                        title: 'أفضل الخصومات',
                        subtitle:
                            'يوفر التطبيق العديد من الخصومات والعروض في العديد\n من المتاجر',
                      ),
                      OnboardingPage(
                        imagePath: 'assets/images/Onboarding/onboarding2.png',
                        title: 'توافر الخريطة',
                        subtitle:
                            'يوفر التطبيق خريطة للتسهيل خلال عملية البحث\nعلى المتاجر القريبة، وحفظهم',
                      ),
                      OnboardingPage(
                        imagePath: 'assets/images/Onboarding/onboarding3.png',
                        title: 'توافر أكثر من وسيلة دفع',
                        subtitle:
                            'يوفر التطبيق أكثر من وسيلة دفع للتسهيل على\nالزبون',
                      ),
                    ],
                  ),
                ),

                // Dots indicator
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List<AnimatedContainer>.generate(3, (index) {
                      return AnimatedContainer(
                        curve: Curves.bounceInOut,
                        margin: const EdgeInsets.all(4),
                        width: index == state.currentPage ? 20 : 10,
                        height: 10,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: MerzoxColors.kColor98C1D9),
                          color: index == state.currentPage
                              ? MerzoxColors.kColor3D5A80
                              : Colors.transparent,
                        ),
                        duration: Duration(milliseconds: 100),
                      );
                    }),
                  ),
                ),

                // Circular progress button
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: MerzoxColors.kColorEE6C4D,
                        shape: BoxShape.circle,
                      ),
                      height: 70,
                      width: 70,
                      child: CircularProgressIndicator(
                        value: (state.currentPage + 1) / 3,
                        strokeWidth: 2,
                        valueColor: const AlwaysStoppedAnimation(
                          MerzoxColors.kColor3D5A80,
                        ),
                        backgroundColor: MerzoxColors.kColorFEE3DC,
                      ),
                    ),
                    Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white,
                          style: BorderStyle.solid,
                          width: 10,
                        ),
                      ),
                      child: IconButton(
                        color: MerzoxColors.kColorEE6C4D,
                        icon: const Icon(
                          size: 20,
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white,
                        ),
                        style: ButtonStyle(
                          shape: WidgetStateProperty.all(const CircleBorder()),
                        ),
                        onPressed: () {
                          _pageController.nextPage(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.bounceInOut,
                          );
                          bloc.add(NextPage(state.currentPage));
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 80.0),
              ],
            ),
          ),
        );
      },
    );
  }
}
