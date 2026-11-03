import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../api/chat/chat_models.dart';

/// What one message costs this side, in paise. [paise] is null when the
/// server did not say (a host's own media without `hostMediaPercent`).
@immutable
class ChatPrice {
  const ChatPrice(this.paise, {this.fromEarnings = false});

  static const free = ChatPrice(0);

  final int? paise;

  /// Paid from the host's earnings (their own photo or voice note).
  final bool fromEarnings;

  bool get isFree => paise == 0;
  bool get isKnown => paise != null;

  double? get rupees => paise == null ? null : paise! / 100;

  @override
  bool operator ==(Object other) =>
      other is ChatPrice &&
      other.paise == paise &&
      other.fromEarnings == fromEarnings;

  @override
  int get hashCode => Object.hash(paise, fromEarnings);
}

/// The chat's money rules (contract §2-§3), in integer paise like the
/// server, converted only for display.
abstract final class ChatPricing {
  static int paise(double rupees) => (rupees * 100).round();

  /// `₹2`, `₹2.50`, `₹1,999` (Indian grouping is not needed at chat sizes).
  static String money(double rupees) => moneyPaise(paise(rupees));

  static String moneyPaise(int paise) {
    final whole = paise ~/ 100;
    final cents = paise.abs() % 100;
    return cents == 0
        ? '₹$whole'
        : '₹$whole.${cents.toString().padLeft(2, '0')}';
  }

  /// The billed length of a voice note: a phone cannot under-report it,
  /// the server bills `max(durationSec, floor(bytes / 10000))`.
  static int billedSeconds(int durationSec, {int bytes = 0}) =>
      math.max(durationSec, bytes ~/ 10000);

  /// The voice ladder: up to `shortSec` the short price; up to `longSec`
  /// the long price; then the long price plus `stepPrice` for each
  /// `stepSec` started past `longSec`.
  static int voicePaise(ChatVoicePricing v, int seconds) {
    final s = math.max(1, seconds);
    if (s <= v.shortSec) return paise(v.shortPrice);
    if (s <= v.longSec || v.stepSec <= 0) return paise(v.longPrice);
    final steps = ((s - v.longSec) / v.stepSec).ceil();
    return paise(v.longPrice) + steps * paise(v.stepPrice);
  }

  /// The list price of [type] (what a paying side pays).
  static int listPaise(
    ChatMessageType type,
    ChatConfig config, {
    double? textPrice,
    double? imagePrice,
    int seconds = 0,
  }) => switch (type) {
    ChatMessageType.text => paise(textPrice ?? config.textPrice),
    ChatMessageType.image => paise(imagePrice ?? config.imagePrice),
    ChatMessageType.audio => voicePaise(config.voice, seconds),
    // The host sets it; the buyer pays it on unlock, never to send.
    ChatMessageType.privateImage || ChatMessageType.unknown => 0,
  };

  /// What sending [type] costs [side]. The payer pays the list price; a
  /// host's text and private photos are free, a host's own photo or voice
  /// note costs `hostMediaPercent` of the list price, from earnings.
  /// [textPrice] / [imagePrice]: the conversation's own (`/chats/with`;
  /// on the host side `imagePrice` is already the host's price).
  static ChatPrice priceFor({
    required ChatSide side,
    required ChatMessageType type,
    required ChatConfig config,
    double? textPrice,
    double? imagePrice,
    int seconds = 0,
  }) {
    final list = listPaise(
      type,
      config,
      textPrice: textPrice,
      imagePrice: imagePrice,
      seconds: seconds,
    );
    if (side == ChatSide.payer) return ChatPrice(list);
    if (type != ChatMessageType.image && type != ChatMessageType.audio) {
      return ChatPrice.free;
    }
    // The host side's `/chats/with` imagePrice is already the host's own
    // price (list × hostMediaPercent).
    if (type == ChatMessageType.image && imagePrice != null) {
      return ChatPrice(paise(imagePrice), fromEarnings: true);
    }
    final percent = config.hostMediaPercent;
    if (percent == null) return const ChatPrice(null, fromEarnings: true);
    return ChatPrice((list * percent / 100).round(), fromEarnings: true);
  }

  /// A host's share of a private photo sold at [price] rupees: floor in
  /// paise, as the server pays it.
  static int privateSharePaise(double price, int percent) =>
      (paise(price) * percent / 100).floor();

  /// [price] inside the admin's range.
  static bool privatePriceAllowed(double? price, ChatPrivatePhotoRules rules) =>
      price != null &&
      paise(price) >= paise(rules.minPrice) &&
      paise(price) <= paise(rules.maxPrice);

  /// Quick picks for the host's price sheet, inside [rules]' range; the
  /// range ends themselves when no pick fits.
  static List<double> privatePicks(ChatPrivatePhotoRules rules) {
    const picks = [49.0, 99.0, 199.0, 499.0];
    final inside = [
      for (final p in picks)
        if (privatePriceAllowed(p, rules)) p,
    ];
    if (inside.isNotEmpty) return inside;
    return {rules.minPrice, rules.maxPrice}.toList();
  }
}
