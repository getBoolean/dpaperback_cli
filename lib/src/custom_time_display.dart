import 'dart:async';

import 'package:console/console.dart';

// Modified from console's timer.dart

class MillisecondTimeDisplay {
  Stopwatch? _watch;
  bool _isStart = true;
  late String _lastMsg;
  Timer? _updateTimer;

  /// Starts the Timer
  void start([int place = 1]) {
    Console.adapter.echoMode = false;
    _watch = Stopwatch();
    _updateTimer = Timer.periodic(Duration(milliseconds: 10), (timer) {
      update(place);
    });
    _watch!.start();
  }

  /// Stops the Timer
  void stop() {
    Console.adapter.echoMode = true;
    if (_watch != null) {
      _watch!.stop();
    }
    if (_updateTimer != null) {
      _updateTimer!.cancel();
    }
  }

  /// Updates the Timer
  void update([int place = 1]) {
    if (_watch != null) {
      if (_isStart) {
        final msg = '(${_watch!.elapsed.inMilliseconds}ms)';
        _lastMsg = msg;
        Console.write(msg);
        _isStart = false;
      } else {
        Console.moveCursorBack(_lastMsg.length);
        final msg = '(${(_watch!.elapsed.inMilliseconds).toStringAsFixed(place)}ms)';
        _lastMsg = msg;
        Console.setBold(true);
        Console.setTextColor(Color.GRAY.id);
        Console.write(msg);
        Console.setBold(false);
      }
    }
  }
}
