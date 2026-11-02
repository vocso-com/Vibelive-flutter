import 'package:image_picker/image_picker.dart';

import '../../../../core/config/runtime_config.dart';
import '../../../../core/query/query_hooks.dart';
import '../../../../core/utils/log.dart';
import '../../../api/host_status/host_status_api.dart';
import '../../../api/host_status/host_status_models.dart';
import '../../../api/host_status/host_status_queries.dart';
import '../../../component/c_toast.dart';

/// Records a Vibe (host status) with the camera and posts it: what the
/// host's own circle and its "+" on the Home Vibes row do.
///
/// Every limit is the admin's (Host Media settings, via the runtime config):
/// the camera stops at [RuntimeHostMedia.statusLimit]; a host who has used
/// today's allowance is told so before recording, not after; and the message
/// after posting follows the review switch ("live now" or "shows once checked").
///
/// The clip is captured, never chosen from the gallery: [ImageSource.camera]
/// is what makes "recorded in-app" true and what stops a reviewer being
/// handed something downloaded off the internet.
Future<void> captureStatus(
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
    final file = await ImagePicker().pickVideo(
      source: ImageSource.camera,
      maxDuration: media.statusLimit,
    );
    // Null is a cancel or a refused camera permission: the host's choice
    // either way, and not an error worth showing.
    if (file == null) return;
    await post.mutateAsync(
      HostStatusDraft(file.path, recordedAt: DateTime.now()),
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
