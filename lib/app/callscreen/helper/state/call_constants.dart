/// Every number of the call logic (RN spec §3, plus the architecture
/// decisions 7 and 8). One place, so the windows agree with each other.
abstract final class CallTimings {
  // ── Payload ages (E-13) ───────────────────────────────────────────────
  /// Background VoIP invite (RN `callTtl.ts`).
  static const voipInviteTtl = Duration(seconds: 45);

  /// FCM / notification / deep-link ring payload (RN CallManager), and a
  /// foreground VoIP invite (native keeps a VoIP ring this long, I3).
  static const ringPayloadTtl = Duration(seconds: 120);

  /// Decline API skipped for an older ring (E-15, RN `GHOST_CALL_TTL_MS`).
  static const ghostDeclineTtl = Duration(seconds: 120);

  /// Cold start: an older pending accept / ring is not routed (RN
  /// RootLayout).
  static const coldStartTtl = Duration(minutes: 5);

  /// Cold-start "is it still open on the server" check, raced (E-16).
  static const statusCheckTimeout = Duration(seconds: 2);

  // ── Dedup windows ─────────────────────────────────────────────────────
  /// Ended in memory (RN SystemIncomingCall, E-18).
  static const endedMemory = Duration(seconds: 30);

  /// Ringing / ended signal repeats (E-3).
  static const signalDedup = Duration(seconds: 4);

  /// Same FCM message (E-2).
  static const claimTtl = Duration(seconds: 15);

  /// Handled VoIP call ids kept (E-4, RN `@vibe_handled_calls`).
  static const handledVoipIds = 20;

  // ── Presentation ──────────────────────────────────────────────────────
  /// Foreground incoming screen: keep presenting for this long (mem #1).
  static const foregroundHold = Duration(seconds: 2);

  /// …retrying the router this often while it is not ready (E-59).
  static const foregroundRetry = Duration(milliseconds: 250);

  /// Pending navigation slot: replay attempts, then give up.
  static const navigationRetry = Duration(milliseconds: 250);
  static const navigationGiveUp = Duration(seconds: 30);

  /// Leaving a cold-start call: the post-auth route lookup, at most.
  static const authRouteWait = Duration(seconds: 3);

  /// Caller exit: re-open the host profile once Home is back (iOS cannot
  /// stack a sheet on a page that is being removed).
  static const reopenProfileDelay = Duration(milliseconds: 350);

  // ── Screen rules (the UI uses these too) ──────────────────────────────
  static const declineGuard = Duration(milliseconds: 2500);
  static const hangupGuard = Duration(milliseconds: 2500);
  static const incomingBootstrapped = Duration(milliseconds: 600);
  static const postEndExit = Duration(milliseconds: 1200);
  static const feedbackDelay = Duration(milliseconds: 300);

  /// Caller: remote joined Agora → connected after this (RN C8).
  static const callerConnectDelay = Duration(milliseconds: 500);

  // ── Agora (§4) ────────────────────────────────────────────────────────
  /// Engine released this long after the call is over.
  static const engineReleaseGrace = Duration(milliseconds: 1000);

  /// A join right after init waits [coldBootSettle] (E-55).
  static const coldBootWindow = Duration(milliseconds: 1000);
  static const coldBootSettle = Duration(milliseconds: 300);

  /// -17 "already joining": leave, wait, rejoin once (E-53).
  static const minus17Settle = Duration(milliseconds: 300);

  /// iOS: after leaving another channel (E-57).
  static const iosRejoinSettle = Duration(milliseconds: 150);

  /// Local view remount after a camera flip.
  static const cameraFlipRemount = Duration(milliseconds: 100);

  /// iOS headless join: CallKit's audio session, else join anyway.
  static const audioSessionFallback = Duration(seconds: 3);

  // ── Timers RN lacked (decision 7) ─────────────────────────────────────
  /// Caller: nobody answered → normal hang-up (cancel).
  static const noAnswer = Duration(seconds: 60);

  /// Receiver: in-app ring with no end push → local dismiss, no API.
  static const incomingRing = Duration(seconds: 60);

  /// Remote dropped (Agora offline reason 1) → hang-up unless back.
  static const remoteDropGrace = Duration(seconds: 30);

  /// Agora RECONNECTING for longer → hang-up.
  static const reconnecting = Duration(seconds: 30);

  /// `CALL_ENDED` for an ongoing call: Agora's remote quit normally ends it
  /// (E-47). A server-side end (low balance, admin) leaves both sides in
  /// the channel, so after this the call ends locally (no API).
  static const endedPushGrace = Duration(seconds: 3);

  // ── Billing (decision 8, spec §9.5) ───────────────────────────────────
  /// Agora token lifetime (3600 s from initiate, no renew route).
  static const tokenLifetime = Duration(seconds: 3600);

  /// End this much before the next unaffordable minute is billed. The
  /// server bills from the receiver's `/UpdateCall`, up to a few seconds
  /// before the caller's local connect, and hears of the end a moment after
  /// the hang-up: 20 s covers both (A3).
  static const maxDurationMargin = Duration(seconds: 20);

  // ── Native recovery ───────────────────────────────────────────────────
  /// Waits between the Dart `/UpdateCall` retries after native's failed
  /// (I1): 3 attempts in all.
  static const updateRetry = [Duration(seconds: 2), Duration(seconds: 5)];

  /// Sign-out waits at most this long for the Callend to go out (U3).
  static const signOutEndWait = Duration(seconds: 4);

  /// Low-balance toast this long before the end (server warns at 300 s).
  static const lowBalanceWarning = Duration(minutes: 5);

  /// A free call that stops at its free limit ends this much before it by
  /// our clock (docs/free_calls.md): the server's clock started a moment
  /// earlier, and it counts a further 15 s past the limit as free.
  static const freeEndMargin = Duration(seconds: 5);

  /// "Free call ends soon" this long before a free call's end.
  static const freeEndWarning = Duration(seconds: 30);
}

/// Fixed request values copied from RN.
abstract final class CallWire {
  /// RN `mapExpert` never had a category, so every profile call sent this
  /// fallback `categoryId` (the backend ignores it, E-84).
  static const profileCategoryId = 'dcybx2ez5hjaqshrfpqg39on';

  static const reportedDuringCall = 'Reported during a live call.';
  static const blockedDuringCall = 'Blocked during a live call.';
  static const reportedIncoming = 'Reported from an incoming call.';
  static const blockedIncoming = 'Blocked from an incoming call.';
}
