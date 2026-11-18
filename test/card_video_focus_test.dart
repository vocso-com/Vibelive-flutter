import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/homescreen/discover/card_video_focus.dart';

/// Which Discover cards play their video intro: the rule alone.
void main() {
  const view = Rect.fromLTWH(0, 100, 400, 600); // y 100..700

  test('visible share: whole, half, none', () {
    expect(
      CardVideoFocus.visibleShare(const Rect.fromLTWH(0, 200, 200, 200), view),
      1,
    );
    // Half of it below the bottom edge.
    expect(
      CardVideoFocus.visibleShare(const Rect.fromLTWH(0, 600, 200, 200), view),
      0.5,
    );
    expect(
      CardVideoFocus.visibleShare(const Rect.fromLTWH(0, 800, 200, 200), view),
      0,
    );
    expect(CardVideoFocus.visibleShare(Rect.zero, view), 0);
  });

  test('pick: only cards mostly on screen, the most central first, at most '
      'four', () {
    final shares = {
      'a': 1.0,
      'b': 0.59,
      'c': 0.6,
      'd': 1.0,
      'e': 1.0,
      'f': 1.0,
    };
    final centre = {'a': 50.0, 'b': 0.0, 'c': 300.0, 'd': 10.0, 'e': 20.0};
    // b is central but too little of it shows; f has no distance (0): first.
    expect(CardVideoFocus.pick(shares, centre), {'f', 'd', 'e', 'a'});
    expect(CardVideoFocus.pick(shares, centre, max: 2), {'f', 'd'});
    expect(CardVideoFocus.pick({'x': 0.2}, {'x': 0.0}), isEmpty);
    expect(CardVideoFocus.pick(<String, double>{}, {}), isEmpty);
  });

  test(
    'a card that is disposed leaves quietly: no one is told mid-teardown',
    () {
      final focus = CardVideoFocus(settleDelay: Duration.zero);
      var told = 0;
      focus.addListener(() => told++);
      final card = Object();
      focus.register(card, () => null);
      focus.unregister(card);
      expect(told, 0);
      focus.dispose();
    },
  );
}
