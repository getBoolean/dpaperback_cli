import 'package:dpaperback_cli/src/commands/command.dart';

class Bundle extends Command {
  final String output;
  final String target;

  Bundle(this.output, this.target);

  void bundleSources() {}

  void run() {
    final executionTimer = time();
    bundleSources();
    createVersioningFile();
    generateHomepage();
    stopTimer(executionTimer, prefix: 'Execution time');
  }

  void createVersioningFile() {
    final verionTimer = time();
    stopTimer(verionTimer, prefix: 'Versioning File');
  }

  void generateHomepage() {
    final homepageTimer = time();

    stopTimer(homepageTimer, prefix: 'Homepage Generation');
  }
}
