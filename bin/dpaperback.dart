import 'package:dpaperback_cli/dpaperback_cli.dart';

Future<void> main(List<String> args) async {
  await DartPaperbackCommandRunner().run(args);
}
