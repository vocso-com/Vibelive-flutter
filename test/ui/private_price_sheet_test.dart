import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/api/chat/chat_models.dart';
import 'package:vibelive/app/chatscreen/conversation/private_price_sheet.dart';

import 'host_onboarding_support/harness.dart';

/// A host prices a private photo: they see what they earn on the button,
/// never what the buyer pays (the buyer pays a little more, set by the admin).
void main() {
  setUpAll(setUpHostHarness);

  testWidgets('no "you earn" / "buyer pays" lines; the button still sends '
      'the buyer price', (tester) async {
    await resetHost();
    phone(tester);
    final picked = <double?>[];
    await pumpRoutes(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async => picked.add(
                await askPrivatePhotoPrice(
                  context,
                  const ChatPrivatePhotoRules(
                    enabled: true,
                    minPrice: 10,
                    maxPrice: 500,
                    earnMultiplier: 1.2,
                  ),
                ),
              ),
              child: const Text('PRICE'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('PRICE'));
    await pumpFor(tester, 600);
    expect(find.textContaining('Buyer pays'), findsNothing);
    expect(find.textContaining('You earn ₹'), findsNothing);
    final send = find.byKey(const ValueKey('chat-private-send'));
    expect(send, findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('chat-private-price')),
      '50',
    );
    await pumpFor(tester, 200);
    // The earning is on the button; the buyer's ₹60 is nowhere.
    expect(
      find.descendant(
        of: send,
        matching: find.textContaining(
          RegExp('you earn ₹50', caseSensitive: false),
        ),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Buyer pays'), findsNothing);
    expect(find.textContaining('You earn ₹'), findsNothing);
    expect(
      find.textContaining('60'),
      findsNothing,
      reason: 'buyer price hidden',
    );
    await tester.tap(send);
    await pumpFor(tester, 600);
    // ₹50 earned × 1.2: the buyer price goes to the server, unseen.
    expect(picked, [60]);
    await finishHost(tester);
  });
}
