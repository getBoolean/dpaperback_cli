import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart';
import 'package:dpaperback_cli/src/time_mixin.dart';
import 'package:riverpod/riverpod.dart';

class Clean extends Command<int> {
  final ProviderContainer container;
  Clean([ProviderContainer? container]) : container = container ?? ProviderContainer() {
    argParser
      ..addSeparator('Flags:')
      ..addOption(
        'target',
        abbr: 't',
        help: 'The directory with generated output from the build process',
        defaultsTo: './',
      );
  }
  @override
  String get description => 'Deletes the bundles directory and the versioning file';

  @override
  String get name => 'clean';

  @override
  List<String> get aliases => [];

  @override
  Future<int> run() async {
    final results = argResults;
    if (results == null) return 0;

    final target = parseTargetPath(results);

    return CleanCli(
      target: target,
      container: container,
    ).run();
  }

  String parseTargetPath(ArgResults command) {
    final targetArgument = command['target'] as String;
    final targetPath = canonicalize(targetArgument);
    if (!exists(targetPath)) {
      print(red('The target directory "$targetArgument" could not be found'));
      exit(2);
    }

    return targetPath;
  }
}

class CleanCli with CommandTime {
  final String target;
  final ProviderContainer container;

  CleanCli({required this.target, required this.container});

  Future<int> run() async {
    final bundles = join(target, 'bundles');
    if (await Directory(bundles).exists()) {
      await Directory(bundles).delete(recursive: true);
    }

    final tempBuild = join(target, 'temp_build');
    if (await Directory(tempBuild).exists()) {
      await Directory(tempBuild).delete(recursive: true);
    }

    final localChromium = join(target, '.local-chromium');
    if (await Directory(localChromium).exists()) {
      await Directory(localChromium).delete(recursive: true);
    }

    return 0;
  }
}
