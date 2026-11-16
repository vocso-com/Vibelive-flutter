import 'dart:async';
import 'dart:io' show File, HttpClient, Platform;
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../../core/utils/log.dart';
import 'notification_channels.dart';
import 'push_envelope.dart';

/// The one wrapper around `flutter_local_notifications` (RN notifee).
///
/// String ids (`wallet_topup_latest`, …) map to stable ints, so a later
/// notification with the same id replaces the earlier one, as notifee did.
/// Never throws: a notification is never worth a crash.
abstract final class LocalNotifier {
  static final plugin = FlutterLocalNotificationsPlugin();
  static bool _initialised = false;

  static const smallIcon = 'ic_notification';
  static const brand = Color(0xFF561DE2);

  static Future<void> init({
    DidReceiveNotificationResponseCallback? onTap,
    DidReceiveBackgroundNotificationResponseCallback? onBackgroundTap,
  }) async {
    if (_initialised) return;
    _initialised = true;
    try {
      await plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings(smallIcon),
          // Permission is requested once, through FirebaseMessaging.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: onTap,
        onDidReceiveBackgroundNotificationResponse: onBackgroundTap,
      );
    } catch (e) {
      _initialised = false;
      Log.w('LocalNotifier', 'init failed: $e');
    }
  }

  /// Positive 31-bit FNV-1a id from a string, stable across launches (CE).
  static int idFor(String key) {
    var hash = 0x811C9DC5;
    for (final unit in key.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0x7FFFFFFF;
    }
    return hash;
  }

  static Future<void> show({
    required String id,
    required String? title,
    required String? body,
    required PushEnvelope envelope,
    required String channelId,
    bool autoCancel = true,
    String? imageUrl,
  }) async {
    if (!_initialised) await init();
    // A picture (a campaign's or an admin test's): shown big when it can be
    // fetched in a few seconds; otherwise the plain notification, as before.
    final picture = imageUrl == null ? null : await fetchImage(imageUrl);
    final attachment = picture == null || !Platform.isIOS
        ? null
        : await _attachmentFile(id, imageUrl!, picture);
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        NotificationChannels.nameOf(channelId),
        importance: Importance.high,
        priority: Priority.high,
        icon: smallIcon,
        color: brand,
        sound: NotificationChannels.soundOf(channelId),
        autoCancel: autoCancel,
        showWhen: true,
        visibility: NotificationVisibility.public,
        largeIcon: picture == null ? null : ByteArrayAndroidBitmap(picture),
        styleInformation: picture == null
            ? null
            : BigPictureStyleInformation(
                ByteArrayAndroidBitmap(picture),
                contentTitle: title,
                summaryText: body,
                hideExpandedLargeIcon: true,
              ),
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBanner: true,
        presentList: true,
        presentBadge: true,
        presentSound: true,
        attachments: attachment == null
            ? null
            : [DarwinNotificationAttachment(attachment)],
      ),
    );
    try {
      await plugin.show(
        id: idFor(id),
        title: title,
        body: body,
        notificationDetails: details,
        payload: envelope.copyWith(notificationId: id).toPayload(),
      );
    } catch (e) {
      Log.w('LocalNotifier', 'show $id failed: $e');
    }
  }

  /// Fetches a notification picture: https only, a few seconds and 2 MB at
  /// most; null on anything else (tests swap it).
  @visibleForTesting
  static Future<Uint8List?> Function(String url) fetchImage = _download;

  static Future<Uint8List?> _download(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 5));
      final response = await request.close().timeout(
        const Duration(seconds: 6),
      );
      if (response.statusCode != 200) return null;
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(const Duration(seconds: 6))) {
        bytes.add(chunk);
        if (bytes.length > 2 * 1024 * 1024) return null;
      }
      return bytes.isEmpty ? null : bytes.takeBytes();
    } catch (e) {
      Log.d('LocalNotifier', 'picture not fetched: $e');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// iOS shows a picture from a file: written to the temp folder.
  static Future<String?> _attachmentFile(
    String id,
    String url,
    Uint8List bytes,
  ) async {
    try {
      final dir = await getTemporaryDirectory();
      final ext = url.toLowerCase().contains('.png') ? 'png' : 'jpg';
      final file = File('${dir.path}/push_${idFor(id)}.$ext');
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (e) {
      Log.d('LocalNotifier', 'picture not attached: $e');
      return null;
    }
  }

  static Future<void> cancel(int id) async {
    try {
      await plugin.cancel(id: id);
    } catch (_) {}
  }

  static Future<void> cancelAll() async {
    try {
      await plugin.cancelAll();
    } catch (_) {}
  }

  /// The app was started by tapping one of our notifications (read once).
  static Future<PushEnvelope?> launchEnvelope() async {
    if (!(Platform.isAndroid || Platform.isIOS)) return null;
    try {
      final details = await plugin.getNotificationAppLaunchDetails();
      if (details == null || !details.didNotificationLaunchApp) return null;
      return PushEnvelope.fromPayload(details.notificationResponse?.payload);
    } catch (_) {
      return null;
    }
  }

  /// Android: notifications currently in the tray (sweeps). Empty elsewhere.
  static Future<List<ActiveNotification>> active() async {
    if (!Platform.isAndroid) return const [];
    try {
      return await plugin.getActiveNotifications();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> cancelActive(ActiveNotification n) async {
    final id = n.id;
    if (id == null) return;
    try {
      await plugin.cancel(id: id, tag: n.tag);
    } catch (_) {}
  }
}
