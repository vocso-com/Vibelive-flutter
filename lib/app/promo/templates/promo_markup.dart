import 'package:flutter/widgets.dart';

import '../../api/promo_banner/promo_content.dart';

/// The admin's colour markup in a title or subtitle (backend
/// `promo-templates.js`, docs/promo_templates.md §2):
/// - `{words}` → the template's accent colour;
/// - `{#RRGGBB|words}` (also #RGB / #AARRGGBB) → that colour; a bad hex
///   falls back to the accent.
///
/// No nesting; an unbalanced `{` or `}` is drawn as typed.
abstract final class PromoMarkup {
  /// The server's pattern (backend promo-templates.js `MARKUP`), as is.
  static final _pattern = RegExp(
    r'\{(?:(#[^{}|]*)\|)?([^{}]*)\}',
    caseSensitive: false,
  );

  /// Plain text and coloured runs, in order. A run's colour is null for
  /// plain text.
  static List<({String text, Color? color})> parse(String text, Color accent) {
    final out = <({String text, Color? color})>[];
    var at = 0;
    for (final m in _pattern.allMatches(text)) {
      if (m.start > at) {
        out.add((text: text.substring(at, m.start), color: null));
      }
      final words = m[2]!;
      final hex = m[1];
      final color = hex == null ? accent : (parsePromoHex(hex) ?? accent);
      if (words.isNotEmpty) out.add((text: words, color: color));
      at = m.end;
    }
    if (at < text.length) out.add((text: text.substring(at), color: null));
    return out;
  }

  /// [text] without markup (screen readers, analytics).
  static String plain(String text) =>
      parse(text, const Color(0x00000000)).map((r) => r.text).join();

  static TextSpan span(String text, Color accent) => TextSpan(
    children: [
      for (final r in parse(text, accent))
        TextSpan(
          text: r.text,
          style: r.color == null ? null : TextStyle(color: r.color),
        ),
    ],
  );
}

/// One line (or a few) of template text: the admin's markup in colour, at a
/// size already scaled by the caller, never scaled again by the phone's
/// font-size setting (the admin preview must stay true).
class PromoText extends StatelessWidget {
  const PromoText(
    this.text, {
    super.key,
    required this.size,
    required this.color,
    required this.accent,
    this.weight = FontWeight.w600,
    this.lineHeight,
    this.maxLines,
    this.align,
    this.letterSpacing,
    this.uppercase = false,
    this.tabular = false,
  });

  final String text;
  final double size;
  final Color color;
  final Color accent;
  final FontWeight weight;

  /// Line height in the same units as [size].
  final double? lineHeight;
  final int? maxLines;
  final TextAlign? align;
  final double? letterSpacing;
  final bool uppercase;
  final bool tabular;

  @override
  Widget build(BuildContext context) {
    final value = uppercase ? text.toUpperCase() : text;
    return Text.rich(
      PromoMarkup.span(value, accent),
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
      textAlign: align,
      textScaler: TextScaler.noScaling,
      style: TextStyle(
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: lineHeight == null ? null : lineHeight! / size,
        letterSpacing: letterSpacing,
        fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
      ),
    );
  }
}
