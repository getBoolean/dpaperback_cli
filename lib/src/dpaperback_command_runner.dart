import 'package:cli_completion/cli_completion.dart';
import 'package:dcli/dcli.dart';
import 'package:dpaperback_cli/dpaperback_cli.dart';
import 'package:riverpod/riverpod.dart';

const executableName = 'dpaperback';
const packageName = 'dpaperback_cli';
const description = 'A commandline tool for bundling and serving Paperback written in Dart.';

class DartPaperbackCommandRunner extends CompletionCommandRunner<int> {
  final ProviderContainer container;

  DartPaperbackCommandRunner([ProviderContainer? container])
      : container = container ?? ProviderContainer(),
        super(executableName, description) {
    addCommand(Bundle(container));
    addCommand(Server(container));
    addCommand(Clean(container));
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
