import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/widgets/merzox_icons.dart';
import 'package:merzox/core/widgets/picture_viewer.dart';
import 'package:merzox/core/widgets/remote_circle_avatar.dart';
import 'package:merzox/features/authentication/account_avatar.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:merzox/features/home/home_screen.dart';
import 'package:merzox/features/home/presentation/bloc/home_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'localization_test_harness.dart';
import 'network_image_harness.dart';

/// The account's own picture, where the account is named.
///
/// It was never drawn here: the bar drew the figure whatever the account had,
/// so a reader who added a picture saw it on the profile tab and nowhere else.
const String _picture = 'https://pictures.example/merzox/face.png';

const ValueKey<String> _pressable = ValueKey<String>(
  'merzox.home.accountPicture',
);

/// No `HomeStarted`, so the shell renders without catalog, location or session
/// work.
Future<void> _pumpHome(WidgetTester tester) async {
  await pumpLocalized(
    tester,
    BlocProvider<HomeBloc>(
      create: (_) => HomeBloc(),
      child: const HomeScreen(isGuest: false),
    ),
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadAppTranslations();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await AccountAvatar.forget();
  });

  testWidgets('with no picture the bar draws the figure', (tester) async {
    await _pumpHome(tester);

    expect(find.byIcon(MerzoxIcons.homeScreenProfile), findsOneWidget);
    expect(find.byKey(_pressable), findsNothing);
  });

  // The picture stands exactly where the figure stood. Anything else and the
  // bar would take a different amount of room depending on whether the account
  // happens to have a photograph, which is a layout that moves for a reason
  // nobody can see.
  testWidgets('the picture occupies the circle the figure did', (tester) async {
    await _pumpHome(tester);
    final Rect figure = tester.getRect(
      find.byIcon(MerzoxIcons.homeScreenProfile).first,
    );
    final Rect figureCircle = tester.getRect(
      find
          .ancestor(
            of: find.byIcon(MerzoxIcons.homeScreenProfile).first,
            matching: find.byType(CircleAvatar),
          )
          .first,
    );

    SharedPreferences.setMockInitialValues(<String, Object>{
      AuthBloc.avatarUrlKey: _picture,
    });
    await AccountAvatar.restore();

    serveNetworkImage();
    await _pumpHome(tester);

    final Rect picture = tester.getRect(
      find.descendant(
        of: find.byKey(_pressable),
        matching: find.byType(RemoteCircleAvatar),
      ),
    );

    expect(picture.size, figureCircle.size);
    expect(
      picture.center,
      offsetMoreOrLessEquals(figureCircle.center, epsilon: 0.5),
    );
    expect(figure.width, lessThan(figureCircle.width));

    stopServingNetworkImages();
  });

  testWidgets('a picture already stored is what the bar opens on', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      AuthBloc.avatarUrlKey: _picture,
    });
    await AccountAvatar.restore();

    serveNetworkImage();
    await _pumpHome(tester);

    final RemoteCircleAvatar avatar = tester.widget<RemoteCircleAvatar>(
      find.descendant(
        of: find.byKey(_pressable),
        matching: find.byType(RemoteCircleAvatar),
      ),
    );

    expect(avatar.url, _picture);

    stopServingNetworkImages();
  });

  // The fault itself. Storage already held the new URL after an upload; the bar
  // was simply never told, and went on drawing the figure until something
  // unrelated rebuilt it.
  testWidgets('a picture added while the bar is on screen reaches it', (
    tester,
  ) async {
    serveNetworkImage();
    await _pumpHome(tester);

    expect(find.byKey(_pressable), findsNothing);

    await AccountAvatar.remember(_picture);
    await settleFrames(tester);

    expect(find.byKey(_pressable), findsOneWidget);

    stopServingNetworkImages();
  });

  testWidgets('pressing the picture opens it full-size', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      AuthBloc.avatarUrlKey: _picture,
    });
    await AccountAvatar.restore();

    serveNetworkImage();
    await _pumpHome(tester);

    expect(find.byKey(kPictureViewerKey), findsNothing);

    await tester.tap(find.byKey(_pressable));
    await settleFrames(tester);

    expect(find.byKey(kPictureViewerKey), findsOneWidget);

    await tester.tap(find.byKey(kPictureViewerCloseKey));
    await settleFrames(tester);

    expect(find.byKey(kPictureViewerKey), findsNothing);

    stopServingNetworkImages();
  });

  // The picture belongs to the session. Left in storage it was the previous
  // account's face on the first frame the next one drew.
  testWidgets('signing out takes the picture with it', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      AuthBloc.avatarUrlKey: _picture,
    });
    await AccountAvatar.restore();
    expect(AccountAvatar.url.value, _picture);

    await AuthBloc.clearStoredSession();

    expect(AccountAvatar.url.value, '');

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(AuthBloc.avatarUrlKey), isNull);
  });
}
