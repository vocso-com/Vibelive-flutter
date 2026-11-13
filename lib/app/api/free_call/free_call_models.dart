import 'package:flutter/foundation.dart';

import '../../../core/network/strapi.dart';

/// A free call's terms, as the server stamped them on the call
/// (docs/free_calls.md): [minutes] free, then — when [continuePaid] — billed
/// as usual while the caller can pay; otherwise the call ends at the limit.
@immutable
class FreeCallTerms {
  const FreeCallTerms({required this.minutes, this.continuePaid = true});

  final int minutes;
  final bool continuePaid;

  Duration get duration => Duration(minutes: minutes);

  /// `{minutes, continuePaid}` from a start reply or a status; null when the
  /// call is not free.
  static FreeCallTerms? tryParse(Object? raw) {
    final map = Strapi.map(raw);
    if (map == null) return null;
    return of(map['minutes'], map['continuePaid']);
  }

  /// From loose values (a push carries strings). Null without free minutes.
  static FreeCallTerms? of(Object? minutes, Object? continuePaid) {
    final m = J.integer(minutes) ?? J.number(minutes)?.floor();
    if (m == null || m <= 0) return null;
    return FreeCallTerms(
      minutes: m,
      // Unsaid reads as the server's default (on).
      continuePaid: continuePaid == null ? true : J.boolean(continuePaid),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FreeCallTerms &&
      other.minutes == minutes &&
      other.continuePaid == continuePaid;

  @override
  int get hashCode => Object.hash(minutes, continuePaid);
}

/// `GET /free-call/status`: whether the signed-in user has a free call now,
/// and on which calls. Off when unknown — the app then shows prices and
/// gates on balance exactly as before; the server decides again anyway.
@immutable
class FreeCallStatus {
  const FreeCallStatus({
    this.available = false,
    this.callsLeft = 0,
    this.minutes = 0,
    this.voice = true,
    this.video = true,
    this.normal = true,
    this.talkNow = true,
    this.continuePaid = true,
  });

  static const off = FreeCallStatus();

  final bool available;
  final int callsLeft;
  final int minutes;
  final bool voice;
  final bool video;

  /// A call to a chosen host (also when it rolls over).
  final bool normal;
  final bool talkNow;
  final bool continuePaid;

  /// Whether this call would start free.
  bool covers({required bool video, required bool talkNow}) =>
      available &&
      minutes > 0 &&
      (video ? this.video : voice) &&
      (talkNow ? this.talkNow : normal);

  factory FreeCallStatus.fromJson(Map<String, dynamic> j) {
    final minutes = J.integer(j['minutes']) ?? 0;
    final left = J.integer(j['callsLeft']) ?? 0;
    return FreeCallStatus(
      available: J.boolean(j['available']) && minutes > 0 && left > 0,
      callsLeft: left,
      minutes: minutes,
      voice: j['voice'] == null || J.boolean(j['voice']),
      video: j['video'] == null || J.boolean(j['video']),
      normal: j['normal'] == null || J.boolean(j['normal']),
      talkNow: j['talkNow'] == null || J.boolean(j['talkNow']),
      continuePaid: j['continuePaid'] == null || J.boolean(j['continuePaid']),
    );
  }

  Map<String, dynamic> toJson() => {
    'available': available,
    'callsLeft': callsLeft,
    'minutes': minutes,
    'voice': voice,
    'video': video,
    'normal': normal,
    'talkNow': talkNow,
    'continuePaid': continuePaid,
  };

  @override
  bool operator ==(Object other) =>
      other is FreeCallStatus &&
      other.available == available &&
      other.callsLeft == callsLeft &&
      other.minutes == minutes &&
      other.voice == voice &&
      other.video == video &&
      other.normal == normal &&
      other.talkNow == talkNow &&
      other.continuePaid == continuePaid;

  @override
  int get hashCode => Object.hash(
    available,
    callsLeft,
    minutes,
    voice,
    video,
    normal,
    talkNow,
    continuePaid,
  );
}
