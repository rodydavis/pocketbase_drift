import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Measures how long the main isolate's event loop is blocked: a 10 ms
/// periodic timer records how late each tick fires. DB work, JSON decoding
/// and image decoding on the UI isolate show up as lag spikes.
class LoopLag {
  Timer? _t;
  final _sw = Stopwatch();
  int _last = 0;
  int maxLagMs = 0;
  int ticks = 0;
  int over50 = 0;
  int over100 = 0;
  int totalLagMs = 0;

  void start() {
    _sw.start();
    _last = _sw.elapsedMilliseconds;
    _t = Timer.periodic(const Duration(milliseconds: 10), (_) {
      final now = _sw.elapsedMilliseconds;
      final lag = now - _last - 10;
      _last = now;
      ticks++;
      if (lag > 0) totalLagMs += lag;
      if (lag > maxLagMs) maxLagMs = lag;
      if (lag > 50) over50++;
      if (lag > 100) over100++;
    });
  }

  void stop() => _t?.cancel();

  @override
  String toString() =>
      'maxLag=${maxLagMs}ms spikes>50ms=$over50 spikes>100ms=$over100 blockedTotal=${totalLagMs}ms';
}

/// Collects UI-thread build durations from the engine.
class FrameStats {
  final builds = <int>[];
  void _onTimings(List<FrameTiming> t) {
    for (final f in t) {
      builds.add(f.buildDuration.inMicroseconds);
    }
  }

  void start() => SchedulerBinding.instance.addTimingsCallback(_onTimings);
  void stop() => SchedulerBinding.instance.removeTimingsCallback(_onTimings);

  @override
  String toString() {
    if (builds.isEmpty) return 'frames=0';
    final s = [...builds]..sort();
    int p(double q) => s[((s.length - 1) * q).round()] ~/ 1000;
    final janky = s.where((b) => b > 16000).length;
    return 'frames=${s.length} buildP50=${p(.5)}ms buildP90=${p(.9)}ms buildMax=${s.last ~/ 1000}ms build>16ms=$janky';
  }
}

void labLog(String msg) => debugPrint('LAB $msg');
