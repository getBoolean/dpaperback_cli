import 'dart:io';

import 'package:cli_completion/cli_completion.dart';
import 'package:dcli/dcli.dart';
import 'package:dpaperback_cli/dpaperback_cli.dart';
import 'package:dpaperback_cli/src/commands/bundle.dart';
import 'package:dpaperback_cli/src/commands/clean.dart';
import 'package:dpaperback_cli/src/commands/server.dart';

Future<void> main(List<String> args) async {
  await _flushThenExit(await DartPaperbackCommandRunner().run(args));
}

/// Flushes the stdout and stderr streams, then exits the program with the given
/// status code.
///
/// This returns a Future that will never complete, since the program will have
/// exited already. This is useful to prevent Future chains from proceeding
/// after you've decided to exit.
Future<void> _flushThenExit(int status) {
  return Future.wait<void>([stdout.close(), stderr.close()]).then<void>((_) => exit(status));
}

const executableName = 'dpaperback';
const packageName = 'dpaperback_cli';
const description = 'A commandline tool for bundling and serving Paperback written in Dart.';

class DartPaperbackCommandRunner extends CompletionCommandRunner<int> {
  final cli = DartPaperbackCli();

  DartPaperbackCommandRunner() : super(executableName, description) {
    addCommand(Bundle());
    addCommand(Server());
    addCommand(Clean());
  }

  @override
  Future<int> run(Iterable<String> args) async {
    try {
      final ArgResults topLevelResults = parse(args);

      final command = topLevelResults.command;

      if (topLevelResults.rest.isNotEmpty) {
        print(red('\nInvalid command: "${topLevelResults.rest.join(' ')}"'));
        printUsage();
        return 1;
      }

      if (command == null) {
        print(red('\nYou must pass the name of the command to use.'));
        printUsage();
        return 1;
      }

      return await runCommand(topLevelResults) ?? 0;
    } on FormatException catch (e, stackTrace) {
      // On format errors, show the commands error message, root usage and
      // exit with an error code
      printerr(e.message);
      printerr('$stackTrace');
      print('');
      print(usage);
      return 0;
    }
  }
}
