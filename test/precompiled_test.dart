import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../hook/precompiled.dart';

void main() {
  const package = 'wear_net';
  const target = 'aarch64-apple-darwin';
  const filename = 'lib$package.dylib';
  final content = utf8.encode('test native library');
  late Directory temporary;
  late Directory output;
  late File configuration;
  late HttpServer server;
  late List<int> response;
  late int status;
  late int requests;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('native-release-test-');
    output = Directory.fromUri(temporary.uri.resolve('output/'));
    configuration = File.fromUri(temporary.uri.resolve('native_release.json'));
    final hash = sha256.convert(content).toString();
    final archive = Archive()
      ..addFile(ArchiveFile('lib/$filename', content.length, content));
    final manifest = utf8.encode(
      jsonEncode({
        'target': target,
        'abi': 1,
        'library': filename,
        'sha256': hash,
      }),
    );
    archive.addFile(ArchiveFile('manifest.json', manifest.length, manifest));
    response = ZipEncoder().encode(archive);
    await configuration.writeAsString(
      jsonEncode({
        'repository': 'OrPudding/$package',
        'tag': 'v0.1.0',
        'libraries': {
          target: {
            'archiveSha256': sha256.convert(response).toString(),
            'librarySha256': hash,
          },
        },
      }),
    );
    requests = 0;
    status = HttpStatus.ok;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests++;
      expect(request.uri.path, '/$package-$target.zip');
      request.response.statusCode = status;
      request.response.add(response);
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    await temporary.delete(recursive: true);
  });

  Future<File> load() => precompiledLibrary(
    configuration: configuration,
    output: output,
    package: package,
    target: target,
    releaseBase: Uri.parse('http://127.0.0.1:${server.port}/'),
  );

  test('downloads verified library and reuses it without networking', () async {
    final library = await load();
    expect(await library.readAsBytes(), content);
    expect((await load()).path, library.path);
    expect(requests, 1);
  });

  test('replaces a corrupted cached library', () async {
    final library = await load();
    await library.writeAsString('interrupted download');
    expect(await (await load()).readAsBytes(), content);
    expect(requests, 2);
  });

  test('rejects corrupted archives and permits a later retry', () async {
    final valid = response;
    response = utf8.encode('invalid archive');
    await expectLater(load(), throwsFormatException);
    response = valid;
    expect(await (await load()).readAsBytes(), content);
  });

  test('reports failed downloads without caching an error page', () async {
    status = HttpStatus.serviceUnavailable;
    await expectLater(load(), throwsA(isA<HttpException>()));
    status = HttpStatus.ok;
    expect(await (await load()).readAsBytes(), content);
  });

  test('rejects mismatched library hashes inside a verified archive', () async {
    final config =
        jsonDecode(await configuration.readAsString()) as Map<String, dynamic>;
    config['libraries'][target]['librarySha256'] = '0' * 64;
    await configuration.writeAsString(jsonEncode(config));
    await expectLater(load(), throwsFormatException);
  });

  test('selects all shipped targets and rejects unsupported targets', () {
    const targets = {
      ('android', 'arm'): 'armv7-linux-androideabi',
      ('android', 'arm64'): 'aarch64-linux-android',
      ('android', 'x64'): 'x86_64-linux-android',
      ('linux', 'arm64'): 'aarch64-unknown-linux-gnu',
      ('linux', 'x64'): 'x86_64-unknown-linux-gnu',
      ('macos', 'arm64'): 'aarch64-apple-darwin',
      ('macos', 'x64'): 'x86_64-apple-darwin',
      ('windows', 'x64'): 'x86_64-pc-windows-msvc',
    };
    for (final entry in targets.entries) {
      expect(releaseTarget(entry.key.$1, entry.key.$2), entry.value);
    }
    expect(() => releaseTarget('ios', 'arm64'), throwsUnsupportedError);
    expect(() => releaseTarget('windows', 'arm64'), throwsUnsupportedError);
  });
}
