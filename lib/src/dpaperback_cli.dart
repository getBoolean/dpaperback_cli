import 'dart:io';

import 'package:dcli/dcli.dart';

const kDefaultPaperbackExtensionsCommon = 'paperback-extensions-common@^5.0.0-alpha.7';

class DartPaperbackCli {
  String parseTargetPath(ArgResults command) {
    final targetArgument = command['target'] as String;
    final targetPath = canonicalize(targetArgument);
    if (!exists(targetPath)) {
      print(red('The target directory "$targetArgument" could not be found'));
      exit(2);
    }

    return targetPath;
  }

  String parseOutputPath(ArgResults command) {
    final outputArgument = command['output'] as String;
    final outputPath = canonicalize(outputArgument);

    if (!exists(outputPath)) {
      createDir(outputPath, recursive: true);
    }
    return outputPath;
  }
}
