import 'package:flutter/widgets.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';

/// The chat's colours and sizes, read once per build (`ChatPalette.of`).
/// Mine: the accent (lime in dark, purple in light); theirs: a quiet card.
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
