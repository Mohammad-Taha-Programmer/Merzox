import 'package:flutter_test/flutter_test.dart';
import 'package:merzox/core/auth/sign_in_identifier.dart';

/// The server stores one spelling of a number. These are the spellings a reader
/// arrives with, and what each one has to become.
void main() {
  group('a number with no country of its own', () {
    test('takes the country picked beside the field', () {
      expect(
        signInIdentifier('592029316', dialPrefix: '+972'),
        '+972592029316',
      );
    });

    test('loses the trunk zero the country code replaces', () {
      expect(
        signInIdentifier('0592029316', dialPrefix: '+972'),
        '+972592029316',
      );
    });

    test('follows the flag, not the last one that was picked', () {
      expect(
        signInIdentifier('0592029316', dialPrefix: '+970'),
        '+970592029316',
      );
    });

    test('is read past the spacing somebody typed for their own eyes', () {
      expect(
        signInIdentifier(' 059 202-9316 ', dialPrefix: '+972'),
        '+972592029316',
      );
    });
  });

  group('a number that names its own country', () {
    test('keeps the plus it was written with', () {
      expect(
        signInIdentifier('+972592029316', dialPrefix: '+970'),
        '+972592029316',
      );
    });

    test('has two leading zeros replaced by the plus the server expects', () {
      expect(
        signInIdentifier('00972592029316', dialPrefix: '+970'),
        '+972592029316',
      );
    });

    test('is stripped of spacing either way it was written', () {
      expect(
        signInIdentifier('+972 59-202 9316', dialPrefix: '+970'),
        '+972592029316',
      );
      expect(
        signInIdentifier('00 972 59 202 9316', dialPrefix: '+970'),
        '+972592029316',
      );
    });

    test('ignores the flag entirely, whichever one is showing', () {
      const String typed = '00201234567890';

      expect(signInIdentifier(typed, dialPrefix: '+972'), '+201234567890');
      expect(signInIdentifier(typed, dialPrefix: '+1'), '+201234567890');
    });
  });

  group('the field is still an identifier field', () {
    test('an email address travels untouched', () {
      expect(
        signInIdentifier('user@example.com', dialPrefix: '+972'),
        'user@example.com',
      );
    });

    test('an email is trimmed but never given a country code', () {
      expect(
        signInIdentifier('  user@example.com  ', dialPrefix: '+972'),
        'user@example.com',
      );
    });

    test('an empty entry stays empty for the validator to refuse', () {
      expect(signInIdentifier('   ', dialPrefix: '+972'), '');
    });
  });

  group('the dial code itself', () {
    test('is accepted however the list or a stored value spells it', () {
      expect(internationalDialPrefix('+972'), '+972');
      expect(internationalDialPrefix('972'), '+972');
      expect(internationalDialPrefix('00972'), '+972');
    });

    test('is nothing when there is nothing to read', () {
      expect(internationalDialPrefix(''), '');
    });
  });

  // The rule reads a country only where the reader declared one. Bare digits
  // that happen to open with a country code are a local number, because a rule
  // that sometimes reads leading digits as a country and sometimes as the
  // number cannot be predicted by the person typing. This is the behaviour, and
  // it is pinned so a later change to it is a decision rather than a slip.
  test('leading digits alone do not make a country code', () {
    expect(
      signInIdentifier('972592029316', dialPrefix: '+972'),
      '+972972592029316',
    );
  });
}
