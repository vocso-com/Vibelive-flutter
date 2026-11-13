import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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

  @override
  State<ChatMessageList> createState() => _ChatMessageListState();
}

class _ChatMessageListState extends State<ChatMessageList> {
  final _scroll = ScrollController();
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
    _derive();
  }

  @override
  void dispose() {
    _c.messages.removeListener(_onMessages);
    _c.hasMore.removeListener(_onMore);
    _c.vanish.removeListener(_onMore);
    _scroll.dispose();
    _pull.dispose();
    super.dispose();
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

    return Stack(
      children: [
        Positioned.fill(
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: list,
          ),
        ),
        if (widget.onVanishSwitch != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: VanishPullIndicator(pull: _pull.pull, on: vanish.on),
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
