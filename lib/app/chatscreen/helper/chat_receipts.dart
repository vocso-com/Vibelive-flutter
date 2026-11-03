import 'dart:convert';

import '../../../core/network/api_exception.dart';
import '../../../core/storage/app_prefs.dart';
import '../../../core/utils/log.dart';
import '../../api/chat/chat_api.dart';

/// "Delivered" receipts from chat pushes (`POST /chats/receipts`, no
/// sign-in), from any isolate. One that cannot be posted now (offline) is
/// kept on disk and goes with the next one, or when the app comes back.
abstract final class ChatReceipts {
  static const storageKey = 'chat_pending_receipts';
  static const _max = 50;

  /// Posts [receipt] and any kept ones. Never throws.
  static Future<void> post(String? receipt) async {
    final pending = _read();
    final r = receipt?.trim();
    if (r != null && r.isNotEmpty && !pending.contains(r)) pending.add(r);
    await _send(pending);
  }

  /// Posts the kept ones (app back in front).
  static Future<void> flush() => _send(_read());

  static Future<void> _send(List<String> receipts) async {
    if (receipts.isEmpty) return;
    try {
      await ChatApi.postReceipts(receipts);
      await AppPrefs.remove(storageKey);
    } on ApiException catch (e) {
      // A refused receipt (forged, too old) is never worth keeping.
      final keep =
          e.type == ApiErrorType.network ||
          e.type == ApiErrorType.timeout ||
          e.type == ApiErrorType.server;
      Log.d('ChatReceipts', 'post failed (${keep ? 'kept' : 'dropped'}): $e');
      if (keep) {
        final tail = receipts.length > _max
            ? receipts.sublist(receipts.length - _max)
            : receipts;
        await AppPrefs.setString(storageKey, jsonEncode(tail));
      } else {
        await AppPrefs.remove(storageKey);
      }
    } catch (e) {
      Log.w('ChatReceipts', e);
    }
  }

  static List<String> _read() {
    final raw = AppPrefs.getString(storageKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw);
      return list is List ? [for (final e in list) '$e'] : [];
    } on FormatException {
      return [];
    }
  }
}
