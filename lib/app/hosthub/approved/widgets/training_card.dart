import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/utils/scale.dart';
import '../../../api/hosthub/training_queries.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../../onboarding/helper/host_palette.dart';
import '../../onboarding/training/training_screen.dart';
import '../../onboarding/widgets/step_body.dart';

/// "Host training" on the ME tab for a host who already has a profile
/// (docs/host_onboarding.md): the admin's videos and quizzes still to do,
/// when the admin shows training to existing hosts. Never required: the
/// training has "Skip for now". Nothing when there is nothing to do.
class HostTrainingCard extends HookWidget {
  const HostTrainingCard({super.key});

  @override
  Widget build(BuildContext context) {
    final config = useHostTraining(context).data;
    if (config == null || !config.reaches(existing: true)) {
      return const SizedBox.shrink();
    }
    final pending = config.pendingAll();
    if (pending.isEmpty) return const SizedBox.shrink();
    final p = HostPalette.of(context);
    return Padding(
      padding: EdgeInsets.only(top: 12.ms),
      child: Pressable(
        key: const ValueKey('host-training-card'),
        activeOpacity: 0.85,
        onPressed: () =>
            HostTraining.open(context, pending, config, optional: true),
        child: HostCard(
          padding: EdgeInsets.all(14.ms),
          child: Row(
            children: [
              Container(
                width: 40.ms,
                height: 40.ms,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.tint,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  LucideIcons.graduationCap,
                  size: 20.ms,
                  color: p.accent,
                ),
              ),
              SizedBox(width: 12.ms),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CText(
                      'hosttraining:card_title',
                      size: 15,
                      weight: FontWeight.w800,
                      color: p.text,
                    ),
                    SizedBox(height: 2.ms),
                    CText(
                      'hosttraining:card_body',
                      variables: {'count': pending.length},
                      size: 12.5,
                      weight: FontWeight.w500,
                      color: p.muted,
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8.ms),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: 12.ms,
                  vertical: 7.ms,
                ),
                decoration: BoxDecoration(
                  color: p.accent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: CText(
                  'hosttraining:card_cta',
                  size: 12.5,
                  weight: FontWeight.w800,
                  color: p.onAccent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
