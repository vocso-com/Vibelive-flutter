import 'dart:async';

import 'package:flutter/foundation.dart';

/// The call's named one-shot timers (decision 7: no-answer, incoming ring,
/// remote-drop grace, reconnecting; decision 8: max duration). Arming a
/// name replaces it; everything is cancelled when the call is over.
class CallTimers {
  CallTimers._();
  static final instance = CallTimers._();

  static const noAnswer = 'noAnswer';
  static const incomingRing = 'incomingRing';
  static const remoteDrop = 'remoteDrop';
  static const reconnecting = 'reconnecting';
  static const callerConnect = 'callerConnect';
  static const endedPush = 'endedPush';
  static const maxDuration = 'maxDuration';
  static const lowBalance = 'lowBalance';

  /// "Add money" on the call screen, a little before [maxDuration].
  static const topUpPrompt = 'topUpPrompt';

  /// The longest a call is held while its caller pays.
  static const topUpHoldMax = 'topUpHoldMax';

  final _timers = <String, Timer>{};

  void arm(String name, Duration after, void Function() fire) {
    _timers.remove(name)?.cancel();
    _timers[name] = Timer(after.isNegative ? Duration.zero : after, () {
      _timers.remove(name);
      try {
        fire();
      } catch (_) {}
    });
  }

  void cancel(String name) => _timers.remove(name)?.cancel();

  bool isArmed(String name) => _timers.containsKey(name);

  void cancelAll() {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
  }

  @visibleForTesting
  Set<String> get armed => _timers.keys.toSet();
}
