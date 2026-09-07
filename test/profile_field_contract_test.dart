import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/features/profile/pages/profile_edit_page.dart';

/// Every field the personal profile screen edits, against the server that has
/// to keep it.
///
/// A control on a screen that writes nowhere looks exactly like one that
/// works: the form saves, the snack bar says so, and the value is gone on the
/// next load. So each field is followed here from the screen to the route
/// that accepts it, the branch that applies it, the schema that stores it and
/// the response that reads it back.
///
/// These read the backend sources from the working copy - the app and the API
/// live in one repository - so a field removed on one side fails on the other
/// instead of failing silently on a phone.

/// The names the screen sends in its PATCH body, in the order it builds them.
const List<String> profilePatchFields = <String>[
  'name',
  'gender',
  'address',
  'birthDate',
  'emails',
  'phones',
];

Set<String> _jsSetLiteral(String source, String name) {
  final RegExpMatch? match = RegExp(
    'const\\s+$name\\s*=\\s*new Set\\(\\[(.*?)\\]\\)',
    dotAll: true,
  ).firstMatch(source);

  expect(match, isNotNull, reason: '$name is not declared in the controller');

  return RegExp("'([^']+)'")
      .allMatches(match!.group(1)!)
      .map((RegExpMatch m) => m.group(1)!)
      .toSet();
}

void main() {
  final String controller = File(
    'backend/src/controllers/user.controller.js',
  ).readAsStringSync();
  final String routes = File(
    'backend/src/routes/user.routes.js',
  ).readAsStringSync();
  final String model = File('backend/src/models/User.js').readAsStringSync();

  test('the screen has a route to send its fields to', () {
    // The app patches `/users/me`, authenticated and validated.
    expect(
      routes.contains("router.patch('/me', requireAuth, validateProfilePatch, updateMe)"),
      isTrue,
      reason: 'the profile PATCH route is not mounted as the app calls it',
    );
  });

  test('every field the screen sends passes the validator at the door', () {
    // The validator refuses a body carrying anything it does not list, so a
    // field added to the screen and nowhere else does not save half of the
    // form - it fails the whole PATCH with `INVALID_PROFILE_FIELDS`.
    final String validate = File(
      'backend/src/middleware/validate.js',
    ).readAsStringSync();

    final int start = validate.indexOf('export function validateProfilePatch');
    expect(start, greaterThan(-1));

    final RegExpMatch? allowed = RegExp(
      r'const allowed = \[(.*?)\]',
      dotAll: true,
    ).firstMatch(validate.substring(start));

    expect(allowed, isNotNull);

    final Set<String> names = RegExp("'([^']+)'")
        .allMatches(allowed!.group(1)!)
        .map((RegExpMatch m) => m.group(1)!)
        .toSet();

    for (final String field in profilePatchFields) {
      expect(
        names,
        contains(field),
        reason: '$field would be refused before it reached the controller',
      );
    }
  });

  test('every field the screen sends is read out of the body', () {
    final RegExpMatch? picked = RegExp(
      r'const updates = pick\(req\.body, \[(.*?)\]',
      dotAll: true,
    ).firstMatch(controller);

    expect(picked, isNotNull);

    final Set<String> accepted = RegExp("'([^']+)'")
        .allMatches(picked!.group(1)!)
        .map((RegExpMatch m) => m.group(1)!)
        .toSet();

    for (final String field in profilePatchFields) {
      expect(
        accepted,
        contains(field),
        reason: '$field is sent by the screen but dropped by the controller',
      );
    }
  });

  test('every field the screen sends is applied by a branch of its own', () {
    for (final String field in profilePatchFields) {
      final bool applied =
          controller.contains('updates.$field !== undefined') ||
          controller.contains('Array.isArray(updates.$field)');

      expect(
        applied,
        isTrue,
        reason: '$field is read from the body but never written to the user',
      );
    }
  });

  test('every field the screen sends is a real field of the account', () {
    for (final String field in profilePatchFields) {
      expect(
        RegExp('^\\s+$field:', multiLine: true).hasMatch(model),
        isTrue,
        reason: '$field is written by the controller but not in the schema',
      );
    }
  });

  test('every field the screen sends comes back when it is read', () {
    // `toSafeJSON` is the only shape the app ever sees. A field the schema
    // stores but this omits is written and then invisible.
    final int start = model.indexOf('toSafeJSON');
    expect(start, greaterThan(-1));

    final String safeJson = model.substring(start);

    for (final String field in profilePatchFields) {
      expect(
        safeJson.contains('$field:'),
        isTrue,
        reason: '$field is stored but never returned to the app',
      );
    }
  });

  test('the one-time-change markers the screen obeys are stored', () {
    // The screen greys the name and gender out once they have been used. It
    // learns that from `canChangeName` / `canChangeGender`, which the server
    // derives from these two.
    for (final String marker in <String>['nameChangedAt', 'genderChangedAt']) {
      expect(model.contains(marker), isTrue);
      expect(controller.contains(marker), isTrue);
    }

    expect(model.contains('canChangeName'), isTrue);
    expect(model.contains('canChangeGender'), isTrue);
  });

  test('the labels the screen offers are the labels the server keeps', () {
    // Anything else is rewritten to `other` on the way in, so a label offered
    // here but unknown there would come back changed under the reader.
    expect(
      profileEmailLabels.keys.toSet(),
      _jsSetLiteral(controller, 'emailLabels'),
    );
    expect(
      profilePhoneLabels.keys.toSet(),
      _jsSetLiteral(controller, 'phoneLabels'),
    );
  });
}
