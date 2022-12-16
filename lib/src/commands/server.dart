import 'package:dcli/dcli.dart';
import 'package:dpaperback_cli/src/commands/bundle.dart';
import 'package:dpaperback_cli/src/commands/command.dart';

class Server extends Command {
  final String output;
  final String target;
  final String commonsUrl;
  final int port;

  Server(this.output, this.target, this.port, this.commonsUrl);

  void run() {
    Bundle(output, target, commonsPackage: commonsUrl).run();
    print(blue('\nStarting Server on port $port'));
  }
}
