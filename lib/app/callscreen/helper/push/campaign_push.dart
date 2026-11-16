import '../../../api/authscreen/push_api.dart';
import '../../../api/authscreen/push_queries.dart';
import '../../../authscreen/helper/deep_links.dart';
import 'local_notifier.dart';
import 'notification_channels.dart';
import 'push_envelope.dart';
import 'push_strings.dart';

/// Orchestrator campaign / sequence pushes (campaign memory): drawn locally
/// in the foreground on both platforms, opened through
/// [DeepLinks.queueCampaign], tracked (`opened` on tap, `clicked` once the
/// link opened).
abstract final class CampaignPush {
  static Future<void> present(PushEnvelope m) async {
    final key = m.messageId ?? pushTrackingIdOf(m.data) ?? m.deeplink ?? '';
    final id = 'campaign_$key';
    await LocalNotifier.show(
      id: id,
      title: m.title ?? PushStrings.appName,
      body: m.body,
      envelope: m.copyWith(
        data: {
          ...m.data,
          '__vibePush': '1',
          if (m.messageId != null) '__messageId': m.messageId!,
        },
        notificationId: id,
      ),
      channelId: NotificationChannels.campaigns,
      imageUrl: m.imageUrl,
    );
  }

  /// A tap: report `opened`, then queue the link (it waits for the
  /// signed-in app, see [DeepLinks]).
  static void open(PushEnvelope m) {
    trackPushEvent(PushEvent.opened, m.raw);
    final link = m.deeplink;
    if (link == null) return;
    DeepLinks.instance.queueCampaign(link, fromPush: true, data: m.raw);
  }
}
