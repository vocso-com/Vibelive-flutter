import '../../../../core/network/strapi.dart';
import '../../../../core/session/session_store.dart';
import '../../helper/call_session.dart';

/// RN `formatTime`: `mm:ss`, both zero-padded, minutes uncapped (61 min →
/// `61:00`, never hh:mm:ss).
String formatCallTime(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  final m = (s ~/ 60).toString().padLeft(2, '0');
  final r = (s % 60).toString().padLeft(2, '0');
  return '$m:$r';
}

/// RN `statusLabel` as an i18n key; null where RN shows none (accepted /
/// ongoing: hidden on purpose for an "instant start").
String? callStatusKey(CallPhase phase, {bool instant = false}) => switch (phase) {
  // The Talk Now search: "Ringing" too (no "Searching", no names).
  CallPhase.calling || CallPhase.ringing when instant => 'call:status.ringing',
  CallPhase.calling => 'call:status.calling',
  CallPhase.ringing => 'call:status.ringing',
  CallPhase.accepted || CallPhase.ongoing => null,
  CallPhase.ended || CallPhase.idle => 'call:status.ended',
};

/// RN `isCallEnded`.
bool isCallOver(CallPhase phase) =>
    phase == CallPhase.ended || phase == CallPhase.idle;

/// `Video Call` / `Audio Call`.
String callTypeKey({required bool video}) =>
    video ? 'call:type.video' : 'call:type.audio';

/// A name worth showing (RN `name || fallback`).
String? nonEmpty(String? s) {
  final t = s?.trim();
  return t == null || t.isEmpty ? null : t;
}

/// This device's user (RN `displayLocalUser`).
({String? name, String? avatarUrl}) localCallUser() {
  final user = SessionStore.instance.value.user;
  return (
    name: nonEmpty(J.str(user?['name'])),
    avatarUrl: Strapi.mediaFromAsset(user?['profilePic']),
  );
}

/// Price as RN printed it (`20`, `12.5`).
String formatRate(num value) =>
    value == value.roundToDouble() ? value.toInt().toString() : '$value';
