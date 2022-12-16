import 'dart:io';

import 'package:dcli/dcli.dart';
import 'package:dpaperback_cli/src/commands/bundle.dart';
import 'package:dpaperback_cli/src/commands/server.dart';
import 'package:path/path.dart' as path;

class DartPaperbackCli {
  bool verbose = false;

  final bundleParser = ArgParser()
    ..addSeparator('Flags:')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Print this usage information.')
    ..addFlag('verbose',
        abbr: 'v', defaultsTo: false, negatable: false, help: 'Enable verbose logging.')
    ..addOption('output',
        abbr: 'o', help: 'The output directory.', defaultsTo: 'modules', valueHelp: 'folder')
    ..addOption('target',
        abbr: 't', help: 'The directory with sources.', defaultsTo: 'lib', valueHelp: 'folder')
    ..addOption('source', abbr: 's', help: 'Bundle a single source.', valueHelp: 'source name');

  final serveParser = ArgParser()
    ..addSeparator('Flags:')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Print this usage information.')
    ..addFlag('verbose',
        abbr: 'v', defaultsTo: false, negatable: false, help: 'Enable verbose logging.')
    ..addOption('output',
        abbr: 'o', help: 'The output directory.', defaultsTo: 'modules', valueHelp: 'folder')
    ..addOption('target',
        abbr: 't', help: 'The directory with sources.', defaultsTo: 'lib', valueHelp: 'folder')
    ..addOption('ip', valueHelp: 'value')
    ..addOption('port', abbr: 'p', defaultsTo: '27015', valueHelp: 'value');

  final cleanParser = ArgParser()
    ..addSeparator('Flags:')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Print this usage information.')
    ..addFlag('verbose',
        abbr: 'v', defaultsTo: false, negatable: false, help: 'Enable verbose logging.')
    ..addOption('target', abbr: 't', help: 'The directory with sources.', defaultsTo: 'lib');

  late final baseParser = ArgParser(allowTrailingOptions: false)
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Print this usage information.')
    ..addFlag('verbose',
        abbr: 'v', defaultsTo: false, negatable: false, help: 'Enable verbose logging.')
    ..addCommand('bundle', bundleParser)
    ..addCommand('serve', serveParser)
    ..addCommand('clean', cleanParser);

  void printUsage() {
    print(green('\nUsage: dpaperback <command> [arguments]'));
    print(green('\nFlags:'));
    print(green(baseParser.usage));
    print(green('\nCommands:'));
    print(green(
        '   bundle          Builds all the sources in the repository and generates a versioning file'));
    print(green('   serve           Build the sources and start a local server'));
    print(green('   clean           Deletes the modules directory and the versioning file'));
  }

  String commandUsage(String command) {
    switch (command) {
      case 'bundle':
        return bundleParser.usage;
      case 'serve':
        return serveParser.usage;
      case 'clean':
        return cleanParser.usage;
      default:
        return baseParser.usage;
    }
  }

  void printCommandUsage(String command) {
    print(green('\nUsage: dpaperback $command [arguments]\n'));
    print(green(commandUsage(command)));
  }

  void dpaperback(ArgResults command) {
    print('Working directory: $pwd\n');

    switch (command.name) {
      case 'bundle':
        bundle(command);
        break;
      case 'serve':
        serve(command);
        break;
      case 'clean':
        clean(command);
        break;
    }
  }

  void bundle(ArgResults command) {
    print(blue('Building Sources\n'));

    final output = parseOutputPath(command);
    final target = parseTargetPath(command);
    final source = command['source'] as String?;
    return Bundle(output, target, source).run();
  }

  void serve(ArgResults command) {
    print(blue('Building Sources\n'));
    final output = parseOutputPath(command);
    final target = parseTargetPath(command);
    final port = command['port'];

    final parsedPort = int.tryParse(port);
    if (parsedPort == null || parsedPort < 1 || parsedPort > 65535) {
      print(red('The port "$port" is not a valid port number. It must be between 1 and 65535.'));
      exit(2);
    }

    Server(output, target, parsedPort).run();
  }

  void clean(ArgResults command) {
    print(blue('Cleaning...'));

    final target = parseTargetPath(command);
  }

  String parseTargetPath(ArgResults command) {
    final targetArgument = command['target'] as String;
    final targetPath = path.canonicalize(targetArgument);
    if (!exists(targetPath)) {
      print(red('The target directory "$targetArgument" could not be found'));
      exit(2);
    }

    return targetPath;
  }

  String parseOutputPath(ArgResults command) {
    final outputArgument = command['output'] as String;
    final outputPath = path.canonicalize(outputArgument);

    return createDir(outputPath, recursive: true);
  }
}
