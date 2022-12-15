import 'package:dcli/dcli.dart';

class DartPaperbackCli {
  bool verbose = false;

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

  late final baseParser = ArgParser(allowTrailingOptions: false)
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

  void printUsage() {
    print(green('\nUsage: dpaperback <command> [arguments]'));
    print(green('\nGlobal options:'));
    print(green(baseParser.usage));
    print(green('\nAvailable commands:'));
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
    print(green('\nUsage: dpaperback $command [arguments]'));
    print(green('\nOptions:'));
    print(green(commandUsage(command)));
  }

  void dpaperback(ArgResults command) {
    print('Hello, World!');
    switch (command.name) {
      case 'bundle':
        break;
      case 'serve':
        break;
      case 'clean':
        break;
    }
  }
}
