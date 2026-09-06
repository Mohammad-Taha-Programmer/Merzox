import 'dart:io';

import 'dev_config/host_selection.dart';

/// Writes the address a phone should talk to into a file the build reads.
///
/// Run it, then run the app:
///
/// ```
/// dart run tool/dev_config.dart
/// flutter run --dart-define-from-file=config/merzox.dev.json
/// ```
///
/// The address is read off this machine rather than typed, so it cannot be
/// stale in the way a number in the source was. Re-run it whenever the router
/// hands out a different one - it is one command, and it is the first thing to
/// try when a physical device says the server is unreachable.
///
/// `--host` overrides the choosing entirely, for a machine where the automatic
/// answer is wrong or ambiguous. `--port` defaults to the port the backend
/// listens on.
const String kDefaultOutput = 'config/merzox.dev.json';
const int kDefaultPort = 4000;

Future<int> run(List<String> arguments, {required IOSink out}) async {
  final Map<String, String> options = _options(arguments);

  if (options.containsKey('help')) {
    out.writeln(_usage);
    return 0;
  }

  final String output = options['out'] ?? kDefaultOutput;
  final int? port = int.tryParse(options['port'] ?? '$kDefaultPort');

  if (port == null || port < 1 || port > 65535) {
    out.writeln('Not a port: ${options['port']}');
    return 2;
  }

  final String? host = options['host'] ?? await _chooseHost(out);
  if (host == null) return 2;

  final File file = File(output);
  await file.parent.create(recursive: true);
  await file.writeAsString(
    renderDevConfig(baseUrl: devBaseUrl(host, port)),
    flush: true,
  );

  out.writeln('Wrote $output');
  out.writeln('  ${devBaseUrl(host, port)}');
  out.writeln('');
  out.writeln('Run the app with:');
  out.writeln('  flutter run --dart-define-from-file=$output');

  return 0;
}

Future<String?> _chooseHost(IOSink out) async {
  final List<LocalAddress> found = <LocalAddress>[];

  // Loopback is asked for deliberately: when nothing usable is found, the
  // message lists everything the machine has, and a list that silently omits
  // the one interface that is up would read as a fault in the tool.
  for (final NetworkInterface adapter in await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: true,
  )) {
    for (final InternetAddress address in adapter.addresses) {
      found.add(
        LocalAddress(interfaceName: adapter.name, address: address.address),
      );
    }
  }

  final List<LocalAddress> reachable = reachableHosts(found);

  if (reachable.isEmpty) {
    out.writeln('No address on this machine that a phone could reach.');
    out.writeln('Every interface was loopback, link-local, or virtual:');
    for (final LocalAddress candidate in found) {
      out.writeln('  $candidate');
    }
    out.writeln('');
    out.writeln('Connect this machine to the network the phone is on, or pass');
    out.writeln(
      'the address yourself:  dart run tool/dev_config.dart --host=…',
    );
    return null;
  }

  if (reachable.length > 1) {
    // Several plausible answers and no way to tell from here which one the
    // phone is on. Guessing would reproduce the fault this file exists to
    // prevent, so it asks instead.
    out.writeln('More than one address a phone could be on:');
    for (final LocalAddress candidate in reachable) {
      out.writeln('  $candidate');
    }
    out.writeln('');
    out.writeln(
      'Pick one:  dart run tool/dev_config.dart --host=${reachable.first.address}',
    );
    return null;
  }

  out.writeln('Found ${reachable.single}');
  return reachable.single.address;
}

Map<String, String> _options(List<String> arguments) {
  final Map<String, String> parsed = <String, String>{};

  for (final String argument in arguments) {
    if (!argument.startsWith('--')) continue;

    final int equals = argument.indexOf('=');
    if (equals == -1) {
      parsed[argument.substring(2)] = '';
      continue;
    }

    parsed[argument.substring(2, equals)] = argument.substring(equals + 1);
  }

  return parsed;
}

const String _usage = '''
Writes the LAN address a phone should talk to into a build config file.

  dart run tool/dev_config.dart [--host=192.168.1.13] [--port=4000] [--out=path]

Then:

  flutter run --dart-define-from-file=config/merzox.dev.json
''';

Future<void> main(List<String> arguments) async {
  exitCode = await run(arguments, out: stdout);
}
