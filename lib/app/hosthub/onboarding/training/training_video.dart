import 'package:flutter/material.dart';

import '../../../../core/analytics/events/host_events.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/utils/log.dart';
import '../../../../core/utils/scale.dart';
import '../../../api/hosthub/training_api.dart';
import '../../../api/hosthub/training_models.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../helper/host_palette.dart';
import '../widgets/continue_bar.dart';
import 'training_player.dart';
import 'training_screen.dart';

/// A training video. Continue opens at once, or (must watch) once it has
/// played to the end; a Skip shows after the admin's seconds when allowed.
/// A video that cannot play never keeps the host here.
class TrainingVideoStep extends StatefulWidget {
  const TrainingVideoStep({
    super.key,
    required this.step,
    required this.onDone,
  });

  final TrainingStep step;
  final VoidCallback onDone;

  @override
  State<TrainingVideoStep> createState() => _TrainingVideoStepState();
}

class _TrainingVideoStepState extends State<TrainingVideoStep> {
  bool _completed = false;
  bool _failed = false;
  bool _saving = false;
  int _furthestSec = 0;

  TrainingStep get _step => widget.step;

  bool get _canContinue => _completed || !_step.mustWatch || _failed;

  /// Skip: only where watching is required (otherwise Continue already lets
  /// the host go on), after the admin's seconds of playing.
  bool get _showSkip =>
      _step.mustWatch &&
      _step.skippable &&
      !_completed &&
      (_failed || _furthestSec >= _step.skipAfterSec);

  Future<void> _finish({required bool skipped}) async {
    if (_saving) return;
    setState(() => _saving = true);
    final result = _completed ? 'watched' : (skipped ? 'skipped' : 'continued');
    HostEvents.trainingVideoDone(
      stepId: _step.id,
      result: result,
      seconds: _furthestSec,
    );
    var progress = TrainingProgress(
      status: skipped && !_completed ? 'skipped' : 'watched',
      done: true,
    );
    try {
      progress = await HostTrainingApi.watched(
        _step.id,
        seconds: _furthestSec,
        completed: _completed,
        skipped: skipped && !_completed,
      );
    } on ApiException catch (e) {
      // Never stuck on a video: not saved means it is asked again before
      // Submit (once the setup is read again), not that the host waits here.
      Log.w('HostTraining', 'video result not saved: $e');
    }
    recordTrainingProgress(
      _step,
      progress.done ? progress : const TrainingProgress(done: true),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    final maxVideo = MediaQuery.sizeOf(context).height * 0.52;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(20.ms, 18.ms, 20.ms, 16.ms),
            children: [
              TrainingHeading(step: _step),
              SizedBox(height: 18.ms),
              Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxVideo),
                  child: TrainingPlayer(
                    key: ValueKey('training-video-${_step.id}'),
                    video: _step.video!,
                    autoplay: _step.autoplay,
                    startMuted: _step.startMuted,
                    loop: _step.loop,
                    allowSeek: _step.allowSeek,
                    onProgress: (furthest, _) {
                      final secs = furthest.inSeconds;
                      if (secs != _furthestSec) {
                        setState(() => _furthestSec = secs);
                      }
                    },
                    onCompleted: () => setState(() => _completed = true),
                    onFailed: () => setState(() => _failed = true),
                  ),
                ),
              ),
              if (_step.mustWatch && !_completed && !_failed) ...[
                SizedBox(height: 14.ms),
                CText(
                  'hosttraining:watch_to_end',
                  key: const ValueKey('training-watch-hint'),
                  size: 13,
                  weight: FontWeight.w600,
                  color: p.muted,
                  align: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(20.ms, 8.ms, 20.ms, 16.ms),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_step.mustWatch && _step.skippable && !_completed) ...[
                Center(
                  child: _showSkip
                      ? Pressable(
                          key: const ValueKey('training-skip'),
                          onPressed: _saving
                              ? null
                              : () => _finish(skipped: true),
                          hitPadding: EdgeInsets.all(8.ms),
                          child: CText(
                            'hosttraining:skip',
                            size: 14,
                            weight: FontWeight.w700,
                            color: p.muted,
                          ),
                        )
                      : CText(
                          'hosttraining:skip_in',
                          variables: {
                            'seconds': (_step.skipAfterSec - _furthestSec)
                                .clamp(1, 600),
                          },
                          size: 13,
                          weight: FontWeight.w600,
                          color: p.faint,
                        ),
                ),
                SizedBox(height: 10.ms),
              ],
              HostButton(
                key: const ValueKey('training-continue'),
                label: 'hosttraining:continue',
                loading: _saving,
                onPressed: _canContinue ? () => _finish(skipped: false) : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
