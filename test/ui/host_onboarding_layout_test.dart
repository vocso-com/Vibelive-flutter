import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/hosthub/onboarding/helper/host_steps.dart';
import 'package:vibelive/app/hosthub/onboarding/host_onboarding_screen.dart';
import 'package:vibelive/core/constants/app_assets.dart';
import 'package:vibelive/core/storage/app_prefs.dart';

import 'host_onboarding_support/harness.dart';

/// A complete draft parked on [step].
Future<void> _parkDraft(HostStep step) => AppPrefs.setString(
  'hostflow_draft_v1:u1',
  jsonEncode({
    'step': step.name,
    'started': true,
    'seeded': true,
    'languagesSeeded': true,
    'name': 'Venkata Lakshmi Narasimha Subrahmanyam',
    'handle': 'venkata_lakshmi_narasimha_sub',
    'tagline': 'Good conversations, music and everyday stories.',
    'bio':
        'I love meeting new people and having real conversations about '
        'life, relationships, music and self-growth. I am a good listener.',
    'gender': 'Female',
    'languages': [
      {'id': 5, 'documentId': 'l5', 'label': 'English'},
      {'id': 22, 'documentId': 'l22', 'label': 'हिंदी'},
    ],
    'state': {'id': 4, 'documentId': 'st4', 'name': 'Andaman and Nicobar'},
    'district': {'id': 9, 'documentId': 'd9', 'name': 'North and Middle'},
    'topics': [
      {'value': 'topic_dating_advice', 'label': 'Dating advice', 'emoji': ''},
      {'value': 'topic_self_love', 'label': 'Self-love & confidence'},
      {'value': 'topic_feeling_low', 'label': 'Feeling low', 'emoji': ''},
      {'value': 'topic_career_confusion', 'label': 'Career confusion'},
    ],
    'photos': [
      {'key': 'm77', 'mediaId': 77},
      {'key': 'm78', 'mediaId': 78},
    ],
    'agreed': true,
  }),
);

/// Raises the keyboard over 10 frames (iOS: inset = keyboard, no bottom
/// padding); returns how often each widget type rebuilt meanwhile.
Future<Map<String, int>> _raiseKeyboard(WidgetTester tester, double kb) async {
  final counts = <String, int>{};
  debugOnRebuildDirtyWidget = (e, _) {
    final n = e.widget.runtimeType.toString();
    counts[n] = (counts[n] ?? 0) + 1;
  };
  try {
    for (var k = 1; k <= 10; k++) {
      tester.view
        ..viewInsets = FakeViewPadding(bottom: kb * 3 * k / 10)
        ..padding = const FakeViewPadding(top: 20 * 3);
      await tester.pump(const Duration(milliseconds: 16));
    }
  } finally {
    debugOnRebuildDirtyWidget = null;
  }
  return counts;
}

Future<Map<String, int>> _typing(
  WidgetTester tester,
  Finder field,
  String text,
) async {
  final counts = <String, int>{};
  debugOnRebuildDirtyWidget = (e, _) {
    final n = e.widget.runtimeType.toString();
    counts[n] = (counts[n] ?? 0) + 1;
  };
  try {
    await tester.enterText(field, text);
    await tester.pump();
  } finally {
    debugOnRebuildDirtyWidget = null;
  }
  return counts;
}

/// The focused field's caret, in screen coordinates.
Rect _caretRect(WidgetTester tester) {
  final editable = tester.allRenderObjects
      .whereType<RenderEditable>()
      .firstWhere((r) => r.hasFocus);
  final local = editable.getLocalRectForCaret(editable.selection!.extent);
  return MatrixUtils.transformRect(editable.getTransformTo(null), local);
}

void main() {
  setUpAll(setUpHostHarness);
  setUp(() async => resetHost());

  for (final (step, key, title) in [
    (HostStep.tagline, 'tagline', 'Write a short tagline'),
    (HostStep.bio, 'bio', 'A little more about you'),
  ]) {
    testWidgets('375×667: the $key field and Continue stay above the '
        'keyboard; typing and the keyboard rebuild no step', (tester) async {
      await _parkDraft(step);
      phone(tester, size: const Size(375, 667), top: 20);
      await pumpRoutes(tester, const HostOnboardingScreen());
      expect(find.text(title), findsOneWidget);

      final field = find.byKey(ValueKey('hostflow-$key'));
      await tester.tap(field);
      await tester.pump();
      const keyboard = 260.0;
      final frames = await _raiseKeyboard(tester, keyboard);
      await pumpFor(tester, 300);
      expect(tester.takeException(), isNull);

      // Only the inset wrapper follows the keyboard.
      for (final name in [
        'HostOnboardingScreen',
        '_Flow',
        'TaglineStep',
        'BioStep',
        'HostStepBody',
        'HostPromptSuggestions',
        'HostContinueBar',
      ]) {
        expect(frames[name], isNull, reason: '$name rebuilt on keyboard');
      }

      final button = tester.getRect(
        find.byKey(const ValueKey('hostflow-continue')),
      );
      expect(button.bottom, lessThanOrEqualTo(667 - keyboard));
      // The field shows, and the caret (end of the text) clears the bar.
      final box = tester.getRect(field);
      expect(box.top, lessThan(button.top - 40));
      final caret = _caretRect(tester);
      expect(caret.top, greaterThanOrEqualTo(0));
      expect(caret.bottom, lessThanOrEqualTo(button.top));

      final typed = await _typing(tester, field, 'Real talks, every day.');
      for (final name in [
        'TaglineStep',
        'BioStep',
        'HostStepBody',
        'HostPromptSuggestions',
        'HostContinueBar',
      ]) {
        expect(typed[name], isNull, reason: '$name rebuilt while typing');
      }
      final max = key == 'tagline' ? 60 : 500;
      expect(find.text('22/$max'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await finishHost(tester);
    });
  }

  testWidgets('320 wide, Hindi, every screen: no overflow', (tester) async {
    for (final step in HostStep.values) {
      await AppPrefs.remove('hostflow_draft_v1:u1');
      await _parkDraft(step);
      phone(tester, size: const Size(320, 568), top: 20);
      await pumpRoutes(
        tester,
        HostOnboardingScreen(key: ValueKey(step)),
        locale: const Locale('hi'),
      );
      await pumpFor(tester, 600);
      expect(tester.takeException(), isNull, reason: '$step');
      if (step != HostStep.intro) {
        // Video intros are off here: the Video step is skipped and left out
        // of "N of M", like the header does.
        final shown = [
          for (final s in HostStep.values)
            if (s != HostStep.submitted && s != HostStep.video) s,
        ];
        final current = shown.where((s) => s.index < step.index).length + 1;
        expect(find.text('${shown.length + 1} में से $current'), findsOne);
        final scroll = find.byType(Scrollable).last;
        await tester.fling(scroll, const Offset(0, -2000), 2500);
        await pumpFor(tester, 600);
        expect(tester.takeException(), isNull, reason: '$step scrolled');
      } else {
        expect(find.text('होस्ट बनें'), findsOneWidget);
      }
      await finishHost(tester);
    }
  });

  testWidgets('dark theme renders every form step', (tester) async {
    for (final step in [
      HostStep.basic,
      HostStep.rates,
      HostStep.preview,
      HostStep.guidelines,
    ]) {
      await AppPrefs.remove('hostflow_draft_v1:u1');
      await _parkDraft(step);
      phone(tester);
      await pumpRoutes(
        tester,
        HostOnboardingScreen(key: ValueKey(step)),
        theme: ThemeMode.dark,
      );
      await pumpFor(tester, 400);
      expect(tester.takeException(), isNull, reason: '$step');
      await finishHost(tester);
    }
  });

  testWidgets('design: bundled intro photo, flat (no shadows), every '
      'screen', (tester) async {
    for (final theme in [ThemeMode.light, ThemeMode.dark]) {
      for (final step in HostStep.values) {
        await AppPrefs.remove('hostflow_draft_v1:u1');
        await _parkDraft(step);
        phone(tester);
        await pumpRoutes(
          tester,
          HostOnboardingScreen(key: ValueKey('$theme$step')),
          theme: theme,
        );
        await pumpFor(tester, 300);
        if (step == HostStep.intro) {
          final image = tester.widget<Image>(find.byType(Image).first);
          final provider = image.image as ResizeImage;
          expect(
            (provider.imageProvider as AssetImage).assetName,
            AppImages.hostIntro,
          );
          expect(provider.width, isNotNull); // decoded at display size
        }
        expectFlat(tester, '$theme $step');
        if (step == HostStep.basic) {
          // A sheet of the flow, open.
          await tester.tap(find.bySemanticsLabel('Add a language'));
          await pumpFor(tester, 500);
          expect(find.text('English'), findsWidgets);
          expectFlat(tester, '$theme language sheet');
        }
        await finishHost(tester);
      }
    }
  });
}
