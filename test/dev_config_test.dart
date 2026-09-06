import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/dev_config.dart' as dev_config;
import '../tool/dev_config/host_selection.dart';

/// The address a physical device is given.
///
/// A phone can use neither of the app's fallbacks: `10.0.2.2` is the Android
/// emulator's alias for its host's loopback and `127.0.0.1` is the phone's
/// own. It has always needed the workstation's LAN address, and the last time
/// that address lived anywhere it lived in the source, went stale when the
/// router handed out a different number, and read as "the server is
/// unreachable" while the server was up.
///
/// So the rule under test is not which address is right today. It is that the
/// answer is read off the machine, that an address no phone could reach is
/// never offered, and that an ambiguous machine is asked rather than guessed
/// at - guessing is how the fault happened.

class _Captured implements IOSink {
  final StringBuffer buffer = StringBuffer();

  String get text => buffer.toString();

  @override
  void writeln([Object? object = '']) => buffer.writeln(object);

  @override
  void write(Object? object) => buffer.write(object);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

LocalAddress _at(String address, {String on = 'Wi-Fi'}) =>
    LocalAddress(interfaceName: on, address: address);

void main() {
  group('which addresses a phone could reach', () {
    test('the machine own loopback is not one of them', () {
      // Whoever asks, 127.0.0.1 means the asker - which for a phone is the
      // phone. It falls out of the private-range rule rather than needing one
      // of its own.
      expect(
        reachableHosts(<LocalAddress>[
          _at('127.0.0.1', on: 'Loopback Pseudo-Interface 1'),
        ]),
        isEmpty,
      );
    });

    test('a link-local address is a failed lease, not an address', () {
      // 169.254.x.x is what an interface holds when it never got one.
      // Offering it would send the build at a number that answers nothing.
      expect(reachableHosts(<LocalAddress>[_at('169.254.238.95')]), isEmpty);
    });

    test('a virtual switch is skipped however plausible its address', () {
      // This workstation offers two, and either would look like a real answer
      // and fail exactly the way the stale address did.
      final List<LocalAddress> reachable = reachableHosts(<LocalAddress>[
        _at('192.168.75.1', on: 'VMware Network Adapter VMnet1'),
        _at('192.168.2.1', on: 'VMware Network Adapter VMnet8'),
      ]);

      expect(reachable, isEmpty);
    });

    test('the real machine leaves exactly one answer', () {
      // The interfaces this workstation actually reports, in the order Dart
      // reports them.
      final List<LocalAddress> reachable = reachableHosts(<LocalAddress>[
        _at('192.168.75.1', on: 'VMware Network Adapter VMnet1'),
        _at('192.168.2.1', on: 'VMware Network Adapter VMnet8'),
        _at('192.168.1.13', on: 'شبكة Wi-Fi 6'),
        _at('127.0.0.1', on: 'Loopback Pseudo-Interface 1'),
      ]);

      expect(reachable.single.address, '192.168.1.13');
    });

    test('a public address is not a development host', () {
      expect(reachableHosts(<LocalAddress>[_at('93.184.216.34')]), isEmpty);
    });

    test('the private ranges are the whole of the private ranges', () {
      for (final String inside in <String>[
        '10.0.0.1',
        '10.255.255.254',
        '172.16.0.1',
        '172.31.255.254',
        '192.168.1.13',
      ]) {
        expect(isPrivateIPv4(inside), isTrue, reason: inside);
      }

      for (final String outside in <String>[
        '172.15.0.1',
        '172.32.0.1',
        '11.0.0.1',
        '192.169.0.1',
      ]) {
        expect(isPrivateIPv4(outside), isFalse, reason: outside);
      }
    });

    test('nonsense is not quietly accepted as an address', () {
      for (final String rubbish in <String>[
        '',
        '192.168.1',
        '192.168.1.256',
        '192.168.1.a',
        '192.168.1.13.7',
      ]) {
        expect(isPrivateIPv4(rubbish), isFalse, reason: rubbish);
      }
    });

    test('the order the machine reported is kept', () {
      final List<LocalAddress> reachable = reachableHosts(<LocalAddress>[
        _at('192.168.1.13', on: 'Wi-Fi'),
        _at('10.0.0.7', on: 'Ethernet'),
      ]);

      expect(reachable.map((LocalAddress a) => a.address), <String>[
        '192.168.1.13',
        '10.0.0.7',
      ]);
    });
  });

  group('what gets written', () {
    test('the file is the shape the build flag expects', () {
      final Object? parsed = jsonDecode(
        renderDevConfig(baseUrl: 'http://192.168.1.13:4000/api/v1'),
      );

      // A flat object of define names to strings: anything else and
      // `--dart-define-from-file` rejects it.
      expect(parsed, isA<Map<String, dynamic>>());
      expect(
        (parsed! as Map<String, dynamic>)['MERZOX_API_BASE_URL'],
        'http://192.168.1.13:4000/api/v1',
      );
    });

    test('the define is named exactly what the app reads', () {
      // Renaming either side without the other is a build that silently falls
      // back to the emulator alias again.
      expect(renderDevConfig(baseUrl: 'x'), contains('"MERZOX_API_BASE_URL"'));
    });

    test('the url carries the api prefix the client expects', () {
      expect(
        devBaseUrl('192.168.1.13', 4000),
        'http://192.168.1.13:4000/api/v1',
      );
    });
  });

  group('running it', () {
    late Directory scratch;

    setUp(() async {
      scratch = await Directory.systemTemp.createTemp('merzox-dev-config');
    });

    tearDown(() async {
      if (scratch.existsSync()) await scratch.delete(recursive: true);
    });

    test('a given host is written without consulting the machine', () async {
      final String out = '${scratch.path}/nested/merzox.dev.json';
      final _Captured log = _Captured();

      final int code = await dev_config.run(<String>[
        '--host=192.168.1.99',
        '--out=$out',
      ], out: log);

      expect(code, 0);
      expect(jsonDecode(File(out).readAsStringSync()), <String, dynamic>{
        'MERZOX_API_BASE_URL': 'http://192.168.1.99:4000/api/v1',
      });
    });

    test('it says the command to run next', () async {
      final String out = '${scratch.path}/merzox.dev.json';
      final _Captured log = _Captured();

      await dev_config.run(<String>[
        '--host=192.168.1.99',
        '--out=$out',
      ], out: log);

      // The file is useless without the flag that reads it, and the flag is
      // the part a developer will not remember.
      expect(log.text, contains('--dart-define-from-file=$out'));
    });

    test(
      'the port can be moved, because the backend has moved before',
      () async {
        final String out = '${scratch.path}/merzox.dev.json';

        await dev_config.run(<String>[
          '--host=192.168.1.99',
          '--port=3000',
          '--out=$out',
        ], out: _Captured());

        expect(File(out).readAsStringSync(), contains(':3000/api/v1'));
      },
    );

    test('a port that is not a port is refused, not written', () async {
      final String out = '${scratch.path}/merzox.dev.json';
      final _Captured log = _Captured();

      final int code = await dev_config.run(<String>[
        '--host=192.168.1.99',
        '--port=seventy',
        '--out=$out',
      ], out: log);

      expect(code, 2);
      expect(File(out).existsSync(), isFalse);
      expect(log.text, contains('seventy'));
    });

    test('the default port is the one the backend listens on', () {
      expect(dev_config.kDefaultPort, 4000);
    });

    test('the default output is the path the ignore rule names', () {
      // If these two ever disagree, one machine's LAN address gets committed.
      expect(dev_config.kDefaultOutput, 'config/merzox.dev.json');
      expect(
        File('.gitignore').readAsStringSync(),
        contains(dev_config.kDefaultOutput),
      );
    });

    test('every way of launching the app names the same file', () async {
      // Android Studio and VS Code each build their own command line, so a
      // flag typed at a terminal never reaches a build started with the Run
      // button - which is how a phone came to be dialling 10.0.2.2 with the
      // config file sitting right there, generated and correct.
      final String flag =
          '--dart-define-from-file=${dev_config.kDefaultOutput}';

      expect(
        File('.run/merzox (dev API).run.xml').readAsStringSync(),
        contains(flag),
      );
      expect(File('.vscode/launch.json').readAsStringSync(), contains(flag));
      expect(File('README.md').readAsStringSync(), contains(flag));
      expect(File('config/README.md').readAsStringSync(), contains(flag));
    });

    test('the IDE configurations are the shape their editors read', () {
      final String studio = File(
        '.run/merzox (dev API).run.xml',
      ).readAsStringSync();

      // Verified against the plugin's own SdkFields, which serialises exactly
      // these option names: a typo here is a configuration that loads and
      // silently drops the flag.
      expect(studio, contains('type="FlutterRunConfigurationType"'));
      expect(studio, contains('<option name="additionalArgs"'));
      expect(studio, contains('<option name="filePath"'));

      final Object? code = jsonDecode(
        File('.vscode/launch.json').readAsStringSync()
        // launch.json permits comments; jsonDecode does not.
        .replaceAll(RegExp(r'^\s*//.*$', multiLine: true), ''),
      );
      final List<dynamic> launches =
          (code! as Map<String, dynamic>)['configurations'] as List<dynamic>;

      expect((launches.single as Map<String, dynamic>)['toolArgs'], <String>[
        '--dart-define-from-file=${dev_config.kDefaultOutput}',
      ]);
    });

    test('help explains itself and writes nothing', () async {
      final String out = '${scratch.path}/merzox.dev.json';
      final _Captured log = _Captured();

      final int code = await dev_config.run(<String>[
        '--help',
        '--host=192.168.1.99',
        '--out=$out',
      ], out: log);

      expect(code, 0);
      expect(File(out).existsSync(), isFalse);
      expect(log.text, contains('--dart-define-from-file'));
    });
  });
}
