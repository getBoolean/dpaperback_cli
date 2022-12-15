import 'dart:io';

import 'package:dcli/dcli.dart';
import 'package:dpaperback_cli/dpaperback_cli.dart';

void main(List<String> arguments) {
  exitCode = 0; // presume success
  final bundleParser = ArgParser()
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Print this usage information.',
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      defaultsTo: false,
      negatable: false,
      help: 'Enable verbose logging.',
    );
  final serveParser = ArgParser()
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Print this usage information.',
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      defaultsTo: false,
      negatable: false,
      help: 'Enable verbose logging.',
    );
  final cleanParser = ArgParser()
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Print this usage information.',
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      defaultsTo: false,
      negatable: false,
      help: 'Enable verbose logging.',
    );
  final baseParser = ArgParser(allowTrailingOptions: false)
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Print this usage information.',
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      defaultsTo: false,
      negatable: false,
      help: 'Enable verbose logging.',
    )
    ..addCommand('bundle', bundleParser)
    ..addCommand('serve', serveParser)
    ..addCommand('clean', cleanParser);

  final ArgResults results = baseParser.parse(arguments);

  final verbose = results['verbose'] as bool;
  final help = results['help'] as bool;

  final command = results.command;
  if (help && command == null) {
    printUsage(
      usage: baseParser.usage,
      verbose: verbose,
    );
    exit(0);
  }

  if (command == null) {
    print(red('\nYou must pass the name of the command to use.'));
    printUsage(
      usage: baseParser.usage,
      verbose: verbose,
    );
    exit(1);
  }

  final enableVerboseLogging = verbose || command['verbose'] as bool;
  final shouldShowHelp = help || command['help'] as bool;

  if (shouldShowHelp) {
    printCommandUsage(
      command: command,
      verbose: verbose,
      usage: command.name == 'bundle'
          ? bundleParser.usage
          : command.name == 'serve'
              ? serveParser.usage
              : command.name == 'clean'
                  ? cleanParser.usage
                  : baseParser.usage,
    );
    exit(0);
  }

  dpaperback(command, verbose: enableVerboseLogging);
}
