import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/home/widgets/business_rating_stars.dart';

Widget _testApp({
  required double rating,
  required int ratingCount,
  double width = 92,
}) {
  return MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            height: 24,
            child: BusinessRatingStars(
              rating: rating,
              ratingCount: ratingCount,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a newly created business displays five empty stars', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_testApp(rating: 0, ratingCount: 0));

    expect(find.byIcon(Icons.star_outline_rounded), findsNWidgets(5));

    expect(find.byIcon(Icons.star_rounded), findsNothing);

    expect(find.byIcon(Icons.star_half_rounded), findsNothing);

    expect(tester.takeException(), isNull);
  });

  testWidgets('zero reviewers override a stale legacy average', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_testApp(rating: 5, ratingCount: 0));

    expect(find.byIcon(Icons.star_outline_rounded), findsNWidgets(5));

    expect(find.byIcon(Icons.star_rounded), findsNothing);

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a real three point five average displays three and a half stars',
    (WidgetTester tester) async {
      await tester.pumpWidget(_testApp(rating: 3.5, ratingCount: 8));

      expect(find.byIcon(Icons.star_rounded), findsNWidgets(3));

      expect(find.byIcon(Icons.star_half_rounded), findsOneWidget);

      expect(find.byIcon(Icons.star_outline_rounded), findsOneWidget);

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('rating stars remain overflow-free in a narrow RTL card', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_testApp(rating: 4.5, ratingCount: 12, width: 58));

    expect(find.byType(BusinessRatingStars), findsOneWidget);

    expect(tester.takeException(), isNull);
  });
}
