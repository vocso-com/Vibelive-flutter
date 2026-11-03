import 'package:flutter/foundation.dart';

import '../../../core/network/strapi.dart';

/// Which chat ledger row a transaction is (contract §3).
enum ChatLedger {
  /// A payer's messages to a host, billed (`CHAT_<batch>_<host>`).
  charge,

  /// A host's share of answered messages (`…_PAYOUT`, `CHAT_REPLY_…`).
  payout,
  reply,

  /// A host's own photos / voice notes (`…_MEDIA`).
  media,

  /// A private photo bought (`PHOTO_<id>`) / sold (`PHOTO_<id>_PAYOUT`).
  photo,
  photoSold,
}

/// How the wallet history names a chat ledger row (contract §6): "Chat
/// with Priya · 12 messages" instead of "Paid to Vibe Live".
///
/// `metadata` is private on the server (never in `GET /transactions`), so
/// the kind comes from `transaction_Id` and the name and count from the
/// row's `Note` ("Chat with Priya · 12 messages", "Private photo from
/// Priya"), shown in the app language when it can be read, else as sent.
@immutable
class ChatWalletRow {
  const ChatWalletRow({
    required this.kind,
    required this.titleKey,
    required this.detailKey,
    required this.variables,
  });

  final ChatLedger kind;

  /// i18n key of the first line.
  final String titleKey;

  /// Second line, filled from [variables] (`name`, `count`, `note`).
  final String detailKey;
  final Map<String, String> variables;

  /// The ledger kind from a `transaction_Id`, else from `metadata.type`.
  static ChatLedger? kindOf(String? reference, [JsonMap? metadata]) {
    final ref = (reference ?? '').trim().toUpperCase();
    if (ref.startsWith('CHAT_REPLY_')) return ChatLedger.reply;
    if (ref.startsWith('CHAT_')) {
      if (ref.endsWith('_PAYOUT')) return ChatLedger.payout;
      if (ref.endsWith('_MEDIA')) return ChatLedger.media;
      return ChatLedger.charge;
    }
    if (ref.startsWith('PHOTO_')) {
      return ref.endsWith('_PAYOUT') ? ChatLedger.photoSold : ChatLedger.photo;
    }
    return switch (J.str(metadata?['type'])?.toUpperCase()) {
      'CHAT_CHARGE' => ChatLedger.charge,
      'CHAT_PAYOUT' => ChatLedger.payout,
      'CHAT_REPLY_PAYOUT' => ChatLedger.reply,
      'CHAT_HOST_MEDIA' => ChatLedger.media,
      'PRIVATE_PHOTO' => ChatLedger.photo,
      'PRIVATE_PHOTO_PAYOUT' => ChatLedger.photoSold,
      _ => null,
    };
  }

  static final _chatWith = RegExp(r'^Chat with (.+?) · (\d+)\b');
  static final _chatCount = RegExp(r'^Chat · (\d+)\b');
  static final _photoFrom = RegExp(r'^Private photo from (.+)$');
  static final _photoBy = RegExp(r'^Private photo bought by (.+)$');

  /// Null for a row that is not chat.
  static ChatWalletRow? of({
    String? reference,
    String? note,
    JsonMap? metadata,
  }) {
    final kind = kindOf(reference, metadata);
    if (kind == null) return null;
    final n = (note ?? '').trim();
    String? name;
    int? count;
    final withMatch = _chatWith.firstMatch(n);
    final countMatch = _chatCount.firstMatch(n);
    final photoMatch = _photoFrom.firstMatch(n) ?? _photoBy.firstMatch(n);
    if (withMatch != null) {
      name = withMatch[1];
      count = int.tryParse(withMatch[2]!);
    } else if (countMatch != null) {
      count = int.tryParse(countMatch[1]!);
    } else if (photoMatch != null) {
      name = photoMatch[1];
    }
    // An older row with metadata still readable.
    final payerSide = kind == ChatLedger.charge || kind == ChatLedger.photo;
    final meta = metadata ?? const <String, dynamic>{};
    name ??= _name(payerSide ? meta['hostName'] : meta['payerName']);
    count ??= J.integer(meta['messages']);
    final understood = name != null || count != null;

    final (title, base) = switch (kind) {
      ChatLedger.charge => ('chat', 'with'),
      ChatLedger.payout => ('earnings', 'from'),
      ChatLedger.reply => ('earnings', 'reply'),
      ChatLedger.media => ('media', 'media_to'),
      ChatLedger.photo => ('photo', 'photo_from'),
      ChatLedger.photoSold => ('photo_earnings', 'photo_to'),
    };
    final String detail;
    if (!understood && n.isNotEmpty) {
      // A note in a shape this build does not know: as the server wrote it.
      detail = 'note';
    } else {
      final counted = base == 'with' || base == 'from' || base == 'media_to';
      final one = counted && count == 1 ? '_one' : '';
      detail = '$base$one${name == null ? '_noname' : ''}';
    }
    return ChatWalletRow(
      kind: kind,
      titleKey: 'chat:wallet.$title',
      detailKey: 'chat:wallet.$detail',
      variables: {
        'count': '${count ?? 0}',
        'name': ?name,
        if (detail == 'note') 'note': n,
      },
    );
  }

  static String? _name(Object? v) {
    final s = J.str(v)?.trim();
    return s == null || s.isEmpty ? null : s;
  }
}
