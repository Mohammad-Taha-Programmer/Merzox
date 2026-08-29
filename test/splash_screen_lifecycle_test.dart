import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/onboarding/view/onboarding_page.dart';
import 'package:merzox/features/splash/presentation/splash_screen.dart';

void main() {
  testWidgets('disposed SplashScreen does not navigate when its timer fires', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SplashScreen()));
    expect(find.byType(SplashScreen), findsOneWidget);

    // Unmount the splash before the three-second navigation timer fires.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    expect(find.byType(SplashScreen), findsNothing);

    // Advance fake time past the scheduled navigation.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(OnboardingPage), findsNothing);
  });
}
