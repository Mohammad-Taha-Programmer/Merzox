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
String devBaseUrl(String host, int port) => 'http://$host:$port/api/v1';

/// The config file's contents.
///
/// Written as the exact shape `--dart-define-from-file` expects: a flat JSON
/// object of define names to string values. The comment a developer would
/// want cannot go inside it - JSON has nowhere to put one - so the file is
/// deliberately tiny and the explanation lives beside it in the example.
String renderDevConfig({required String baseUrl}) {
  return '{\n  "MERZOX_API_BASE_URL": "$baseUrl"\n}\n';
}
