# Build configuration

`merzox.dev.json` names the API a development build talks to. It is read at
build time by `--dart-define-from-file`, which feeds the same defines the app
already reads, so nothing in the app changes because of it.

It is not committed. The address in it is one machine's place on one router,
and a committed copy would be wrong for the next person and eventually for the
person who wrote it - which is exactly the fault this replaced. Generate your
own instead of copying the example:

```powershell
dart run tool/dev_config.dart
flutter run --dart-define-from-file=config/merzox.dev.json
```

The generator reads the address off this machine rather than asking you to
type it, skipping loopback, link-local and virtual adapters. If it finds more
than one candidate it lists them and asks, rather than guessing. It writes the
same address into `backend/.env` as `PUBLIC_BASE_URL`, which is what the
server puts in front of the verification link it mails, so the address a phone
dials and the address an email names cannot drift apart.

## When the network is slow

`MERZOX_API_TIMEOUT_MS` is the second define this file may carry, and it is
optional. A request is given ten seconds when nothing says otherwise, and that
is what ships; the define exists because the server is only as near as the
network you are on. On one network the database sat 600ms away and a plain
list took four and a half seconds - close enough to the limit that requests
crossed it and read as "the server is unreachable" with nothing wrong on
either side.

Add it beside the address when that happens:

```json
{
  "MERZOX_API_BASE_URL": "http://192.168.1.13:4000/api/v1",
  "MERZOX_API_TIMEOUT_MS": "30000"
}
```

It is milliseconds, and a value under a thousand is read as nothing said -
`30` is a plausible way to write "thirty seconds" into a field whose name ends
in MS, and honoured literally it would fail every request.

Re-running the generator keeps it. That command only knows the address, so it
rewrites that line and carries everything else in the file over.

Re-run it whenever the router hands out a different number. That is the first
thing to try when a physical device says the server is unreachable: the
emulator and the desktop both fall back to fixed names for "this machine", and
a phone is on neither of them.

## Running from an IDE

Android Studio and VS Code build their own command line from a run
configuration, so the flag above never reaches a build started with the Run
button. Pressing Run with the auto-created `main.dart` configuration produces a
build with no `MERZOX_API_BASE_URL` at all — it falls back to `10.0.2.2`, and
on a physical device nothing answers there.

Two shared configurations are committed for this, both named
**merzox (dev API)**: [.run/](../.run/) for Android Studio and
[.vscode/launch.json](../.vscode/launch.json) for VS Code. Pick that one from
the configuration dropdown rather than `main.dart`.

To add the flag to a configuration you already have, put it in the run
configuration's own arguments field — *Additional run args* in Android Studio,
`toolArgs` in `launch.json`:

```
--dart-define-from-file=config/merzox.dev.json
```
