import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/api/chat/chat_api.dart';
import 'package:vibelive/app/api/chat/chat_models.dart';
import 'package:vibelive/app/chatscreen/helper/chat_format.dart';
import 'package:vibelive/app/chatscreen/helper/chat_pricing.dart';
import 'package:vibelive/app/chatscreen/helper/chat_rows.dart';
import 'package:vibelive/app/chatscreen/helper/chat_sync.dart';
import 'package:vibelive/app/chatscreen/helper/chat_wallet_rows.dart';
import 'package:vibelive/app/chatscreen/helper/low_balance.dart';
import 'package:vibelive/app/chatscreen/helper/pending_queue.dart';
import 'package:vibelive/core/network/api_exception.dart';

ChatMessage msg(
  String id, {
  String sender = 'me',
  required DateTime at,
  String? clientId,
  ChatSendState state = ChatSendState.sent,
  DateTime? readAt,
}) => ChatMessage(
  id: id,
  senderId: sender,
  type: ChatMessageType.text,
  createdAt: at,
  text: id,
  clientId: clientId,
  state: state,
  readAt: readAt,
);

ChatConfig config({int? hostMediaPercent}) => ChatConfig.fromJson({
  'enabled': true,
  'textPrice': 2,
  'imagePrice': 3,
  'voice': const {
    'shortSec': 10,
    'shortPrice': 2,
    'longSec': 30,
    'longPrice': 4,
    'stepSec': 20,
    'stepPrice': 1,
    'maxSeconds': 120,
  },
  'hostMediaPercent': ?hostMediaPercent,
});

void main() {
  group('pricing', () {
    test('voice ladder: short, long, then a step per started stepSec', () {
      final v = config().voice;
      expect(ChatPricing.voicePaise(v, 1), 200);
      expect(ChatPricing.voicePaise(v, 10), 200);
      expect(ChatPricing.voicePaise(v, 11), 400);
      expect(ChatPricing.voicePaise(v, 30), 400);
      expect(ChatPricing.voicePaise(v, 31), 500);
      expect(ChatPricing.voicePaise(v, 50), 500);
      expect(ChatPricing.voicePaise(v, 51), 600);
      expect(ChatPricing.voicePaise(v, 120), 900);
    });

    test('billed length never under-reports (bytes / 10000)', () {
      expect(ChatPricing.billedSeconds(5, bytes: 80000), 8);
      expect(ChatPricing.billedSeconds(12, bytes: 80000), 12);
    });

    test('payer pays the list price; host replies free', () {
      final c = config(hostMediaPercent: 50);
      expect(
        ChatPricing.priceFor(
          side: ChatSide.payer,
          type: ChatMessageType.text,
          config: c,
          textPrice: 2.5,
        ),
        const ChatPrice(250),
      );
      expect(
        ChatPricing.priceFor(
          side: ChatSide.host,
          type: ChatMessageType.text,
          config: c,
        ).isFree,
        isTrue,
      );
    });

    test('host media: percent of list, from earnings; unknown without it', () {
      final voice = ChatPricing.priceFor(
        side: ChatSide.host,
        type: ChatMessageType.audio,
        config: config(hostMediaPercent: 50),
        seconds: 12,
      );
      expect(voice.paise, 200);
      expect(voice.fromEarnings, isTrue);
      // The host's /chats/with imagePrice is already the host's price.
      expect(
        ChatPricing.priceFor(
          side: ChatSide.host,
          type: ChatMessageType.image,
          config: config(hostMediaPercent: 50),
          imagePrice: 1.5,
        ).paise,
        150,
      );
      expect(
        ChatPricing.priceFor(
          side: ChatSide.host,
          type: ChatMessageType.audio,
          config: config(),
          seconds: 5,
        ).isKnown,
        isFalse,
      );
    });

    test('money format and private photo share (floor, paise)', () {
      expect(ChatPricing.money(2), '₹2');
      expect(ChatPricing.money(2.5), '₹2.50');
      expect(ChatPricing.moneyPaise(1999), '₹19.99');
      expect(ChatPricing.privateSharePaise(99, 70), 6930);
      expect(ChatPricing.privateSharePaise(0.99, 70), 69);
      // min/max now bound the host's EARNING; picks are round earning amounts.
      const rules = ChatPrivatePhotoRules(minPrice: 10, maxPrice: 200);
      expect(ChatPricing.privatePicks(rules), [50.0, 100.0, 200.0]);
      expect(ChatPricing.privatePriceAllowed(5, rules), isFalse);
      expect(ChatPricing.privatePriceAllowed(200, rules), isTrue);
      expect(ChatPricing.privatePriceAllowed(200.01, rules), isFalse);
      // buyer price = earning × multiplier (default 1.2), in paise.
      expect(ChatPricing.buyerPricePaise(50, rules), 6000);
      expect(ChatPricing.buyerPricePaise(100, rules), 12000);
      const flat = ChatPrivatePhotoRules(minPrice: 10, maxPrice: 200, earnMultiplier: 1.0);
      expect(ChatPricing.buyerPricePaise(100, flat), 10000);
    });
  });

  group('rows', () {
    final day1 = DateTime(2026, 11, 2, 10);
    final day2 = DateTime(2026, 11, 3, 9);

    test('a separator starts each day; close messages group', () {
      final rows = ChatRows.build([
        msg('c', sender: 'me', at: day2.add(const Duration(minutes: 2))),
        msg('b', sender: 'me', at: day2),
        msg('a', sender: 'p', at: day1),
      ], 'me');
      expect(rows.map((r) => r.mine), [true, true, false]);
      expect(rows[0].dayBreak, isNull);
      expect(rows[1].dayBreak, DateTime(2026, 11, 3));
      expect(rows[2].dayBreak, DateTime(2026, 11, 2));
      expect(rows[0].joinOlder, isTrue); // c under b
      expect(rows[1].joinNewer, isTrue); // b has no tail
      expect(rows[1].joinOlder, isFalse); // other day, other person
    });

    test('equal rows for an untouched message (widget reuse)', () {
      final a = msg('a', at: day1);
      final b = msg('b', at: day2);
      final before = ChatRows.build([b, a], 'me');
      final after = ChatRows.build([
        msg('c', sender: 'p', at: day2),
        b,
        a,
      ], 'me');
      expect(after[2], before[1]); // a: same message, same flags
      expect(after[1] == before[0], isTrue); // b: c is from someone else
    });

    test('ticks: queued, failed, sent, delivered, read', () {
      final m = msg('a', at: day1);
      ChatTick tick(ChatMessage m, {DateTime? d, DateTime? r}) =>
          ChatRows.tickFor(m, mine: true, peerDeliveredAt: d, peerReadAt: r);
      expect(tick(m), ChatTick.sent);
      expect(tick(m, d: day1), ChatTick.delivered);
      expect(tick(m, d: day1, r: day2), ChatTick.read);
      expect(tick(m.copyWith(readAt: day2)), ChatTick.read);
      expect(
        tick(m, d: day1.subtract(const Duration(seconds: 1))),
        ChatTick.sent,
      );
      expect(tick(m.copyWith(state: ChatSendState.queued)), ChatTick.queued);
      expect(tick(m.copyWith(state: ChatSendState.failed)), ChatTick.failed);
      expect(ChatRows.tickFor(m, mine: false, peerReadAt: day2), ChatTick.none);
    });

    test('merge replaces by id, keeps newest first; compose dedupes', () {
      final a = msg('a', at: day1);
      final b = msg('b', at: day2, clientId: 'c1');
      final merged = ChatRows.merge([a], [b, msg('a', at: day1, readAt: day2)]);
      expect(merged.map((m) => m.id), ['b', 'a']);
      expect(merged.last.readAt, day2);
      final pending = msg(
        'local:c1',
        at: day2,
        clientId: 'c1',
        state: ChatSendState.sending,
      );
      final other = msg(
        'local:c2',
        at: day2,
        clientId: 'c2',
        state: ChatSendState.queued,
      );
      final shown = ChatRows.compose(merged, [pending, other]);
      // c1 was saved: shown once, as the server's.
      expect(shown.map((m) => m.id), ['local:c2', 'b', 'a']);
      expect(ChatRows.newestSent(shown)?.id, 'b');
      expect(ChatRows.oldestSent(shown)?.id, 'a');
    });

    test('unread from the other person', () {
      expect(
        ChatRows.hasUnreadFrom([msg('a', sender: 'p', at: day1)], 'me'),
        isTrue,
      );
      expect(
        ChatRows.hasUnreadFrom([
          msg('a', sender: 'p', at: day1, readAt: day2),
        ], 'me'),
        isFalse,
      );
    });
  });

  group('low balance', () {
    test('bar below the threshold; empty at zero; none when not paying', () {
      ChatLowBalance? low(double? balance, {bool paying = true}) =>
          ChatLowBalance.of(
            paying: paying,
            chatEnabled: true,
            balance: balance,
            textPrice: 2,
            threshold: 10,
          );
      expect(low(20), isNull); // 10 messages left
      expect(low(19.99)?.messagesLeft, 9);
      expect(low(1.5)?.empty, isTrue);
      expect(low(0)?.textKey, 'chat:low_balance.empty');
      expect(low(5, paying: false), isNull);
      expect(low(null), isNull);
      expect(ChatLowBalance.gap(required: 2, balance: 0.5), 1.5);
      expect(ChatLowBalance.gap(required: 2, balance: 5), 0);
    });
  });

  group('pending queue', () {
    OutboxEntry entry(String id, DateTime at, {String peer = 'p'}) =>
        OutboxEntry(
          clientId: id,
          peerUserId: peer,
          senderId: 'me',
          type: ChatMessageType.text,
          createdAt: at,
          text: id,
        );
    final t0 = DateTime(2026, 11, 3, 10);

    test('one in flight per person, oldest first, failed skipped', () {
      final a = entry('a', t0);
      final b = entry('b', t0.add(const Duration(seconds: 1)));
      final c = entry('c', t0, peer: 'q');
      expect(PendingQueue.nextFor([b, a, c], 'p')?.clientId, 'a');
      expect(
        PendingQueue.nextFor([
          a.copyWith(state: ChatSendState.sending),
          b,
        ], 'p'),
        isNull,
      );
      expect(
        PendingQueue.nextFor([
          a.copyWith(state: ChatSendState.failed),
          b,
        ], 'p')?.clientId,
        'b',
      );
      expect(PendingQueue.peersWithQueued([a, b, c]), {'p', 'q'});
    });

    test(
      'offline waits; 402 and refusals fail; a retry keeps the clientId',
      () {
        const offline = ApiException(ApiErrorType.network);
        const broke = ApiException(
          ApiErrorType.rejected,
          statusCode: 402,
          data: {
            'error': {
              'details': {
                'code': 'CHAT_LOW_BALANCE',
                'required': 2,
                'balance': 1,
              },
            },
          },
        );
        const off = ApiException(
          ApiErrorType.conflict,
          statusCode: 409,
          messageKey: 'chat:errors.CHAT_HOST_OFF',
        );
        expect(PendingQueue.classify(offline), OutboxFailure.retryLater);
        expect(PendingQueue.classify(broke), OutboxFailure.lowBalance);
        expect(PendingQueue.classify(off), OutboxFailure.failed);

        final a = entry('a', t0);
        final waiting = PendingQueue.afterFailure(
          a,
          OutboxFailure.retryLater,
          offline,
        );
        expect(waiting.state, ChatSendState.queued);
        expect(waiting.attempts, 1);
        final failed = PendingQueue.afterFailure(a, OutboxFailure.failed, off);
        expect(failed.state, ChatSendState.failed);
        expect(failed.errorKey, 'chat:errors.CHAT_HOST_OFF');
        final again = PendingQueue.retry(failed);
        expect(again.clientId, 'a');
        expect(again.state, ChatSendState.queued);
        expect(again.errorKey, isNull);
        expect(again.toMessage().key, 'me:a');
      },
    );
  });

  group('server answers', () {
    test('a refusal reads code and amounts from error.details', () {
      final r = ChatRefusal.of(
        const ApiException(
          ApiErrorType.unknown,
          statusCode: 402,
          data: {
            'error': {
              'message': 'Recharge',
              'details': {
                'code': 'CHAT_LOW_BALANCE',
                'required': '2.00',
                'balance': 0.5,
              },
            },
          },
        ),
      );
      expect(r.isLowBalance, isTrue);
      expect(r.required, 2);
      expect(r.balance, 0.5);
      expect(
        ChatRefusal.of(
          const ApiException(ApiErrorType.unknown, statusCode: 402),
        ).code,
        ChatCodes.lowBalance,
      );
    });

    test('config: only an explicit enabled shows chat; off stays off', () {
      expect(ChatConfig.fromJson(const {}).enabled, isFalse);
      expect(ChatConfig.fromJson(const {'data': <Object>[]}).enabled, isFalse);
      expect(ChatConfig.fromJson(const {'enabled': true}).enabled, isTrue);
      expect(ChatConfig.fromJson(ChatConfig.off.toJson()).enabled, isFalse);
      final c = config(hostMediaPercent: 40);
      expect(ChatConfig.fromJson(c.toJson()).hostMediaPercent, 40);
      expect(
        ChatConfig.fromJson(const {
          'enabled': true,
          'maxMessageLength': 9,
        }).maxMessageLength,
        50,
      );
    });

    test('messages and conversations parse leniently', () {
      final m = ChatMessage.fromJson(const {
        'id': 'm1',
        'senderId': 7,
        'type': 'private_image',
        'createdAt': '2026-11-03T10:00:00.000Z',
        'private': {
          'price': '99',
          'preview': {'url': 'https://x/p.webp', 'width': 300, 'height': 400},
          'unlocked': true,
          'expiresAt': '2026-11-03T10:10:00.000Z',
        },
      });
      expect(m.senderId, '7');
      expect(m.type, ChatMessageType.privateImage);
      expect(m.privatePhoto!.price, 99);
      expect(m.privatePhoto!.previewWidth, 300);
      expect(
        m.privatePhoto!.canOpenAt(DateTime.utc(2026, 11, 3, 10, 5)),
        isTrue,
      );
      expect(
        m.privatePhoto!.canOpenAt(DateTime.utc(2026, 11, 3, 10, 11)),
        isFalse,
      );
      expect(
        ChatMessage.fromJson(const {'type': 'sticker'}).type,
        ChatMessageType.unknown,
      );
      final page = ChatConversationsPage.fromJson(const {
        'items': [
          {
            'id': 'c1',
            'mySide': 'payer',
            'peer': {'userId': 7, 'name': 'Priya', 'isHost': true},
            'unread': '3',
          },
          {'id': ''},
        ],
        'unreadTotal': 3,
      });
      expect(page.items.single.peer.userId, '7');
      expect(page.items.single.unread, 3);
      final round = ChatConversationsPage.fromJson(page.toJson());
      expect(round.items.single.peer.name, 'Priya');
    });
  });

  group('hints', () {
    test(
      'a hint concerns its conversation, or its sender before one exists',
      () {
        const h = ChatHint(conversationId: 'c1', peerUserId: '7');
        expect(h.concerns(peer: '7', conversationId: 'c1'), isTrue);
        expect(h.concerns(peer: '7', conversationId: 'c2'), isFalse);
        expect(h.concerns(peer: '7'), isTrue);
        expect(h.concerns(peer: '8'), isFalse);
        expect(ChatHint.resume.concerns(peer: '8'), isTrue);
      },
    );
  });

  group('wallet rows', () {
    test('kind from transaction_Id, name and count from Note', () {
      final charge = ChatWalletRow.of(
        reference: 'CHAT_b1_42',
        note: 'Chat with Priya · 12 messages',
      )!;
      expect(charge.kind, ChatLedger.charge);
      expect(charge.titleKey, 'chat:wallet.chat');
      expect(charge.detailKey, 'chat:wallet.with');
      expect(charge.variables, {'count': '12', 'name': 'Priya'});
      final one = ChatWalletRow.of(
        reference: 'CHAT_b1_42_PAYOUT',
        note: 'Chat with Asha · 1 messages',
      )!;
      expect(one.kind, ChatLedger.payout);
      expect(one.detailKey, 'chat:wallet.from_one');
      final media = ChatWalletRow.of(
        reference: 'CHAT_b1_42_MEDIA',
        note: 'Chat · 3 photos and voice notes',
      )!;
      expect(media.detailKey, 'chat:wallet.media_to_noname');
      expect(
        ChatWalletRow.of(
          reference: 'PHOTO_m1',
          note: 'Private photo from Priya',
        )!.variables['name'],
        'Priya',
      );
      expect(
        ChatWalletRow.of(reference: 'PHOTO_m1_PAYOUT')!.detailKey,
        'chat:wallet.photo_to_noname',
      );
      expect(
        ChatWalletRow.of(reference: 'CHAT_REPLY_m9')!.kind,
        ChatLedger.reply,
      );
      // An unknown note shape is shown as written.
      expect(
        ChatWalletRow.of(
          reference: 'CHAT_b_1',
          note: 'Something new',
        )!.detailKey,
        'chat:wallet.note',
      );
      expect(ChatWalletRow.of(reference: 'RZP_123', note: 'Top up'), isNull);
      expect(ChatWalletRow.of(reference: 'pay_1'), isNull);
    });
  });

  group('format', () {
    test('days, clock and countdown', () {
      final f = ChatFormat.of('en');
      final now = DateTime(2026, 11, 3, 12);
      expect(f.day(DateTime(2026, 11, 3, 1), now: now).key, 'chat:day.today');
      expect(
        f.day(DateTime(2026, 11, 2, 23), now: now).key,
        'chat:day.yesterday',
      );
      expect(f.day(DateTime(2026, 10, 30), now: now).text, 'Friday');
      expect(f.day(DateTime(2026, 9, 1), now: now).text, 'Sep 1');
      expect(f.day(DateTime(2025, 9, 1), now: now).text, 'Sep 1, 2025');
      expect(ChatFormat.clock(75), '1:15');
      expect(
        ChatFormat.countdown(
          now.add(const Duration(minutes: 4, seconds: 59, milliseconds: 100)),
          now,
        ),
        '05:00',
      );
      expect(ChatFormat.countdown(now, now), '00:00');
    });
  });
}
