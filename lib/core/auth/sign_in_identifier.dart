/// What the reader typed into the sign-in field, as the server holds it.
///
/// The server stores one spelling of a phone number and one only: the
/// international one, written with a leading `+`. A reader does not know that,
/// and types whichever spelling their own phone shows them - the local number
/// with its trunk zero, the international one dialled with two zeros, the
/// international one written with a plus. All three are the same number, and
/// the field accepts all three.
///
/// The country the leading digits belong to is the one picked in the flag list
/// beside the field, and it is consulted only when the typed number carries no
/// country of its own.
library;

/// A country dial code as it must be sent: digits behind a single `+`.
///
/// The list beside the field writes them as `+972`, but a stored or pasted one
/// may arrive as `00972` or as bare digits, so all three are accepted here
/// rather than at each call site.
String internationalDialPrefix(String prefix) {
  final String digits = prefix.replaceAll(RegExp(r'\D'), '');
  final String country = digits.startsWith('00') ? digits.substring(2) : digits;

  return country.isEmpty ? '' : '+$country';
}

/// The identifier to send, from what was typed and the flag that was picked.
///
/// An entry containing `@` is an email address and travels untouched; the
/// field is a single identifier field and the label above it does not change
/// that.
///
/// A phone number is read in one of three ways:
///
///   * it begins with `+`, so it already names its country and only the
///     spacing and dashes are dropped;
///   * it begins with two zeros, which is the same country code dialled the
///     other way round, so the two zeros become the `+` the server expects;
///   * it names no country, so [dialPrefix] supplies one, and the national
///     trunk zero in front of the local number - which belongs to dialling
///     inside the country and to nothing else - is dropped as the country code
///     replaces it.
///
/// What is deliberately *not* guessed: bare digits that happen to start with a
/// country code. `972...` with no `+` and no `00` is, by the rule above, a
/// local number, because a rule that sometimes reads leading digits as a
/// country and sometimes as the number itself cannot be predicted by the
/// person typing.
String signInIdentifier(String typed, {required String dialPrefix}) {
  final String value = typed.trim();
  if (value.contains('@')) return value;

  return internationalPhoneNumber(value, dialPrefix: dialPrefix);
}

/// A phone number in the one spelling the server stores, from whichever of the
/// three a reader arrived with.
///
/// The same rule [signInIdentifier] applies, without the question of whether
/// the entry might be an email: a field labelled for a number is a number.
/// Every screen that asks for one calls this, so there is one place where the
/// three spellings become one - there were three copies of this arithmetic and
/// they had already stopped agreeing, one of them prepending a country code
/// written into the source.
String internationalPhoneNumber(String typed, {required String dialPrefix}) {
  final String value = typed.trim();
  if (value.isEmpty) return value;

  final String digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return value;

  if (value.startsWith('+')) return '+$digits';
  if (digits.startsWith('00')) return '+${digits.substring(2)}';

  final String local = digits.startsWith('0') ? digits.substring(1) : digits;

  return '${internationalDialPrefix(dialPrefix)}$local';
}
