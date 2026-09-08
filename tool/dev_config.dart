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
/// Two files are written from that one address. The app is given the API's
/// base; the server is given the same origin as `PUBLIC_BASE_URL`, which is
/// what it puts in front of the verification link it mails out. That link used
/// to be built from a `${CURRENT_IP_ADDRESS}` template the reader never
/// expanded, so it fell back to loopback and arrived pointing at whichever
/// machine opened it. Writing both from here is what keeps them one answer.
///
/// `--host` overrides the choosing entirely, for a machine where the automatic
/// answer is wrong or ambiguous. `--port` defaults to the port the backend
/// listens on. `--no-env` writes the app's file only.
const String kDefaultOutput = 'config/merzox.dev.json';
const String kDefaultEnvOutput = 'backend/.env';
const int kDefaultPort = 4000;

Future<int> run(List<String> arguments, {required IOSink out}) async {
  final Map<String, String> options = _options(arguments);

  if (options.containsKey('help')) {
    out.writeln(_usage);
    return 0;
  }

  final String output = options['out'] ?? kDefaultOutput;
  final String envOutput = options['env'] ?? kDefaultEnvOutput;
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

  if (!options.containsKey('no-env')) {
    await _writeServerOrigin(
      envOutput: envOutput,
      origin: devOrigin(host, port),
      out: out,
    );
  }

  out.writeln('');
  out.writeln('Run the app with:');
  out.writeln('  flutter run --dart-define-from-file=$output');

  return 0;
}

/// Puts the same address in the server's environment file.
///
/// An absent file is reported rather than created. That file is also where the
/// database URI and the mail password live, so one containing a single setting
/// would be a server that cannot start, handed over as though something had
/// been done for it.
Future<void> _writeServerOrigin({
  required String envOutput,
  required String origin,
  required IOSink out,
}) async {
  final File env = File(envOutput);

  if (!env.existsSync()) {
    out.writeln('');
    out.writeln('No $envOutput, so $kPublicBaseUrlKey was left alone.');
    out.writeln('That file holds the database URI and the mail account too,');
    out.writeln('so this will not invent one: copy backend/.env.example and');
    out.writeln('fill it in, then run this again.');
    return;
  }

  await env.writeAsString(
    withPublicBaseUrl(await env.readAsString(), origin),
    flush: true,
  );

  out.writeln('Wrote $envOutput');
  out.writeln('  $kPublicBaseUrlKey=$origin');
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
Writes the LAN address a phone should talk to into the app's build config, and
the same address into the server's environment as PUBLIC_BASE_URL.

  dart run tool/dev_config.dart [--host=192.168.1.13] [--port=4000]
                                [--out=path] [--env=path] [--no-env]

Then:

  flutter run --dart-define-from-file=config/merzox.dev.json
''';

Future<void> main(List<String> arguments) async {
  exitCode = await run(arguments, out: stdout);
}
