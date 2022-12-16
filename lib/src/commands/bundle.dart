import 'package:dpaperback_cli/src/commands/command.dart';

class Bundle extends Command {
  final String output;
  final String target;

  Bundle(this.output, this.target);

  void bundleSources() {}

  void createVersioningFile() {
    final verionTimer = time();
    stopTimer(verionTimer, prefix: 'Versioning File');
  }

  void generateHomepage() {
    final homepageTimer = time();

    stopTimer(homepageTimer, prefix: 'Homepage Generation');
  }
}
