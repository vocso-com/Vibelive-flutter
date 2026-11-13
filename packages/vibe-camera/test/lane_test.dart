import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_camera/vibe_camera.dart';

void main() {
  setUp(VibeCameraLane.debugReset);

  test('jobs run one at a time, in the order asked', () async {
    final lane = VibeCameraLane.shared;
    final log = <String>[];
    final first = Completer<void>();
    final a = lane.run(() async {
      log.add('a starts');
      await first.future;
      log.add('a ends');
    });
    final b = lane.run(() async => log.add('b'));
    await Future<void>.delayed(Duration.zero);
    expect(log, ['a starts'], reason: 'b waits for a');
    first.complete();
    await Future.wait([a, b]);
    expect(log, ['a starts', 'a ends', 'b']);
  });

  test('a job that never answers fails at its timeout and the lane moves on', () async {
    final lane = VibeCameraLane.shared;
    var nextRan = false;
    final hung = lane.run(() => Completer<void>().future, timeout: const Duration(milliseconds: 80));
    final next = lane.run(() async => nextRan = true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(nextRan, isFalse, reason: 'it waits its turn');
    await expectLater(hung, throwsA(isA<TimeoutException>()));
    expect(await next, isTrue);
  });

  test('a failing job hands its error back and does not block the next', () async {
    final lane = VibeCameraLane.shared;
    await expectLater(lane.run<void>(() async => throw StateError('no camera')), throwsStateError);
    expect(await lane.run(() async => 7), 7);
  });

  test('an open is the newest until another is asked for', () {
    final lane = VibeCameraLane.shared;
    final first = lane.beginOpen();
    expect(lane.isNewestOpen(first), isTrue);
    final second = lane.beginOpen();
    expect(lane.isNewestOpen(first), isFalse);
    expect(lane.isNewestOpen(second), isTrue);
  });
}
