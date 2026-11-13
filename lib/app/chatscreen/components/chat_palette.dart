import 'package:flutter/widgets.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';

/// How far the chat is into vanish mode's look: 0 normal, 1 vanish. Animated
/// by the chat screen, so every part of the chat (header, bubbles, composer)
/// fades into the dark room together, like Instagram's.
class ChatVanishScope extends InheritedWidget {
  const ChatVanishScope({super.key, required this.t, required super.child});

  final double t;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ChatVanishScope>()?.t ?? 0;

  @override
  bool updateShouldNotify(ChatVanishScope old) => old.t != t;
}

/// The chat's colours and sizes, read once per build (`ChatPalette.of`).
/// Mine: the accent (lime in dark, purple in light); theirs: a quiet card.
/// Inside a [ChatVanishScope] they blend into vanish mode's own palette —
/// the same in light and dark theme, so vanish mode always looks different.
@immutable
class ChatPalette {
  const ChatPalette._({
    required this.dark,
    required this.screen,
    required this.mine,
    required this.onMine,
    required this.mineMeta,
    required this.theirs,
    required this.onTheirs,
    required this.theirsMeta,
    required this.theirsBorder,
    required this.read,
    required this.failed,
    required this.chip,
    required this.onChip,
    required this.bar,
    required this.barBorder,
    required this.field,
    required this.muted,
    required this.accent,
    required this.onAccent,
    required this.text,
  });

  factory ChatPalette.of(BuildContext context) {
    final base = ChatPalette._base(context);
    final t = ChatVanishScope.of(context);
    if (t <= 0) return base;
    return t >= 1 ? vanish : lerp(base, vanish, t);
  }

  /// Vanish mode: a near-black room, violet for my messages.
  static const vanish = ChatPalette._(
    dark: true,
    screen: Color(0xFF000000),
    mine: Color(0xFF7C3AED),
    onMine: Color(0xFFFFFFFF),
    mineMeta: Color(0xA6FFFFFF),
    theirs: Color(0xFF1C1B22),
    onTheirs: Color(0xFFF2F2F7),
    theirsMeta: Color(0x73FFFFFF),
    theirsBorder: Color(0x0FFFFFFF),
    read: Color(0xFFC4B5FD),
    failed: StatusColors.dangerRed,
    chip: Color(0x14FFFFFF),
    onChip: Color(0xB3FFFFFF),
    bar: Color(0xFF0B0A10),
    barBorder: Color(0x14FFFFFF),
    field: Color(0x17FFFFFF),
    muted: Color(0x80FFFFFF),
    accent: Color(0xFF8B5CF6),
    onAccent: Color(0xFFFFFFFF),
    text: Color(0xFFF2F2F7),
  );

  static ChatPalette lerp(ChatPalette a, ChatPalette b, double t) {
    Color c(Color x, Color y) => Color.lerp(x, y, t)!;
    return ChatPalette._(
      dark: t < 0.5 ? a.dark : b.dark,
      screen: c(a.screen, b.screen),
      mine: c(a.mine, b.mine),
      onMine: c(a.onMine, b.onMine),
      mineMeta: c(a.mineMeta, b.mineMeta),
      theirs: c(a.theirs, b.theirs),
      onTheirs: c(a.onTheirs, b.onTheirs),
      theirsMeta: c(a.theirsMeta, b.theirsMeta),
      theirsBorder: c(a.theirsBorder, b.theirsBorder),
      read: c(a.read, b.read),
      failed: c(a.failed, b.failed),
      chip: c(a.chip, b.chip),
      onChip: c(a.onChip, b.onChip),
      bar: c(a.bar, b.bar),
      barBorder: c(a.barBorder, b.barBorder),
      field: c(a.field, b.field),
      muted: c(a.muted, b.muted),
      accent: c(a.accent, b.accent),
      onAccent: c(a.onAccent, b.onAccent),
      text: c(a.text, b.text),
    );
  }

  factory ChatPalette._base(BuildContext context) {
    final c = context.colors;
    final dark = c.isDark;
    return ChatPalette._(
      dark: dark,
      screen: dark ? AppColors.black : LightColors.background,
      mine: c.accent,
      onMine: c.onAccent,
      mineMeta: c.onAccent.withValues(alpha: 0.62),
      theirs: dark ? DarkColors.surfaceSolid : AppColors.white,
      onTheirs: c.text,
      theirsMeta: dark ? AppColors.whiteA(0.45) : AppColors.blackA(0.42),
      theirsBorder: dark ? AppColors.whiteA(0.06) : AppColors.blackA(0.06),
      // Read ticks: visible on both accents (lime / purple).
      read: dark ? const Color(0xFF1D4ED8) : const Color(0xFF7DD3FC),
      failed: StatusColors.dangerRed,
      chip: dark ? AppColors.whiteA(0.08) : AppColors.blackA(0.05),
      onChip: dark ? AppColors.whiteA(0.7) : AppColors.blackA(0.55),
      bar: dark ? DarkColors.navBg : AppColors.white,
      barBorder: dark ? AppColors.whiteA(0.08) : AppColors.blackA(0.07),
      field: dark ? AppColors.whiteA(0.06) : AppColors.slate100,
      muted: dark ? AppColors.whiteA(0.5) : AppColors.blackA(0.45),
      accent: c.accent,
      onAccent: c.onAccent,
      text: c.text,
    );
  }

  final bool dark;
  final Color screen;
  final Color mine;
  final Color onMine;
  final Color mineMeta;
  final Color theirs;
  final Color onTheirs;
  final Color theirsMeta;
  final Color theirsBorder;
  final Color read;
  final Color failed;
  final Color chip;
  final Color onChip;

  /// Header and composer background.
  final Color bar;
  final Color barBorder;
  final Color field;
  final Color muted;
  final Color accent;
  final Color onAccent;
  final Color text;

  /// Widest a bubble may be: most of a phone, capped on a tablet.
  static double bubbleMax(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final cap = 520.ms;
    final phone = w * 0.78;
    return phone < cap ? phone : cap;
  }

  /// The phone's text size for message text, capped so a bubble and the
  /// composer still fit (the rest of the app draws at a fixed size).
  static TextScaler textScaler(BuildContext context) =>
      MediaQuery.textScalerOf(context).clamp(maxScaleFactor: maxTextScale);

  static const maxTextScale = 1.3;

  static double get radius => 18.ms;
  static double get tail => 6.ms;
}
