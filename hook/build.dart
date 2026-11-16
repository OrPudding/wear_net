import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

import 'precompiled.dart';

Future<void> main(List<String> args) => build(args, (input, output) async {
  if (!input.config.buildCodeAssets) return;
  final code = input.config.code;
  final target = releaseTarget(
    code.targetOS.name,
    code.targetArchitecture.name,
  );
  final override = input.userDefines.path('native_library');
  final File library;
  if (override != null) {
    library = File.fromUri(override);
    output.dependencies.add(override);
    if (!await library.exists()) {
      throw StateError(
        'Explicit native library does not exist: ${library.path}',
      );
    }
  } else {
    final release = input.packageRoot.resolve('native_release.json');
    output.dependencies.add(release);
    library = await precompiledLibrary(
      configuration: File.fromUri(release),
      output: Directory.fromUri(input.outputDirectory),
      package: input.packageName,
      target: target,
    );
  }
  output.assets.code.add(
    CodeAsset(
      package: input.packageName,
      name: input.packageName,
      linkMode: DynamicLoadingBundled(),
      file: library.uri,
    ),
  );
});
