import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/storage/app_prefs.dart';
import '../../../core/utils/scale.dart';
import '../../component/c_loader.dart';
import '../../component/c_state_view.dart';
import '../components/message_bubble.dart';
import '../components/vanish_mode.dart';
import '../helper/chat_room_controller.dart';
import '../helper/chat_rows.dart';

/// The messages: a reversed lazy list (newest at the bottom), older pages
/// loading as the top comes near.
///
/// Rows are derived when the messages change, not in build, and a row that
/// draws the same as before gets back the very same widget instance, so a
/// new message builds one bubble (plus the one that lost its tail), not
/// every bubble on screen. Keys are stable from "sending" to "sent", and
/// the list finds a moved row by key, so a bubble keeps its state.
class ChatMessageList extends StatefulWidget {
  const ChatMessageList({
    super.key,
    required this.controller,
    required this.actions,
    required this.me,
    this.onVanishSwitch,
  });

  final ChatRoomController controller;
  final ChatBubbleActions actions;
  final String? me;

  /// Pulling the conversation up past its newest message and letting go
  /// switches vanish mode (Instagram's gesture). Null: no gesture.
  final VoidCallback? onVanishSwitch;

  /// Tests switch the first-time vanish tip off where it is not the subject.
  @visibleForTesting
  static bool vanishTipEnabled = true;

  /// Where "this person has seen the vanish tip" is kept (per signed-in user):
  /// how many times it played, or [_tipUsed] once they used vanish mode.
  static String vanishTipKey(String? userId) =>
      'chat_vanish_tip_seen:${userId ?? '?'}';

  /// The tip plays on at most this many chat visits.
  static const vanishTipTimes = 2;
  static const _tipUsed = 'used';

  /// They switched vanish mode themselves: the tip has done its job.
  static void markVanishTipUsed(String? userId) =>
      unawaited(AppPrefs.setString(vanishTipKey(userId), _tipUsed));

  @override
  State<ChatMessageList> createState() => _ChatMessageListState();
}

class _ChatMessageListState extends State<ChatMessageList>
    with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();

  /// The first-time tip: for three seconds the chat peeks up a little and the
  /// ring half fills with "Swipe up to turn on vanish mode", then settles.
  /// Once per person; a touch ends it at once.
  late final AnimationController _tip;
  Timer? _tipDelay;
  bool _tipDone = false;
  late final _pull = VanishPull(onRelease: () => widget.onVanishSwitch?.call());
  final _widgets = <String, (ChatRow, Widget)>{};
  var _rows = const <ChatRow>[];
  var _index = const <String, int>{};

  ChatRoomController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.messages.addListener(_onMessages);
    _c.hasMore.addListener(_onMore);
    _c.vanish.addListener(_onMore);
    _tip = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..addListener(_onTip);
    _tip.addStatusListener((status) {
      if (status == AnimationStatus.completed) _endTip();
    });
    _derive();
  }

  @override
  void dispose() {
    _c.messages.removeListener(_onMessages);
    _c.hasMore.removeListener(_onMore);
    _c.vanish.removeListener(_onMore);
    _tipDelay?.cancel();
    _tip.dispose();
    _scroll.dispose();
    _pull.dispose();
    super.dispose();
  }

  // ── the first-time vanish tip ───────────────────────────────────────────

  /// 0 → 1 → 0 over the tip: up in the first fifth, held, down in the last.
  static double _tipShape(double t) {
    if (t < 0.2) return Curves.easeOutCubic.transform(t / 0.2);
    if (t < 0.75) return 1;
    return 1 - Curves.easeInCubic.transform((t - 0.75) / 0.25);
  }

  double get _tipLift => _tip.isAnimating ? _tipShape(_tip.value) * 26.ms : 0;

  void _onTip() {
    if (!_tip.isAnimating) return;
    // The ring about three quarters full: "Swipe up…", never "Release…".
    _pull.pull.value = _tipShape(_tip.value) * kVanishPullThreshold * 0.74;
    setState(() {});
  }

  /// Plays the tip once the chat has settled, if this person never saw it.
  void _maybeTip() {
    if (_tipDone || _tipDelay != null || !ChatMessageList.vanishTipEnabled) {
      return;
    }
    if (widget.onVanishSwitch == null || _c.vanish.value.on) return;
    if (_c.conversationId == null || _rows.isEmpty) return;
    final key = ChatMessageList.vanishTipKey(_c.me);
    final saved = AppPrefs.getString(key);
    final shown = int.tryParse(saved ?? '0') ?? ChatMessageList.vanishTipTimes;
    if (saved == ChatMessageList._tipUsed ||
        shown >= ChatMessageList.vanishTipTimes) {
      _tipDone = true;
      return;
    }
    _tipDelay = Timer(const Duration(milliseconds: 900), () {
      if (!mounted || _tipDone || _c.vanish.value.on) return;
      unawaited(AppPrefs.setString(key, '${shown + 1}'));
      unawaited(_tip.forward(from: 0));
    });
  }

  void _endTip() {
    _tipDone = true;
    _tipDelay?.cancel();
    if (_tip.isAnimating) _tip.stop();
    _pull.pull.value = 0;
    if (mounted) setState(() {});
  }

  void _onMessages() => setState(_derive);

  void _onMore() => setState(() {});

  void _derive() {
    _rows = ChatRows.build(_c.messages.value, widget.me);
    _index = {for (var i = 0; i < _rows.length; i++) _rows[i].key: i};
    _widgets.removeWhere((key, _) => !_index.containsKey(key));
  }

  Widget _row(ChatRow row) {
    final cached = _widgets[row.key];
    if (cached != null && cached.$1 == row) return cached.$2;
    final w = RepaintBoundary(
      key: ValueKey(row.key),
      child: ChatMessageRow(
        row: row,
        receipts: _c.receipts,
        actions: widget.actions,
      ),
    );
    _widgets[row.key] = (row, w);
    return w;
  }

  bool _onScroll(ScrollNotification n) {
    // A touch ends the tip at once (they found the list themselves).
    if (n is ScrollStartNotification &&
        n.dragDetails != null &&
        _tip.isAnimating) {
      _endTip();
    }
    // Reversed: "after" is towards the top, the older messages.
    if (n.metrics.extentAfter < 600) _c.loadOlder();
    if (widget.onVanishSwitch != null) _pull.onNotification(n);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final vanish = _c.vanish.value;
    final more = _c.hasMore.value && !vanish.on;
    final peerName = _c.open.value?.peer.name ?? '';
    // Always scrollable, so even a short (or empty) chat can be pulled; a
    // rubber band where the vanish gesture exists, so the pull follows the
    // finger as on Instagram.
    final physics = widget.onVanishSwitch == null
        ? const AlwaysScrollableScrollPhysics()
        : const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics());
    final notice = vanish.on
        ? VanishNotice(info: vanish, peerName: peerName)
        : null;

    final Widget list;
    if (rows.isEmpty) {
      // Nothing yet: one screen-high page with the hint (or the vanish
      // notice) in its middle. It scrolls when there is no room, so a small
      // phone with the keyboard up never overflows.
      list = LayoutBuilder(
        builder: (context, box) => ListView(
          key: const ValueKey('chat-message-list'),
          controller: _scroll,
          reverse: true,
          physics: physics,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: Center(child: notice ?? const _SayHi()),
            ),
          ],
        ),
      );
    } else {
      final extra = (more ? 1 : 0) + (notice != null ? 1 : 0);
      list = ListView.builder(
        key: const ValueKey('chat-message-list'),
        controller: _scroll,
        reverse: true,
        physics: physics,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.only(top: 8.ms, bottom: 10.ms),
        itemCount: rows.length + extra,
        findChildIndexCallback: (key) =>
            key is ValueKey<String> ? _index[key.value] : null,
        itemBuilder: (_, i) {
          if (i < rows.length) return _row(rows[i]);
          // Above the oldest: the vanish notice (top of the conversation),
          // or the older page loading.
          if (notice != null) return notice;
          return const _OlderLoading(key: ValueKey('chat-older'));
        },
      );
    }

    if (!_tipDone) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeTip());
    }
    final lift = _tipLift;
    return Stack(
      children: [
        Positioned.fill(
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            // Always the same tree (offset 0 when idle), so the list is never
            // rebuilt when the tip starts or ends.
            child: Transform.translate(offset: Offset(0, -lift), child: list),
          ),
        ),
        if (widget.onVanishSwitch != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: VanishPullIndicator(
              pull: _pull.pull,
              on: vanish.on,
              tip: _tip.isAnimating,
            ),
          ),
      ],
    );
  }
}

class _OlderLoading extends StatelessWidget {
  const _OlderLoading({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(vertical: 14.ms),
    child: const Center(child: RepaintBoundary(child: CLoader(size: 22))),
  );
}

/// No message yet.
class _SayHi extends StatelessWidget {
  const _SayHi();

  @override
  Widget build(BuildContext context) => const CStateView(
    title: 'chat:say_hi.title',
    message: 'chat:say_hi.message',
    icon: LucideIcons.messageCircle,
  );
}
