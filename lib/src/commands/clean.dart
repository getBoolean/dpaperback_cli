import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart';
import 'package:dpaperback_cli/src/time_mixin.dart';

class Clean extends Command<int> {
  Clean() {
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

    return CleanCli(target).run();
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

  CleanCli(this.target);

  Future<int> run() async {
    final bundles = join(target, 'bundles');
    if (exists(bundles)) {
      await Directory(bundles).delete(recursive: true);
    }

    final tempBuild = join(target, 'temp_build');
    if (exists(tempBuild)) {
      await Directory(tempBuild).delete(recursive: true);
    }

    final localChromium = join(target, '.local-chromium');
    if (exists(localChromium)) {
      await Directory(localChromium).delete(recursive: true);
    }

    return 0;
  }
}
