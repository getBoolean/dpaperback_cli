import 'dart:io';

import 'package:dcli/dcli.dart';
import 'package:dpaperback_cli/src/utils/custom_time_display.dart';

const kDefaultPaperbackExtensionsCommon = 'paperback-extensions-common@^5.0.0-alpha.7';

mixin CommandTime {
  MillisecondTimeDisplay? _timeDisplay;
  Stopwatch? _stopwatch;

  void time({required String prefix}) {
    if (_timeDisplay != null || _stopwatch != null) {
      throw Exception('Timer already started. Call `stop` before `time`');
    }
    stdout.write((blue('$prefix: ', bold: true)));
    if (!stdin.hasTerminal) {
      final timer = Stopwatch();
      _stopwatch = timer;
      timer.start();
    } else {
      final timer = MillisecondTimeDisplay();
      _timeDisplay = timer;
      timer.start();
    }
  }

  /// Stops the timer and returns the elapsed time in milliseconds.
  ///
  /// If the timer was not started, 0 is returned.
  int stop() {
    if (!stdin.hasTerminal) {
      _stopwatch?.stop();
      final time = _stopwatch?.elapsedMilliseconds;
      if (time == null) {
        throw Exception('Timer not started. Call `time` before `stop`');
      }
      _stopwatch = null;
      _timeDisplay = null;
      return time;
    }
    _timeDisplay?.stop();
    stdout.writeln();
    final time = _timeDisplay?.watch?.elapsedMilliseconds ?? 0;
    _stopwatch = null;
    _timeDisplay = null;
    return time;
  }
}
