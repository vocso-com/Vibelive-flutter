import 'package:flutter/material.dart';

/// The camera's own look: dark, with the app's accent. Every screen and
/// dialog of the camera is wrapped in it, so an app's theme (light chips,
/// dark text, custom buttons) can never hide a control on the black camera.
abstract final class VibeTheme {
  static ThemeData of(Color accent) {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
    ).copyWith(
      primary: accent,
      onPrimary: Colors.white,
      secondary: accent,
      surface: const Color(0xFF1C1C1E),
      onSurface: Colors.white,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.black,
      canvasColor: Colors.black,
      dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF1C1C1E)),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: Colors.white),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.white12,
          disabledForegroundColor: Colors.white38,
          shape: const StadiumBorder(),
        ),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 3,
        activeTrackColor: accent,
        inactiveTrackColor: Colors.white24,
        thumbColor: Colors.white,
        overlayShape: SliderComponentShape.noOverlay,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Color(0xFF2C2C2E),
        contentTextStyle: TextStyle(color: Colors.white),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: accent,
        selectionColor: accent.withValues(alpha: 0.35),
        selectionHandleColor: accent,
      ),
    );
  }

  /// [child] in the camera's look.
  static Widget wrap(Color accent, Widget child) =>
      Theme(data: of(accent), child: child);
}
