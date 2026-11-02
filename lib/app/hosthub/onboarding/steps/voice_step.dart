import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/utils/scale.dart';
import '../../../component/c_text.dart';
import '../../common/host_page.dart';
import '../../common/host_review.dart';
import '../helper/draft_controller.dart';
import '../helper/draft_models.dart';
import '../helper/host_palette.dart';
import '../widgets/step_body.dart';
import '../widgets/voice_intro_field.dart';

/// 5 of 13: "Introduce yourself", a short recorded hello callers hear before
/// they call (RN "Voice Intro"). Required: Continue needs a recording.
/// Around the recorder: a ready-made opener built from the host's own name
/// and topics, and what makes a good intro.
class VoiceStep extends StatelessWidget {
  const VoiceStep({super.key, required this.draft});
  final HostDraftController draft;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    return HostStepBody(
      title: 'hostflow:voice_step.title',
      subtitle: 'hostflow:voice_step.subtitle',
      children: [
        if (HostReviewScope.of(context).audioRejected)
          _Rejected(intro: draft.voiceIntro),
        HostVoiceIntroField(draft: draft),
        SizedBox(height: 14.ms),
        _Opener(draft: draft),
        // The video intro has its own step next (VideoStep).
        SizedBox(height: 12.ms),
        HostCard(
          color: p.tint,
          borderColor: p.tint,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.lightbulb, size: 20.ms, color: p.accent),
                  SizedBox(width: 8.ms),
                  Expanded(
                    child: CText(
                      'hostflow:voice_step.tips_title',
                      size: 17,
                      weight: FontWeight.w700,
                      color: p.accent,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8.ms),
              for (final k in const ['tip1', 'tip2', 'tip3', 'tip4'])
                Padding(
                  padding: EdgeInsets.only(top: 6.ms),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(LucideIcons.check, size: 16.ms, color: p.accent),
                      SizedBox(width: 8.ms),
                      Expanded(
                        child: CText(
                          'hostflow:voice_step.$k',
                          size: 14.5,
                          weight: FontWeight.w500,
                          color: p.text,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        SizedBox(height: 14.ms),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(LucideIcons.headphones, size: 15.ms, color: p.muted),
            SizedBox(width: 8.ms),
            Expanded(
              child: CText(
                'hostflow:voice_step.note',
                size: 12.5,
                weight: FontWeight.w500,
                color: p.muted,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// "Your voice intro wasn't approved": until a new one is recorded.
class _Rejected extends StatelessWidget {
  const _Rejected({required this.intro});
  final ValueListenable<HostVoiceIntro?> intro;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<HostVoiceIntro?>(
    valueListenable: intro,
    builder: (_, value, _) => value?.isNew ?? false
        ? const SizedBox.shrink()
        : Padding(
            padding: EdgeInsets.only(bottom: 14.ms),
            child: const HostToneCard(
              tone: HostTone.danger,
              icon: LucideIcons.micOff,
              title: 'hostflow:fix.voice_title',
              message: 'hostflow:fix.voice_body',
            ),
          ),
  );
}

/// "Need a start? Try this": an opener with the host's first name and up to
/// two of their topics, to read out (or make their own).
class _Opener extends StatelessWidget {
  const _Opener({required this.draft});
  final HostDraftController draft;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([draft.name, draft.topics]),
      builder: (context, _) {
        final first = draft.name.text.trim().split(RegExp(r'\s+')).first;
        final topics = [
          for (final t in draft.topics.value.take(2))
            if (t.label.trim().isNotEmpty) t.label.trim().toLowerCase(),
        ];
        final and = context.t('hostflow:voice_step.and');
        return HostCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.quote, size: 16.ms, color: p.accent),
                  SizedBox(width: 8.ms),
                  Expanded(
                    child: CText(
                      'hostflow:voice_step.script_title',
                      size: 14,
                      weight: FontWeight.w800,
                      color: p.text,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8.ms),
              CText(
                topics.isEmpty
                    ? 'hostflow:voice_step.script_plain'
                    : 'hostflow:voice_step.script',
                variables: {
                  'name': first.isEmpty ? '…' : first,
                  'topics': topics.join(' $and '),
                },
                size: 14,
                height: 21,
                weight: FontWeight.w500,
                color: p.muted,
              ),
            ],
          ),
        );
      },
    );
  }
}
