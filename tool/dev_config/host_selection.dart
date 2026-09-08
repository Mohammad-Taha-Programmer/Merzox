/// Which address on this machine a phone can actually reach.
///
/// A physical device cannot use either of the app's fallbacks: `10.0.2.2` is
/// the Android emulator's alias for its host's loopback, and `127.0.0.1` is
/// the phone's own loopback. Both are fixed names for "this machine" from the
/// point of view of something running ON this machine, and a phone is not.
///
/// So a real device has always needed the workstation's LAN address, and the
/// last time that address lived anywhere it lived in the source, went stale
/// when the router handed out a different number, and cost an afternoon to
/// find - the server was up the whole while. It now lives in a generated
/// config file that is rewritten from the machine rather than typed.
///
/// This half is the choosing, kept free of I/O so the rules can be stated in
/// a test rather than trusted.
library;

import 'dart:convert';

/// One IPv4 address found on one interface.
class LocalAddress {
  /// The adapter's name, as the operating system reports it.
  final String interfaceName;

  final String address;

  const LocalAddress({required this.interfaceName, required this.address});

  @override
  String toString() => '$address  ($interfaceName)';
}

/// Adapters that exist only for software on this machine.
///
/// A virtual switch has a perfectly valid private address that no phone on the
/// Wi-Fi can reach - this workstation offers two of them, `192.168.75.1` and
/// `192.168.2.1`, either of which would look like a plausible answer and fail
/// exactly like the stale address did.
const List<String> kVirtualAdapterMarkers = <String>[
  'vmware',
  'virtualbox',
  'vbox',
  'hyper-v',
  'vethernet',
  'loopback',
  'bluetooth',
  'docker',
  'wsl',
  'tap-',
  'npcap',
];

/// Whether [address] is in one of the private IPv4 ranges.
///
/// A development machine and the phone testing against it are behind the same
/// router, so the address is private by definition. Anything public here is
/// something else and is not offered.
///
/// This one rule also disposes of the two addresses that most look like
/// answers and are not: `127.0.0.1`, which is whichever machine is asking, and
/// `169.254.x.x`, which is what an interface holds when it never got a lease.
/// Neither is in a private range, so neither needs a rule of its own - and a
/// second rule that never fires is a rule nobody can tell is broken.
bool isPrivateIPv4(String address) {
  final List<String> parts = address.split('.');
  if (parts.length != 4) return false;

  final List<int?> octets = parts.map(int.tryParse).toList();
  if (octets.any((int? part) => part == null || part < 0 || part > 255)) {
    return false;
  }

  final int first = octets[0]!;
  final int second = octets[1]!;

  if (first == 10) return true;
  if (first == 192 && second == 168) return true;
  if (first == 172 && second >= 16 && second <= 31) return true;

  return false;
}

/// Whether an adapter is one of the virtual ones.
bool isVirtualAdapter(String interfaceName) {
  final String name = interfaceName.toLowerCase();

  return kVirtualAdapterMarkers.any(name.contains);
}

/// The addresses a phone on the same network could actually reach.
///
/// Order is preserved, so a caller that finds exactly one has an unambiguous
/// answer and a caller that finds several can show them all rather than guess.
List<LocalAddress> reachableHosts(List<LocalAddress> found) {
  return found
      .where(
        (LocalAddress candidate) =>
            isPrivateIPv4(candidate.address) &&
            !isVirtualAdapter(candidate.interfaceName),
      )
      .toList();
}

/// The base URL a build should be given for [host].
String devBaseUrl(String host, int port) => '${devOrigin(host, port)}/api/v1';

/// The same machine, named the way the server names itself.
///
/// The app is given the API's base - the origin with `/api/v1` after it -
/// because that is what it appends paths to. The server is given the origin
/// alone, because `PUBLIC_BASE_URL` is what it puts in FRONT of
/// `/api/v1/auth/verify-email` when it writes a link into an email, and a
/// prefix counted twice is a link that opens nothing.
///
/// Both are built from the one host and the one port, so the address the
/// phone dials and the address the email names cannot disagree.
String devOrigin(String host, int port) => 'http://$host:$port';

/// The setting the server reads its own public address from.
const String kPublicBaseUrlKey = 'PUBLIC_BASE_URL';

/// [contents] with [kPublicBaseUrlKey] set to [origin].
///
/// The file this rewrites holds the database URI and the mail password beside
/// the address, so it is edited one line at a time rather than regenerated:
/// every line that is not this setting comes back exactly as it was, its own
/// line ending included, and a setting that was commented out stays commented
/// out.
///
/// Every uncommented assignment is rewritten, not only the first. A file that
/// names the setting twice has a winner decided by the reader's rules rather
/// than by ours, and making both say the same thing means it does not matter
/// which of them wins.
String withPublicBaseUrl(String contents, String origin) {
  final String line = '$kPublicBaseUrlKey=$origin';

  // `[^\r\n]` rather than `.`, which matches a carriage return: on a file
  // written with CRLF endings the replacement would eat it and leave one line
  // ending unlike every other line in the file.
  final RegExp assignment = RegExp(
    r'^[ \t]*' '${RegExp.escape(kPublicBaseUrlKey)}' r'[ \t]*=[^\r\n]*',
    multiLine: true,
  );

  if (assignment.hasMatch(contents)) {
    return contents.replaceAll(assignment, line);
  }

  final String newline = contents.contains('\r\n') ? '\r\n' : '\n';
  final String body = contents.isEmpty || contents.endsWith('\n')
      ? contents
      : '$contents$newline';

  return '$body$line$newline';
}

/// The define this tool owns.
const String kApiBaseUrlKey = 'MERZOX_API_BASE_URL';

/// The config file's contents.
///
/// Written as the exact shape `--dart-define-from-file` expects: a flat JSON
/// object of define names to string values. The comment a developer would
/// want cannot go inside it - JSON has nowhere to put one - so the file is
/// deliberately tiny and the explanation lives beside it in the example.
///
/// [existing] is the file as it stands, when there is one. Every define in it
/// other than the address is carried over: the address is the only thing this
/// tool knows, and a build may also carry `MERZOX_API_TIMEOUT_MS`, put there
/// by hand for a slow network. Rewriting the file from scratch would drop it
/// silently, and it would be missed on the next run rather than this one.
///
/// A file that cannot be parsed is replaced rather than mourned. There is
/// nothing to carry over from something that is not a config file, and
/// refusing to write would leave a developer stuck behind a typo.
String renderDevConfig({required String baseUrl, String? existing}) {
  final Map<String, String> defines = <String, String>{};

  if (existing != null && existing.trim().isNotEmpty) {
    try {
      final Object? parsed = jsonDecode(existing);
      if (parsed is Map<String, dynamic>) {
        for (final MapEntry<String, dynamic> entry in parsed.entries) {
          defines[entry.key] = '${entry.value}';
        }
      }
    } on FormatException {
      // Nothing to keep.
    }
  }

  defines[kApiBaseUrlKey] = baseUrl;

  // The address first, whatever order it arrived in, so the line a developer
  // opens this file to read is the top one.
  final List<String> names = <String>[
    kApiBaseUrlKey,
    ...defines.keys.where((String key) => key != kApiBaseUrlKey).toList()
      ..sort(),
  ];

  final String body = names
      .map((String name) => '  "$name": "${defines[name]}"')
      .join(',\n');

  return '{\n$body\n}\n';
}
