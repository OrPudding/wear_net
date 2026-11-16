import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

String releaseTarget(String os, String architecture) =>
    switch ((os, architecture)) {
      ('android', 'arm') => 'armv7-linux-androideabi',
      ('android', 'arm64') => 'aarch64-linux-android',
      ('android', 'x64') => 'x86_64-linux-android',
      ('linux', 'arm64') => 'aarch64-unknown-linux-gnu',
      ('linux', 'x64') => 'x86_64-unknown-linux-gnu',
      ('macos', 'arm64') => 'aarch64-apple-darwin',
      ('macos', 'x64') => 'x86_64-apple-darwin',
      ('windows', 'x64') => 'x86_64-pc-windows-msvc',
      _ => throw UnsupportedError(
        'No bundled native library for $os/$architecture',
      ),
    };

Future<File> precompiledLibrary({
  required File configuration,
  required Directory output,
  required String package,
  required String target,
  Uri? releaseBase,
}) async {
  final config =
      jsonDecode(await configuration.readAsString()) as Map<String, dynamic>;
  final entry =
      (config['libraries'] as Map<String, dynamic>)[target]
          as Map<String, dynamic>?;
  if (entry == null) {
    throw UnsupportedError('No $package release library for $target');
  }
  final filename = target.contains('windows')
      ? '$package.dll'
      : 'lib$package.${target.contains('apple-darwin') ? 'dylib' : 'so'}';
  final expectedHash = entry['librarySha256'] as String;
  final library = File.fromUri(
    output.uri.resolve('precompiled/$expectedHash/$filename'),
  );
  if (await library.exists() &&
      sha256.convert(await library.readAsBytes()).toString() == expectedHash) {
    return library;
  }
  final base =
      releaseBase ??
      Uri.https(
        'github.com',
        '/${config['repository']}/releases/download/${config['tag']}/',
      );
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 30)
    ..findProxy = HttpClient.findProxyFromEnvironment;
  try {
    final url = base.resolve('$package-$target.zip');
    final request = await client
        .getUrl(url)
        .timeout(const Duration(seconds: 30));
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Unable to download $package for $target: HTTP ${response.statusCode}',
        uri: url,
      );
    }
    final chunks = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(const Duration(minutes: 3))) {
      chunks.add(chunk);
    }
    final bytes = chunks.takeBytes();
    if (sha256.convert(bytes).toString() != entry['archiveSha256']) {
      throw FormatException(
        '$package release archive checksum mismatch for $target',
      );
    }
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    final manifest = jsonDecode(
      utf8.decode(archive.findFile('manifest.json')!.content),
    ) as Map<String, dynamic>;
    final content = archive.findFile('lib/$filename')!.content;
    if (manifest['target'] != target ||
        manifest['abi'] != 1 ||
        manifest['library'] != filename ||
        manifest['sha256'] != expectedHash ||
        sha256.convert(content).toString() != expectedHash) {
      throw FormatException(
        '$package release library metadata or checksum mismatch for $target',
      );
    }
    // A private staging directory keeps interrupted writes out of the cache.
    await library.parent.create(recursive: true);
    final staging = await library.parent.createTemp('.download-');
    try {
      final temporary = File.fromUri(staging.uri.resolve(filename));
      await temporary.writeAsBytes(content, flush: true);
      if (await library.exists()) await library.delete();
      await temporary.rename(library.path);
    } finally {
      await staging.delete(recursive: true);
    }
    return library;
  } finally {
    client.close(force: true);
  }
}
