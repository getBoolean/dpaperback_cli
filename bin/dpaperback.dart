import 'dart:io';

import 'package:args/args.dart';
import 'package:dpaperback_cli/dpaperback_cli.dart';

void main(List<String> arguments) {
  exitCode = 0; // presume success
  final parser = ArgParser();

  final ArgResults argResults = parser.parse(arguments);

  dpaperback();
}
