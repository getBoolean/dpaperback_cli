import 'dart:io';

import 'package:dcli/dcli.dart';
import 'package:dpaperback_cli/dpaperback_cli.dart';

void main(List<String> arguments) {
  exitCode = 0; // presume success

  final cli = DartPaperbackCli();
  final ArgResults results = cli.baseParser.parse(arguments);

  cli.verbose = results['verbose'] as bool;
  final help = results['help'] as bool;

  final command = results.command;
  if (help && command == null) {
    cli.printUsage();
    exit(0);
  }

  if (results.rest.isNotEmpty) {
    print(red('\nInvalid command: "${results.rest.join(' ')}"'));
    cli.printUsage();
    exit(1);
  }

  if (command == null) {
    print(red('\nYou must pass the name of the command to use.'));
    cli.printUsage();
    exit(1);
  }

  cli.verbose = cli.verbose || (command['verbose'] is bool ? command['verbose'] as bool : false);

  final shouldShowHelp = help || (command['help'] is bool ? command['help'] as bool : false);
  if (shouldShowHelp) {
    cli.printCommandUsage(command.name ?? '<command>');
    exit(0);
  }

  cli.dpaperback(command);
}
