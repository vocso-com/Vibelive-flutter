import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

/// Camera work, one job at a time, app-wide.
///
/// The camera plugins hold a single camera each, whichever controller asks.
/// On iOS any controller's dispose closes "the" camera, and a start or stop
/// that then finds no camera never answers. On Android every controller
/// shares one recorder, which forgets nothing until a stop completes. So
/// overlapping calls (a second open while the first waits on a permission
/// prompt, a release landing after the next open, a stop racing a dispose)
/// leave a recording that never starts or never ends, and a record button
/// that no longer does anything. Every open, start, stop and release goes
/// through here instead, in order, and none may hold the line for longer
/// than its timeout.
class VibeCameraLane {
  VibeCameraLane._();

  /// The lane every camera screen in the app shares.
  static VibeCameraLane get shared => _shared;
  static VibeCameraLane _shared = VibeCameraLane._();

  /// A fresh lane, for tests: a job still running when one test ends would
  /// otherwise hold up the next.
  @visibleForTesting
  static void debugReset() => _shared = VibeCameraLane._();

  final _jobs = Queue<Future<void> Function()>();
  bool _running = false;
  int _opens = 0;

  /// Runs [job] once every job queued before it has finished. With
  /// [timeout], a job that has not answered by then fails with a
  /// [TimeoutException] and the lane moves on; whatever it answers later is
  /// dropped.
  Future<T> run<T>(Future<T> Function() job, {Duration? timeout}) {
    final done = Completer<T>();
    _jobs.add(() async {
      try {
        final answer = Future<T>.sync(job);
        done.complete(await (timeout == null ? answer : answer.timeout(timeout)));
      } catch (e, s) {
        done.completeError(e, s);
      }
    });
    unawaited(_drain());
    return done.future;
  }

  Future<void> _drain() async {
    if (_running) return;
    _running = true;
    try {
      while (_jobs.isNotEmpty) {
        await _jobs.removeFirst()();
      }
    } finally {
      _running = false;
    }
  }

  /// Notes that a camera is about to be asked for (call it when the open is
  /// queued). The ticket tells a late answer, through [isNewestOpen],
  /// whether a newer camera has been asked for since: then that one has
  /// already taken its place, and closing the late one would close it.
  int beginOpen() => ++_opens;

  bool isNewestOpen(int ticket) => ticket == _opens;
}
