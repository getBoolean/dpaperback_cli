import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart';
import 'package:dpaperback_cli/src/utils/time_mixin.dart';
import 'package:riverpod/riverpod.dart';

class Clean extends Command<int> {
  final ProviderContainer container;
  Clean([ProviderContainer? container]) : container = container ?? ProviderContainer() {
    argParser
      ..addSeparator('Flags:')
      ..addOption(
        'dir',
        abbr: 'd',
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

    final dir = parseDirPath(results);

    return CleanCli(
      dir: dir,
      container: container,
    ).run();
  }

  String parseDirPath(ArgResults command) {
    final dirArgument = command['dir'] as String;
    final dirPath = canonicalize(dirArgument);
    if (!exists(dirPath)) {
      print(red('The directory "$dirArgument" could not be found'));
      exit(2);
    }

    return dirPath;
  }
}

class CleanCli with CommandTime {
  final String dir;
  final ProviderContainer container;

  CleanCli({required this.dir, required this.container});

  Future<int> run() async {
    final bundles = join(dir, 'bundles');
    if (Directory(bundles).existsSync()) {
      await Directory(bundles).delete(recursive: true);
    }

    final tempBuild = join(dir, 'temp_build');
    if (Directory(tempBuild).existsSync()) {
      await Directory(tempBuild).delete(recursive: true);
    }

    final localChromium = join(dir, '.local-chromium');
    if (Directory(localChromium).existsSync()) {
      await Directory(localChromium).delete(recursive: true);
    }

    final paperbackCache = join(dir, '.pb_cache');
    if (Directory(paperbackCache).existsSync()) {
      await Directory(paperbackCache).delete(recursive: true);
    }

    return 0;
  }
}
