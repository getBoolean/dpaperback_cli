import 'package:dart_pb_cli/dart_pb_cli.dart';

import 'dart:io';

import 'package:args/args.dart';

const lineNumber = 'line-number';

void main(List<String> arguments) {
  exitCode = 0; // presume success
  final parser = ArgParser()..addFlag(lineNumber, negatable: false, abbr: 'n');

  ArgResults argResults = parser.parse(arguments);

  dpaperback();
}