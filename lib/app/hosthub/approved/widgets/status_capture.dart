import 'package:flutter/widgets.dart';
import 'package:vibe_camera/vibe_camera.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/theme/vibe_colors.dart';

import '../../../../core/config/runtime_config.dart';
import '../../../../core/query/query_hooks.dart';
import '../../../../core/utils/log.dart';
import '../../../api/host_status/host_status_api.dart';
import '../../../api/host_status/host_status_models.dart';
import '../../../api/host_status/host_status_queries.dart';
import '../../../callscreen/call/helper/call_permission_state.dart';
import '../../../component/c_toast.dart';

/// Records a Vibe (host status) with our own camera (packages/vibe-camera:
/// live looks and light, up to 120 fps, then trim, crop, text) and posts it:
/// what the host's own circle and its "+" on the Home Vibes row do.
///
/// Every limit is the admin's (Host Media settings, via the runtime config):
/// the camera stops at [RuntimeHostMedia.statusLimit]; a host who has used
/// today's allowance is told so before recording, not after; and the message
/// after posting follows the review switch ("live now" or "shows once checked").
///
/// The clip is recorded in the app, never chosen from the gallery: that is
/// what makes "recorded in-app" true and what stops a reviewer being handed
/// something downloaded off the internet.
Future<void> captureStatus(
  BuildContext context,
  MutationResult<HostOwnStatus?, ApiException, HostStatusDraft> post, {
  required RuntimeHostMedia media,
  List<HostOwnStatus> mine = const [],
}) async {
  if (post.isPending) return;
  if (postedToday(mine) >= media.statusMaxPerDay) {
    CToast.show(HostStatusErrorKeys.dailyLimit, variant: CToastVariant.error);
    return;
  }
  try {
    final clip = await VibeCamera.open(
      context,
      config: VibeCameraConfig(
        maxDuration: media.statusLimit,
        // 30 fps: a fraction of the size at 120 (an unedited clip uploads as
        // recorded), so Vibes load fast for the people watching them.
        preferredFps: 30,
        maxOutputFps: 30,
        accent: context.colors.accent,
        strings: vibeCameraStrings(context),
        onOpenSettings: () => openCallSettings(),
      ),
    );
    // Null: closed without a clip — the host's choice, not an error.
    if (clip == null) return;
    await post.mutateAsync(
      HostStatusDraft(clip.file.path, recordedAt: clip.recordedAt),
    );
    CToast.show(
      media.statusAutoApprove
          ? 'hostflow:my_status.posted_live'
          : 'hostflow:my_status.posted',
    );
    // Live at once: the Home row shows it now, not on its next refresh.
    if (media.statusAutoApprove) invalidateStatusFeed();
  } on ApiException catch (e) {
    // The server refuses a status for reasons a host can act on: the
    // feature is not switched on, or they have used today's allowance.
    // Those need different things from them — wait for us, or come back
    // tomorrow — so showing one generic failure for both helps nobody.
    Log.d('MyStatuses', 'post refused: ${e.serverMessage ?? e}');
    CToast.show(
      HostStatusApi.knownErrorKey(e) ?? HostStatusErrorKeys.postFailed,
      variant: CToastVariant.error,
    );
  } catch (e) {
    Log.d('MyStatuses', 'post failed: $e');
    CToast.show(HostStatusErrorKeys.postFailed, variant: CToastVariant.error);
  }
}

/// Posts in the last 24 hours, counted as the server counts them (rolling,
/// whatever a reviewer decided).
int postedToday(List<HostOwnStatus> mine, {DateTime? now}) {
  final since = (now ?? DateTime.now()).subtract(const Duration(hours: 24));
  return mine.where((s) => s.recordedAt?.isAfter(since) ?? false).length;
}

/// The camera's words, in the app's language (hostflow:camera.*). Filter
/// names stay as they are, like most camera apps.
VibeCameraStrings vibeCameraStrings(BuildContext context) {
  String t(String key) => context.t('hostflow:camera.$key');
  return VibeCameraStrings(
    close: t('close'),
    flip: t('flip'),
    flash: t('flash'),
    light: t('light'),
    holdToRecord: t('tap_to_record'),
    tooShort: t('too_short'),
    cameraDenied: t('camera_denied'),
    cameraFailed: t('camera_failed'),
    openSettings: t('open_settings'),
    retry: t('retry'),
    retake: t('retake'),
    done: t('done'),
    filters: t('filters'),
    adjust: t('adjust'),
    trim: t('trim'),
    crop: t('crop'),
    text: t('text'),
    brightness: t('brightness'),
    contrast: t('contrast'),
    saturation: t('saturation'),
    warmth: t('warmth'),
    cropOriginal: t('crop_original'),
    addText: t('add_text'),
    typeSomething: t('type_something'),
    dragToDelete: t('drag_to_delete'),
    saving: t('saving'),
    saveFailed: t('save_failed'),
    cancel: t('cancel'),
    discardTitle: t('discard_title'),
    discard: t('discard'),
    keepEditing: t('keep_editing'),
    gallery: t('gallery'),
  );
}
