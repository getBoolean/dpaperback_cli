import 'dart:io';

import 'package:dcli/dcli.dart';
import 'package:dpaperback_cli/src/custom_time_display.dart';

const kDefaultPaperbackExtensionsCommon = 'paperback-extensions-common@^5.0.0-alpha.7';

mixin CommandTime {
  MillisecondTimeDisplay time({required String prefix}) {
    final MillisecondTimeDisplay timer = MillisecondTimeDisplay();
    stdout.write((blue('$prefix: ', bold: true)));
    timer.start();
    return timer;
  }

  void stopTimer(MillisecondTimeDisplay timer) {
    timer.stop();
    stdout.writeln();
  }
}
