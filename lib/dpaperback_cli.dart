import 'package:dcli/dcli.dart';

void dpaperback(ArgResults command, {required bool verbose}) {
  print('Hello, World!');
}

void printUsage({bool verbose = false, required String usage}) {
  print(green('\nUsage: dpaperback <command> [arguments]'));
  print(green('\nGlobal options:'));
  print(green(usage));
  print(green('\nAvailable commands:'));
  print(green(
      '   bundle          Builds all the sources in the repository and generates a versioning file'));
  print(green('   serve           Build the sources and start a local server'));
  print(green('   clean           Deletes the modules directory and the versioning file'));
}

void printCommandUsage({required ArgResults command, bool verbose = false, required String usage}) {
  print(green('\nUsage: dpaperback ${command.name} [arguments]'));
  print(green('\nOptions:'));
  print(green(usage));
}
