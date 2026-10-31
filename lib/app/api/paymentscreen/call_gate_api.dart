import '../../../core/network/api_client.dart';
import '../../../core/network/strapi.dart';
import '../../../core/utils/log.dart';
import '../../paymentscreen/wallet/helper/balance_gate.dart';

/// Telemetry for the pre-call balance gate: the caller who was refused a call
/// because `rate x minMinutes` exceeded their wallet.
///
/// Why this exists: the gate decides in the client, before `/initiateCall` is
/// ever reached, so a blocked caller left no row anywhere and the calls table
/// silently meant "people who already had money". Of 2,189 signups only 79 ever
/// attempted a call — and of the 38 who reached a 30-second conversation, 18
/// paid. The gate, not the product, was the filter, and nothing recorded it.
///
/// Every call here fails open and silently — a deliberate exception to rule 2
/// of `docs/api_conventions.md` ("never catch an error just to return null"),
/// for the reason that rule allows. The sheet is already on screen by the time
/// these run: a slow, refused or offline request must never delay it, block the
/// caller or surface an error. Instrumentation that can break the flow it
/// measures is worse than none — the same reason the wallet and profile reads
/// before the gate already fail open.
abstract final class CallGateApi {
  static const _tag = 'CallGateApi';

  /// Records the block and returns the row's documentId, or null when the
  /// write did not land. A null simply costs one dropped row.
  static Future<String?> record({
    required BalanceGate gate,
    required String? expertProfileDocumentId,
    required bool video,
  }) async {
    try {
      final body = Strapi.map(
        await ApiClient.post(
          '/call-gate-blocks/record',
          data: {
            'expertProfileDocumentId': ?expertProfileDocumentId,
            'callType': video ? 'videoCall' : 'voiceCall',
            'rate': gate.rate,
            // The multiplier in force. Without it a row cannot say what the
            // gate was on the day it fired, and the 5 -> 2 change that
            // prompted all this cannot be evaluated.
            'minMinutes': gate.minutes,
            'required': gate.required,
            'balance': gate.balance,
            'gap': gate.gap,
            'suggestedAmount': gate.suggestedAmount,
            'earningsBalance': gate.earnings,
            'blockedAt': DateTime.now().toUtc().toIso8601String(),
          },
        ),
      );
      final id = body?['documentId'];
      return id == null ? null : '$id';
    } catch (e) {
      Log.w(_tag, 'block not recorded: $e');
      return null;
    }
  }

  /// Settles what the caller did about it. Skipped when [documentId] is null,
  /// so an unreachable backend never produces an error path here.
  ///
  /// A row left unsettled is a caller who closed the app with the sheet open —
  /// its own answer, and distinct from dismissing the sheet.
  static Future<void> resolve({
    required String? documentId,
    required CallGateOutcome outcome,
  }) async {
    if (documentId == null) return;
    try {
      await ApiClient.patch(
        '/call-gate-blocks/$documentId/outcome',
        data: {'outcome': outcome.wire},
      );
    } catch (e) {
      Log.w(_tag, 'outcome not recorded: $e');
    }
  }
}

/// What the caller did about the gate. Deliberately not [BalanceGateAction]:
/// that enum has no member for "closed it", which is the outcome that matters
/// most here.
enum CallGateOutcome {
  addMoney('add_money'),
  transferEarnings('transfer_earnings'),
  dismissed('dismissed');

  const CallGateOutcome(this.wire);

  /// The backend enum value.
  final String wire;
}
