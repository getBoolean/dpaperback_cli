import 'package:dcli/dcli.dart';
import 'package:dpaperback_cli/src/commands/bundle.dart';
import 'package:dpaperback_cli/src/commands/command.dart';

class Server extends Command {
  final String output;
  final String target;
  final String port;

  Server(this.output, this.target, this.port);

  void run() {
    Bundle(output, target).run();
    print(blue('\nStarting Server on port $port'));
  }
}
