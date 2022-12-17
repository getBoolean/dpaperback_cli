import 'package:dcli/dcli.dart';

mixin CommandTime {
  Stopwatch time() {
    final Stopwatch timer = Stopwatch();
    timer.start();
    return timer;
  }

  void stopTimer(Stopwatch timer, {String prefix = 'Time elapsed:'}) {
    timer.stop();
    print((blue('$prefix: ${timer.elapsedMilliseconds}ms', bold: true)));
  }
}
