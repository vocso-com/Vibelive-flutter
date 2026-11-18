import 'dart:async';

import 'package:flutter/widgets.dart';

/// Which Discover cards play their video intro: the ones the user stopped
/// on. Cards with a video register here; when the list comes to rest, every
/// card at least [minVisible] on screen plays (the most central first, at
/// most [maxPlaying]); while it scrolls nothing new starts, and a card that
/// leaves the screen stops at once. One per Discover list.
class CardVideoFocus extends ChangeNotifier {
  CardVideoFocus({this.settleDelay = const Duration(milliseconds: 150)});

  /// At most this many players at once (decoders and data are not free).
  static const maxPlaying = 4;

  /// Share of a card that must be on screen for it to start.
  static const minVisible = 0.6;

  /// Below this share a playing card stops, even mid-scroll.
  static const minKeep = 0.25;

  final Duration settleDelay;

  /// The list's visible area, in global coordinates (null: not laid out).
  Rect? Function()? viewport;

  final _cards = <Object, RenderBox? Function()>{};
  Set<Object> _active = const {};
  bool _scrolling = false;
  bool _disposed = false;
  Timer? _settle;

  bool isActive(Object card) => _active.contains(card);

  @visibleForTesting
  Set<Object> get active => _active;

  /// A card with a video is on the list ([box]: where it is now).
  void register(Object card, RenderBox? Function() box) {
    _cards[card] = box;
    scheduleSettle();
  }

  /// The card left the list (disposed). Quietly: the others are told
  /// nothing now (that would rebuild them mid-teardown); a freed slot is
  /// handed out on the next settle.
  void unregister(Object card) {
    _cards.remove(card);
    if (_active.contains(card)) {
      _active = {..._active}..remove(card);
      scheduleSettle();
    }
  }

  /// The list started moving: nothing new starts until it rests.
  void scrollStarted() {
    _scrolling = true;
    _settle?.cancel();
  }

  /// While it moves: cards that have left the screen stop.
  void scrolled() {
    final view = viewport?.call();
    if (view == null || _active.isEmpty) return;
    final shares = _shares(view);
    final keep = {
      for (final c in _active)
        if ((shares[c] ?? 0) >= minKeep) c,
    };
    if (keep.length != _active.length) _set(keep);
  }

  /// It came to rest (or new cards were laid out): pick the players soon.
  void scrollEnded() {
    _scrolling = false;
    scheduleSettle();
  }

  void scheduleSettle() {
    if (_disposed) return;
    _settle?.cancel();
    _settle = Timer(settleDelay, settle);
  }

  /// Picks the players now (skipped while the list moves).
  void settle() {
    if (_disposed || _scrolling) return;
    final view = viewport?.call();
    if (view == null) return;
    _set(pick(_shares(view), _centres(view), max: maxPlaying));
  }

  /// Nothing plays (the list is gone, or emptied).
  void clear() => _set(const {});

  Map<Object, double> _shares(Rect view) => {
    for (final e in _cards.entries)
      if (_rectOf(e.value) case final r?) e.key: visibleShare(r, view),
  };

  Map<Object, double> _centres(Rect view) => {
    for (final e in _cards.entries)
      if (_rectOf(e.value) case final r?)
        e.key: (r.center - view.center).distance,
  };

  static Rect? _rectOf(RenderBox? Function() box) {
    final b = box();
    if (b == null || !b.attached || !b.hasSize) return null;
    return b.localToGlobal(Offset.zero) & b.size;
  }

  void _set(Set<Object> next) {
    if (_disposed) return;
    if (next.length == _active.length && next.containsAll(_active)) return;
    _active = next;
    notifyListeners();
  }

  /// How much of [card] lies inside [view], 0 to 1.
  static double visibleShare(Rect card, Rect view) {
    if (card.isEmpty) return 0;
    final i = card.intersect(view);
    if (i.width <= 0 || i.height <= 0) return 0;
    return (i.width * i.height) / (card.width * card.height);
  }

  /// The cards to play: at least [minVisible] on screen, the most central
  /// ([centre]: distance to the view's centre) first, at most [max].
  static Set<T> pick<T>(
    Map<T, double> shares,
    Map<T, double> centre, {
    int max = maxPlaying,
  }) {
    final seen = [
      for (final e in shares.entries)
        if (e.value >= minVisible) e.key,
    ]..sort((a, b) => (centre[a] ?? 0).compareTo(centre[b] ?? 0));
    return seen.take(max).toSet();
  }

  @override
  void dispose() {
    _disposed = true;
    _settle?.cancel();
    _cards.clear();
    super.dispose();
  }
}

/// Hands the list's [CardVideoFocus] to its cards.
class CardVideoScope extends InheritedWidget {
  const CardVideoScope({super.key, required this.focus, required super.child});

  final CardVideoFocus focus;

  static CardVideoFocus? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<CardVideoScope>()?.focus;

  @override
  bool updateShouldNotify(CardVideoScope old) => old.focus != focus;
}
