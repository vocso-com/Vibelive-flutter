import 'package:image_picker/image_picker.dart';

import '../../../../core/query/query_hooks.dart';
import '../../../../core/utils/log.dart';
import '../../../api/host_status/host_status_api.dart';
import '../../../api/host_status/host_status_models.dart';
import '../../../api/host_status/host_status_queries.dart';
import '../../../component/c_toast.dart';

/// Records a Vibe (host status) with the camera and posts it: what the
/// host's own circle and its "+" on the Home Vibes row do.
///
/// The clip is captured, never chosen from the gallery: [ImageSource.camera]
/// is what makes "recorded in-app" true and what stops a reviewer being
/// handed something downloaded off the internet.
Future<void> captureStatus(
  MutationResult<HostOwnStatus?, ApiException, HostStatusDraft> post,
) async {
  if (post.isPending) return;
  try {
    final file = await ImagePicker().pickVideo(
      source: ImageSource.camera,
      maxDuration: statusMaxDuration,
    );
    // Null is a cancel or a refused camera permission: the host's choice
    // either way, and not an error worth showing.
    if (file == null) return;
    await post.mutateAsync(
      HostStatusDraft(file.path, recordedAt: DateTime.now()),
    );
    CToast.show('hostflow:my_status.posted');
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

/// The longest clip the camera records for a status.
const statusMaxDuration = Duration(seconds: 30);
