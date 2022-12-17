import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart';
import 'package:dpaperback_cli/src/time_mixin.dart';

class Server extends Command<int> with CommandTime {
  Server() {
    argParser
      ..addSeparator('Flags:')
      ..addOption('output',
          abbr: 'o', help: 'The output directory.', defaultsTo: './', valueHelp: 'folder')
      ..addOption('target',
          abbr: 't', help: 'The directory with sources.', defaultsTo: 'lib', valueHelp: 'folder')
      ..addOption(
        'paperback-extensions-common',
        abbr: 'c',
        help: 'The Paperback Extensions Common Package and Version',
        valueHelp: ':package@:version',
        defaultsTo: kDefaultPaperbackExtensionsCommon,
      )
      ..addOption('ip', valueHelp: 'value')
      ..addOption('port', abbr: 'p', defaultsTo: '27015', valueHelp: 'value');
  }
  @override
  String get description => 'Build the sources and start a local server';

  @override
  String get name => 'serve';

  @override
  List<String> get aliases => ['server'];

  @override
  Future<int> run() async {
    final results = argResults;
    if (results == null) return 0;

    final output = parseOutputPath(results);
    final target = parseTargetPath(results);
    final commonsPackage = results['paperback-extensions-common'] as String;
    final port = results['port'];

    return ServerCli(output, target, port, commonsPackage).run();
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

  String parseOutputPath(ArgResults command) {
    final outputArgument = command['output'] as String;
    final outputPath = canonicalize(outputArgument);

    if (!exists(outputPath)) {
      createDir(outputPath, recursive: true);
    }
    return outputPath;
  }
}

class ServerCli with CommandTime {
  final String output;
  final String target;
  final String commonsUrl;
  final int port;

  ServerCli(this.output, this.target, this.port, this.commonsUrl);

  int run() {
    print(blue('\nStarting Server on port $port'));
    return 0;
  }
}
