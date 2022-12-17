import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart';
import 'package:dpaperback_cli/src/time_mixin.dart';

class Clean extends Command<int> with CommandTime {
  Clean() {
    argParser
      ..addSeparator('Flags:')
      ..addOption('target', abbr: 't', help: 'The directory with sources.', defaultsTo: 'lib');
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

  int run() {
    return 0;
  }
}
