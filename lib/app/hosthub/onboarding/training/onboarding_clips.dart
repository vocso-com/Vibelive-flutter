import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/analytics/events/host_events.dart';
import '../../../../core/utils/scale.dart';
import '../../../api/hosthub/training_models.dart';
import '../../../api/hosthub/training_queries.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../helper/host_palette.dart';
import '../helper/host_steps.dart';
import '../widgets/step_body.dart';
import 'training_player.dart';

/// An onboarding step with the admin's clips for it (docs/host_onboarding.md)
/// at the top of its page, scrolling with it (a [HostStepHeader] the step's
/// [HostStepBody] shows first): a swipeable frame of short videos the host
/// can hide. With no clips for [step] (or training off) it is exactly
/// [child].
///
/// [current]: the step on screen. A clip plays only while its step is the
/// current one (the page view builds the neighbours during a slide).
class HostStepWithClips extends HookWidget {
  const HostStepWithClips({
    super.key,
    required this.step,
    required this.current,
    required this.child,
    this.existing = false,
  });

  final HostStep step;
  final ValueListenable<HostStep> current;
  final Widget child;

  /// A host who already has a profile (editing a section, or going through
  /// the form again): clips only when the admin shows training to them too.
  final bool existing;

  /// Hidden by the host, per step, for this run of the app.
  @visibleForTesting
  static final hidden = <String>{};

  @override
  Widget build(BuildContext context) {
    final clips = useStepClips(context, step, existing: existing);
    if (clips.isEmpty) return child;
    return HostStepHeader(
      header: _ClipFrame(
        key: ValueKey('onboarding-clips-${step.name}'),
        step: step,
        current: current,
        clips: clips,
        // The page's own side padding.
        inset: 0,
      ),
      child: child,
    );
  }
}

/// The admin's clips for [step]; none while training is off or unknown, or
/// for an [existing] host unless the admin shows training to them too.
List<TrainingClip> useStepClips(
  BuildContext context,
  HostStep step, {
  bool existing = false,
}) {
  final config = useHostTraining(context).data;
  return config != null && config.reaches(existing: existing)
      ? config.clipsOn(step.name)
      : const <TrainingClip>[];
}

/// Just the clips frame for [step] (nothing when it has none), for a screen
/// that places it itself: the always-dark Welcome screen ([palette]).
class HostClipsFrame extends HookWidget {
  const HostClipsFrame({
    super.key,
    required this.step,
    required this.current,
    this.existing = false,
    this.palette,
  });

  final HostStep step;
  final ValueListenable<HostStep> current;
  final bool existing;
  final HostPalette? palette;

  @override
  Widget build(BuildContext context) {
    final clips = useStepClips(context, step, existing: existing);
    if (clips.isEmpty) return const SizedBox.shrink();
    return _ClipFrame(
      key: ValueKey('onboarding-clips-${step.name}'),
      step: step,
      current: current,
      clips: clips,
      palette: palette,
      inset: 0,
    );
  }
}

class _ClipFrame extends HookWidget {
  const _ClipFrame({
    super.key,
    required this.step,
    required this.current,
    required this.clips,
    this.palette,
    this.inset,
  });

  final HostStep step;
  final ValueListenable<HostStep> current;
  final List<TrainingClip> clips;
  final HostPalette? palette;

  /// Side padding (null: the form steps' own).
  final double? inset;

  @override
  Widget build(BuildContext context) {
    final p = palette ?? HostPalette.of(context);
    final side = inset ?? 16.ms;
    final active = useValueListenable(current) == step;
    final open = useState(!HostStepWithClips.hidden.contains(step.name));
    final page = useState(0);
    final controller = usePageController();
    useEffect(() {
      if (active) {
        HostEvents.onboardingClipsShown(step: step.name, count: clips.length);
      }
      return null;
    }, [active]);

    void toggle() {
      open.value = !open.value;
      open.value
          ? HostStepWithClips.hidden.remove(step.name)
          : HostStepWithClips.hidden.add(step.name);
    }

    if (!open.value) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          inset ?? 20.ms,
          4.ms,
          inset ?? 20.ms,
          4.ms,
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Pressable(
            key: const ValueKey('onboarding-clips-show'),
            onPressed: toggle,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12.ms, vertical: 7.ms),
              decoration: BoxDecoration(
                color: p.tint,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: p.tintBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.circlePlay, size: 16.ms, color: p.accent),
                  SizedBox(width: 6.ms),
                  CText(
                    clips.length == 1
                        ? 'hosttraining:clips_show'
                        : 'hosttraining:clips_show_many',
                    variables: {'count': clips.length},
                    size: 12.5,
                    weight: FontWeight.w700,
                    color: p.accent,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final clip = clips[page.value.clamp(0, clips.length - 1)];
    // A frame on a form: a third of a small phone at most.
    final height = (MediaQuery.sizeOf(context).height * 0.26).clamp(
      150.0,
      240.0,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(side, 6.ms, side, 4.ms),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: height,
            child: PageView.builder(
              controller: controller,
              itemCount: clips.length,
              onPageChanged: (i) => page.value = i,
              itemBuilder: (_, i) => Padding(
                padding: EdgeInsets.symmetric(horizontal: 2.ms),
                child: Center(
                  child: TrainingPlayer(
                    key: ValueKey('onboarding-clip-${clips[i].id}'),
                    video: clips[i].video,
                    // Each plays on its own (when set to) while it is the
                    // one in view and its step is on screen.
                    autoplay: clips[i].autoplay,
                    startMuted: clips[i].startMuted,
                    loop: clips[i].loop,
                    active: active && i == page.value,
                    compact: true,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: 6.ms),
          Row(
            children: [
              Expanded(
                child: clip.title.isEmpty
                    ? const SizedBox.shrink()
                    : CText.raw(
                        clip.title,
                        size: 12.5,
                        weight: FontWeight.w700,
                        color: p.text,
                        maxLines: 1,
                      ),
              ),
              if (clips.length > 1)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < clips.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: EdgeInsets.symmetric(horizontal: 2.ms),
                        width: i == page.value ? 14.ms : 6.ms,
                        height: 6.ms,
                        decoration: BoxDecoration(
                          color: i == page.value ? p.accent : p.track,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                  ],
                ),
              SizedBox(width: 8.ms),
              Pressable(
                key: const ValueKey('onboarding-clips-hide'),
                onPressed: toggle,
                hitPadding: EdgeInsets.all(8.ms),
                child: CText(
                  'hosttraining:clips_hide',
                  size: 12,
                  weight: FontWeight.w700,
                  color: p.muted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
