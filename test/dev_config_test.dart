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
  // Several cases below drive the real entry point, whose defaults name files
  // in this repository. One that forgets to redirect them rewrites the
  // developer's own environment file - where the database URI and the mail
  // password live - and the damage is invisible until somebody opens it. That
  // happened once, while this very feature was being written.
  String? environmentBefore;

  String? readEnvironment() {
    final File env = File(dev_config.kDefaultEnvOutput);

    return env.existsSync() ? env.readAsStringSync() : null;
  }

  setUpAll(() => environmentBefore = readEnvironment());

  tearDownAll(() {
    expect(
      readEnvironment(),
      environmentBefore,
      reason: 'a test wrote to ${dev_config.kDefaultEnvOutput}',
    );
  });

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
        '--no-env',
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
        '--no-env',
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
          '--no-env',
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
        '--no-env',
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

  group('the address the server puts in an email', () {
    // `PUBLIC_BASE_URL` was written as `http://${CURRENT_IP_ADDRESS}:${PORT}`,
    // and the reader does not expand that - the expansion needs a package the
    // project does not carry. So the literal template failed validation, the
    // server fell back to loopback, and every verification link it mailed
    // pointed at whichever machine happened to open it. The address is
    // written here now, from the same answer the app's file gets.

    test('the server is given the origin, the app the api base', () {
      // Two settings, one address. `PUBLIC_BASE_URL` goes in FRONT of
      // `/api/v1/auth/verify-email`, so a prefix on it would be counted twice.
      expect(devOrigin('192.168.1.13', 4000), 'http://192.168.1.13:4000');
      expect(
        devBaseUrl('192.168.1.13', 4000),
        '${devOrigin('192.168.1.13', 4000)}/api/v1',
      );
    });

    test('the setting is rewritten and nothing around it is touched', () {
      // The line that has to survive intact is the one nobody wants to
      // retype: this file is where the database URI and the mail password
      // live, and rewriting it wholesale would take them with it.
      const String before = '''
PORT=4000
MONGODB_URI=mongodb://user:p\$\$w0rd@cluster.example.net:27017/merzox?ssl=true
PUBLIC_BASE_URL="http://\${CURRENT_IP_ADDRESS}:\${PORT}"
SMTP_PASS=an-app-password
''';

      final String after = withPublicBaseUrl(before, 'http://192.168.1.99:4000');

      expect(after, contains('PUBLIC_BASE_URL=http://192.168.1.99:4000'));
      expect(after, isNot(contains('CURRENT_IP_ADDRESS')));
      expect(
        after,
        contains(
          'MONGODB_URI=mongodb://user:p\$\$w0rd@cluster.example.net:27017/merzox?ssl=true',
        ),
      );
      expect(after, contains('SMTP_PASS=an-app-password'));
      expect(after, contains('PORT=4000'));
      expect(after.split('\n').length, before.split('\n').length);
    });

    test('a setting that is not there is added', () {
      final String after = withPublicBaseUrl(
        'PORT=4000\n',
        'http://192.168.1.99:4000',
      );

      expect(after, 'PORT=4000\nPUBLIC_BASE_URL=http://192.168.1.99:4000\n');
    });

    test('a file with no trailing newline still gets one', () {
      expect(
        withPublicBaseUrl('PORT=4000', 'http://10.0.0.5:4000'),
        'PORT=4000\nPUBLIC_BASE_URL=http://10.0.0.5:4000\n',
      );
    });

    test('a commented-out setting stays commented out', () {
      // Uncommenting somebody's note would turn a remark into configuration.
      final String after = withPublicBaseUrl(
        '# PUBLIC_BASE_URL=http://localhost:3000\nPORT=4000\n',
        'http://192.168.1.99:4000',
      );

      expect(after, contains('# PUBLIC_BASE_URL=http://localhost:3000'));
      expect(after, contains('\nPUBLIC_BASE_URL=http://192.168.1.99:4000\n'));
    });

    test('every uncommented copy is made to agree', () {
      // Which one the reader honours is its business, not ours. Making them
      // say the same thing is what stops the answer depending on that.
      final String after = withPublicBaseUrl(
        'PUBLIC_BASE_URL=http://one\nPORT=4000\nPUBLIC_BASE_URL=http://two\n',
        'http://192.168.1.99:4000',
      );

      expect(after, isNot(contains('http://one')));
      expect(after, isNot(contains('http://two')));
      expect(
        'PUBLIC_BASE_URL=http://192.168.1.99:4000'.allMatches(after).length,
        2,
      );
    });

    test('a file written with Windows endings keeps them', () {
      // Rewriting one line in LF would leave a single odd line in a file the
      // rest of which is CRLF, which is a diff nobody asked for.
      final String after = withPublicBaseUrl(
        'PORT=4000\r\nPUBLIC_BASE_URL=http://old\r\nSMTP_PASS=x\r\n',
        'http://192.168.1.99:4000',
      );

      expect(after, 'PORT=4000\r\nPUBLIC_BASE_URL=http://192.168.1.99:4000\r\nSMTP_PASS=x\r\n');
    });
  });

  group('writing both files', () {
    late Directory scratch;

    setUp(() async {
      scratch = await Directory.systemTemp.createTemp('merzox-dev-config-env');
    });

    tearDown(() async {
      if (scratch.existsSync()) await scratch.delete(recursive: true);
    });

    test('one run gives the app and the server the same address', () async {
      final String out = '${scratch.path}/merzox.dev.json';
      final String env = '${scratch.path}/.env';
      File(env).writeAsStringSync('PORT=4000\nPUBLIC_BASE_URL=http://stale\n');

      final int code = await dev_config.run(<String>[
        '--host=192.168.1.99',
        '--out=$out',
        '--env=$env',
      ], out: _Captured());

      expect(code, 0);
      expect(
        jsonDecode(File(out).readAsStringSync()),
        <String, dynamic>{
          'MERZOX_API_BASE_URL': 'http://192.168.1.99:4000/api/v1',
        },
      );
      expect(
        File(env).readAsStringSync(),
        contains('PUBLIC_BASE_URL=http://192.168.1.99:4000'),
      );
    });

    test('a missing environment file is reported, never invented', () async {
      // A file holding nothing but this setting is a server that cannot
      // start, handed over as though something had been done for it.
      final String out = '${scratch.path}/merzox.dev.json';
      final String env = '${scratch.path}/absent/.env';
      final _Captured log = _Captured();

      final int code = await dev_config.run(<String>[
        '--host=192.168.1.99',
        '--out=$out',
        '--env=$env',
      ], out: log);

      expect(code, 0);
      expect(File(env).existsSync(), isFalse);
      expect(log.text, contains('backend/.env.example'));
      // The half that did work still says so.
      expect(File(out).existsSync(), isTrue);
    });

    test('the server file can be left out of it', () async {
      final String out = '${scratch.path}/merzox.dev.json';
      final String env = '${scratch.path}/.env';
      File(env).writeAsStringSync('PUBLIC_BASE_URL=http://untouched\n');

      await dev_config.run(<String>[
        '--host=192.168.1.99',
        '--out=$out',
        '--env=$env',
        '--no-env',
      ], out: _Captured());

      expect(File(env).readAsStringSync(), contains('http://untouched'));
    });

    test('the default server file is the one the ignore rule names', () {
      // If these two ever disagree, one machine's LAN address and the mail
      // password beside it get committed.
      expect(dev_config.kDefaultEnvOutput, 'backend/.env');
      expect(
        File('.gitignore').readAsStringSync(),
        contains(dev_config.kDefaultEnvOutput),
      );
    });

    test('the key written is the one the server reads', () {
      // Renaming either side without the other puts the server back on
      // loopback with a warning nobody reads.
      expect(kPublicBaseUrlKey, 'PUBLIC_BASE_URL');
      expect(
        File('backend/src/config/environment.js').readAsStringSync(),
        contains("'$kPublicBaseUrlKey'"),
      );
    });
  });
}
