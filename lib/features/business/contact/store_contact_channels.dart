import 'package:merzox/features/business/models/business_models.dart';
import 'package:merzox/services/api_service.dart';

/// Every way a shop can be reached, and where each one leads.
///
/// The values are what the merchant typed - a handle, a pasted link, a phone
/// number with or without a country code - so turning one into something a
/// phone can open is the whole job, and it is kept here where it can be
/// checked without a screen.

/// What kind of channel a row is, which decides its icon and its wording.
enum StoreContactKind { whatsapp, instagram, facebook, phone, email }

/// One reachable channel.
class StoreContactChannel {
  final StoreContactKind kind;

  /// What the reader sees: the number, the address, the handle.
  final String label;

  /// A second line, when the account gave the value a name of its own -
  /// `mobile`, `work`, `home`. Empty when there is nothing to add.
  final String note;

  /// Where a tap goes.
  final Uri uri;

  const StoreContactChannel({
    required this.kind,
    required this.label,
    required this.uri,
    this.note = '',
  });
}

/// A phone number as a phone can dial it.
///
/// Everything that is not a digit goes, and a leading `+` survives, because
/// `tel:` takes the number and not the way it was written down.
Uri? telUri(String value) {
  final String digits = _dialable(value);
  if (digits.isEmpty) return null;

  return Uri(scheme: 'tel', path: digits);
}

Uri? mailtoUri(String value) {
  final String address = value.trim();
  if (address.isEmpty || !address.contains('@')) return null;

  return Uri(scheme: 'mailto', path: address);
}

/// WhatsApp takes a number in its own address, never a `tel:`.
///
/// `wa.me` wants digits alone - a `+` in the path is read as part of the
/// number and the chat opens on nobody.
Uri? whatsappUri(String value) {
  final String digits = _dialable(value).replaceAll('+', '');
  if (digits.isEmpty) return null;

  return Uri.https('wa.me', '/$digits');
}

/// A social account, however the merchant wrote it down.
///
/// A pasted link is opened as it is. A handle - with or without its `@` - is
/// hung off the site's own address, which is what a merchant means when they
/// type their name into a field labelled Instagram.
Uri? socialUri(String value, {required String host}) {
  final String text = value.trim();
  if (text.isEmpty) return null;

  final Uri? parsed = Uri.tryParse(text);
  if (parsed != null &&
      parsed.hasScheme &&
      (parsed.scheme == 'http' || parsed.scheme == 'https') &&
      parsed.host.isNotEmpty) {
    return parsed;
  }

  // Anything that is not an address and not a plain handle - a path, a query,
  // a `javascript:` string - is refused rather than pasted onto a host.
  final String handle = text.startsWith('@') ? text.substring(1) : text;
  if (handle.isEmpty || !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(handle)) {
    return null;
  }

  return Uri.https(host, '/$handle');
}

/// The shop's own channels, in the order the page draws them.
///
/// Only what is actually there: a row for a channel the merchant never filled
/// in would be a dead end, and an empty page says so plainly instead.
List<StoreContactChannel> storeSocialChannels(BusinessSocialLinks links) {
  final List<StoreContactChannel> channels = <StoreContactChannel>[];

  final Uri? whatsapp = whatsappUri(links.whatsapp);
  if (whatsapp != null) {
    channels.add(
      StoreContactChannel(
        kind: StoreContactKind.whatsapp,
        label: links.whatsapp.trim(),
        uri: whatsapp,
      ),
    );
  }

  final Uri? instagram = socialUri(links.instagram, host: 'instagram.com');
  if (instagram != null) {
    channels.add(
      StoreContactChannel(
        kind: StoreContactKind.instagram,
        label: links.instagram.trim(),
        uri: instagram,
      ),
    );
  }

  final Uri? facebook = socialUri(links.facebook, host: 'facebook.com');
  if (facebook != null) {
    channels.add(
      StoreContactChannel(
        kind: StoreContactKind.facebook,
        label: links.facebook.trim(),
        uri: facebook,
      ),
    );
  }

  return channels;
}

/// The account's phones, as channels.
///
/// The account is where a merchant's numbers live - given at sign-up,
/// corrected in the personal profile - so this page reads them rather than
/// asking for them a second time.
List<StoreContactChannel> storePhoneChannels(AuthApiUser? account) {
  if (account == null) return const <StoreContactChannel>[];

  final List<StoreContactChannel> channels = <StoreContactChannel>[];

  for (final ContactPhone phone in _phonesOf(account)) {
    final Uri? uri = telUri(phone.value);
    if (uri == null) continue;

    channels.add(
      StoreContactChannel(
        kind: StoreContactKind.phone,
        label: phone.value.trim(),
        note: phone.label,
        uri: uri,
      ),
    );
  }

  return channels;
}

List<StoreContactChannel> storeEmailChannels(AuthApiUser? account) {
  if (account == null) return const <StoreContactChannel>[];

  final List<StoreContactChannel> channels = <StoreContactChannel>[];

  for (final ContactEmail email in _emailsOf(account)) {
    final Uri? uri = mailtoUri(email.value);
    if (uri == null) continue;

    channels.add(
      StoreContactChannel(
        kind: StoreContactKind.email,
        label: email.value.trim(),
        note: email.label,
        uri: uri,
      ),
    );
  }

  return channels;
}

/// The account's numbers, falling back to the single one older accounts have.
///
/// An account created before the list existed carries only `phone`, and a
/// page that read the list alone would show nothing for it.
List<ContactPhone> _phonesOf(AuthApiUser account) {
  if (account.phones.isNotEmpty) return account.phones;

  final String single = account.phone?.trim() ?? '';
  return single.isEmpty
      ? const <ContactPhone>[]
      : <ContactPhone>[ContactPhone(value: single)];
}

List<ContactEmail> _emailsOf(AuthApiUser account) {
  if (account.emails.isNotEmpty) return account.emails;

  final String single = account.email?.trim() ?? '';
  return single.isEmpty
      ? const <ContactEmail>[]
      : <ContactEmail>[ContactEmail(value: single)];
}

String _dialable(String value) {
  final String trimmed = value.trim();
  if (trimmed.isEmpty) return '';

  final String digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return '';

  return trimmed.startsWith('+') ? '+$digits' : digits;
}
