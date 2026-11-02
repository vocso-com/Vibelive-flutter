import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/utils/scale.dart';
import '../../../component/c_text.dart';
import '../../common/host_page.dart';
import '../../common/host_review.dart';
import '../helper/draft_controller.dart';
import '../helper/draft_models.dart';
import '../helper/host_palette.dart';
import '../widgets/step_body.dart';
import '../widgets/video_intro_field.dart';

/// 6 of 13: "Show your face", an optional short video hello on the profile.
/// Recorded with the app's camera (the one Vibes use) or picked from the
/// gallery, trimmed to the admin's limit, reviewed before clients see it.
/// Continue never needs it. Skipped by the flow while video intros are off.
class VideoStep extends StatelessWidget {
  const VideoStep({super.key, required this.draft});
  final HostDraftController draft;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    return HostStepBody(
      title: 'hostflow:video_step.title',
      subtitle: 'hostflow:video_step.subtitle',
      children: [
        if (HostReviewScope.of(context).videoRejected)
          _Rejected(intro: draft.videoIntro),
        HostVideoIntroField(draft: draft),
        SizedBox(height: 14.ms),
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
                      'hostflow:video_step.tips_title',
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
                          'hostflow:video_step.$k',
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
            Icon(LucideIcons.shieldCheck, size: 15.ms, color: p.muted),
            SizedBox(width: 8.ms),
            Expanded(
              child: CText(
                'hostflow:video_step.note',
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

/// "Your video intro wasn't approved": until a new one is recorded.
class _Rejected extends StatelessWidget {
  const _Rejected({required this.intro});
  final ValueListenable<HostVideoIntro?> intro;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<HostVideoIntro?>(
    valueListenable: intro,
    builder: (_, value, _) => value?.path != null
        ? const SizedBox.shrink()
        : Padding(
            padding: EdgeInsets.only(bottom: 14.ms),
            child: const HostToneCard(
              tone: HostTone.danger,
              icon: LucideIcons.videoOff,
              title: 'hostflow:fix.video_title',
              message: 'hostflow:fix.video_body',
            ),
          ),
  );
}
