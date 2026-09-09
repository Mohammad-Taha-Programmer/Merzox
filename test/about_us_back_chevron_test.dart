import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/widgets/merzox_back_chevron.dart';
import 'package:merzox/features/about_us/bloc/about_us_bloc.dart';
import 'package:merzox/features/about_us/bloc/about_us_event.dart';
import 'package:merzox/features/about_us/pages/about_us_page.dart';
import 'package:merzox/services/api_service.dart';

import 'golden/merzox_golden_harness.dart' as golden;
import 'localization_test_harness.dart';

/// The way out of `من نحن`.
///
/// The board carries the artboard's thin chevron rather than Material's
/// shafted arrow, and the press has to leave the screen. The title is stacked
/// before the button here, so nothing swallows the press - but the order is
/// one edit away from flipping, which is why the press is held and not only
/// the mark.

class _AboutUsApi extends ApiService {
  @override
  Future<AboutUsApiModel> aboutUs({required String languageCode}) async =>
      AboutUsApiModel.fromJson(<String, dynamic>{
        'pageTitle': 'من نحن',
        'appLabel': 'تطبيق',
        'appName': 'MERZOX',
        'introduction': 'نص افتراضي',
        'sections': <Map<String, dynamic>>[
          <String, dynamic>{
            'key': 'how',
            'title': 'آلية العمل',
            'content': 'نص افتراضي',
          },
        ],
      });
}

/// Opens `من نحن` from somewhere else, so there is a way back to test.
///
/// The golden surface is borrowed for the `EasyLocalization` around it - the
/// page reads `context.locale` on its first frame and throws without one - and
/// for the asset loading that needs, which has to happen outside the fake
/// clock. Nothing here is captured; it is the wrapper that is wanted.
Future<void> _pumpAboutUs(WidgetTester tester) async {
  final AboutUsBloc bloc = AboutUsBloc(apiService: _AboutUsApi());
  addTearDown(bloc.close);

  await golden.pumpMerzoxGoldenPage(
    tester,
    Builder(
      builder: (BuildContext context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () {
              bloc.add(const AboutUsStarted('ar'));
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => BlocProvider<AboutUsBloc>.value(
                    value: bloc,
                    child: const AboutUsPage(),
                  ),
                ),
              );
            },
            child: const Text('elsewhere'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('elsewhere'));
  await golden.settleMerzoxGoldenFrames(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadAppTranslations();
    await golden.loadMerzoxGoldenFonts();
  });

  testWidgets('the way back is the artboard chevron, not a Material arrow', (
    tester,
  ) async {
    await _pumpAboutUs(tester);

    expect(find.byType(AboutUsPage), findsOneWidget);
    expect(find.byType(MerzoxBackChevron), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
  });

  testWidgets('the mark points the way back in each reading order', (
    tester,
  ) async {
    await _pumpAboutUs(tester);

    final CustomPaint paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(MerzoxBackChevron),
        matching: find.byType(CustomPaint),
      ),
    );

    expect(
      (paint.painter! as MerzoxBackChevronPainter).rightward,
      isTrue,
      reason: 'in Arabic the way back is towards the right edge',
    );
  });

  testWidgets('pressing it leaves the screen', (tester) async {
    await _pumpAboutUs(tester);

    await tester.tap(find.byType(MerzoxBackChevron));
    await settleFrames(tester);

    expect(find.byType(AboutUsPage), findsNothing);
    expect(find.text('elsewhere'), findsOneWidget);
  });
}
