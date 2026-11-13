import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../component/c_alert.dart';
import '../../component/c_toast.dart';
import 'call_actions.dart';

/// i18n keys of the call logic (namespace `callflow`). Bodies the call API
/// already has stay in `call:errors.*`.
abstract final class CallFlowKeys {
  static const busyTitle = 'callflow:errors.busy_title';
  static const failedTitle = 'callflow:errors.failed_title';
  static const unableTitle = 'callflow:errors.unable_title';
  static const missingExpert = 'callflow:errors.missing_expert';

  static const permissionOpenSettings = 'callflow:permission.open_settings';
  static String permissionTitle({required bool video}) =>
      'callflow:permission.${_what(video)}_title';
  static String permissionBlocked({required bool video}) =>
      'callflow:permission.${_what(video)}_blocked';
  static String permissionDenied({required bool video}) =>
      'callflow:permission.${_what(video)}_denied';
  static String _what(bool video) => video ? 'mic_camera' : 'mic';

  static const safetyTitle = 'callflow:safety.thanks_title';

  /// The "Thanks for telling us" message for an in-call report / block.
  static String safetyMessage(
    CallSafetyOutcome outcome, {
    required bool block,
  }) => switch (outcome) {
    CallSafetyOutcome.done =>
      block ? 'callflow:safety.blocked' : 'callflow:safety.reported',
    CallSafetyOutcome.noTarget => 'callflow:safety.no_target',
    CallSafetyOutcome.failed =>
      block ? 'callflow:safety.block_failed' : 'callflow:safety.report_failed',
  };

  static const lowBalanceWarning = 'callflow:low_balance.warning';
  static const lowBalanceEnded = 'callflow:low_balance.ended';
  static const freeEndingSoon = 'callflow:free_call.ending';
  static const freeEnded = 'callflow:free_call.ended';
}

/// Alerts and toasts of the call logic: [CAlert] / [CToast] (root
/// navigator, no context needed), recorded in tests.
abstract final class CallAlerts {
  /// Tests: every alert / toast as `title|message` (keys, or the error's
  /// message key).
  @visibleForTesting
  static List<String>? debugLog;

  static Future<bool?> show({
    required String title,
    String? message,
    Map<String, dynamic>? variables,
    CAlertVariant variant = CAlertVariant.error,
    String primaryLabel = 'actions.ok',
    String? secondaryLabel,
  }) async {
    debugLog?.add('$title|$message');
    try {
      return await CAlert.show(
        title: title,
        message: message,
        variables: variables,
        variant: variant,
        primaryLabel: primaryLabel,
        secondaryLabel: secondaryLabel,
      );
    } catch (_) {
      return null;
    }
  }

  /// [error]'s own copy (readable server message, else its key) under
  /// [title].
  static Future<void> error(Object error, {required String title}) async {
    final e = error is ApiException ? error : ApiException.from(error);
    debugLog?.add('$title|${e.messageKey ?? e.serverMessage ?? e.type.name}');
    try {
      await CAlert.error(e, title: title);
    } catch (_) {}
  }

  static void toast(String key, {CToastVariant variant = CToastVariant.info}) {
    debugLog?.add('toast|$key');
    try {
      CToast.show(key, variant: variant, duration: const Duration(seconds: 5));
    } catch (_) {}
  }
}
