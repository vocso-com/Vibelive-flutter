import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../../core/network/strapi.dart';

/// Promo banners as the app reads them (`GET /app-banners?placement=`).
///
/// The server has already decided what this viewer sees (master switch,
/// published, not hidden, inside its schedule, audience); these only describe
/// what arrived. Every field has a safe fallback, so a half-filled banner still
/// draws instead of throwing.
enum PromoPlacement { home, wallet }

enum PromoLayout {
  imageBackground('image_background'),
  imageOnly('image_only'),
  imageLeft('image_left'),
  imageRight('image_right'),
  textOnly('text_only');

  const PromoLayout(this.wire);
  final String wire;

  static PromoLayout parse(Object? v) => values.firstWhere(
    (l) => l.wire == v,
    orElse: () => PromoLayout.imageBackground,
  );

  bool get hasImage => this != textOnly;
}

enum PromoHeight {
  small(96),
  medium(132),
  large(172);

  const PromoHeight(this.dp);

  /// At a 340-wide content area; the card scales with the screen.
  final double dp;

  static PromoHeight parse(Object? v) =>
      values.firstWhere((h) => h.name == v, orElse: () => PromoHeight.medium);
}

/// An animation over a banner (admin: Effect). The admin preview plays the
/// same six (BannerPreview.jsx).
enum PromoEffect {
  none,
  sparkle,
  stars,
  confetti,
  gift,
  shine,
  hearts;

  static PromoEffect parse(Object? v) =>
      values.firstWhere((e) => e.name == v, orElse: () => PromoEffect.none);
}

/// What a tap does. [path] / [link]: an app screen (the app puts its own link
/// scheme in front of a path); [url]: a web page, in the app or the browser.
@immutable
class PromoAction {
  const PromoAction._(
    this.type, {
    this.path,
    this.link,
    this.url,
    this.inApp = false,
  });

  static const none = PromoAction._('none');

  factory PromoAction.fromJson(Object? json) {
    if (json is! Map) return none;
    final type = J.str(json['type']);
    if (type == 'app') {
      final path = J.str(json['path']);
      final link = J.str(json['link']);
      if (path == null && link == null) return none;
      return PromoAction._('app', path: path, link: link);
    }
    if (type == 'url') {
      final url = J.str(json['url']);
      final uri = url == null ? null : Uri.tryParse(url);
      if (uri == null || !uri.hasScheme || !uri.scheme.startsWith('http')) {
        return none;
      }
      return PromoAction._('url', url: url, inApp: json['openIn'] == 'app');
    }
    return none;
  }

  final String type;
  final String? path;
  final String? link;
  final String? url;

  /// A web page opens inside the app rather than in the browser.
  final bool inApp;

  bool get isNone => type == 'none';
  bool get isApp => type == 'app';
  bool get isUrl => type == 'url';

  /// The app link to open: the full link as given, else [scheme]`://`[path].
  String? appLink(String scheme) {
    if (link != null) return link;
    final p = path?.replaceFirst(RegExp(r'^/+'), '');
    return p == null || p.isEmpty ? null : '$scheme://$p';
  }
}

@immutable
class PromoBanner {
  const PromoBanner({
    required this.id,
    this.title = '',
    this.subtitle = '',
    this.ctaLabel = '',
    this.imageUrl,
    this.layout = PromoLayout.imageBackground,
    this.background = const Color(0xFF7C3AED),
    this.backgroundEnd,
    this.text = const Color(0xFFFFFFFF),
    this.ctaBackground = const Color(0xFFFFFFFF),
    this.ctaText = const Color(0xFF111827),
    this.centered = false,
    this.height = PromoHeight.medium,
    this.cornerRadius = 16,
    this.overlayOpacity = 35,
    this.action = PromoAction.none,
    this.dismissible = false,
    this.effect = PromoEffect.none,
    this.effectColor = const Color(0xFFFFD54F),
  });

  /// Null for a row with no id, or one that cannot draw (an image layout
  /// with no image, a text layout with no title).
  static PromoBanner? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = J.str(json['id']);
    if (id == null) return null;
    final colors = json['colors'] is Map ? json['colors'] as Map : const {};
    final effect = json['effect'] is Map ? json['effect'] as Map : const {};
    final layout = PromoLayout.parse(json['layout']);
    final image = Strapi.mediaUrl(J.str(json['image']));
    final title = J.str(json['title']) ?? '';
    if (layout.hasImage && image == null) return null;
    if (!layout.hasImage && title.isEmpty) return null;
    return PromoBanner(
      id: id,
      title: title,
      subtitle: J.str(json['subtitle']) ?? '',
      ctaLabel: J.str(json['ctaLabel']) ?? '',
      imageUrl: image,
      layout: layout,
      background: parseHex(colors['background']) ?? const Color(0xFF7C3AED),
      backgroundEnd: parseHex(colors['backgroundEnd']),
      text: parseHex(colors['text']) ?? const Color(0xFFFFFFFF),
      ctaBackground:
          parseHex(colors['ctaBackground']) ?? const Color(0xFFFFFFFF),
      ctaText: parseHex(colors['ctaText']) ?? const Color(0xFF111827),
      centered: json['textAlign'] == 'center',
      height: PromoHeight.parse(json['height']),
      cornerRadius: (J.number(json['cornerRadius']) ?? 16)
          .clamp(0, 40)
          .toDouble(),
      overlayOpacity: (J.number(json['overlayOpacity']) ?? 35)
          .clamp(0, 90)
          .toDouble(),
      action: PromoAction.fromJson(json['action']),
      dismissible: json['dismissible'] == true,
      effect: PromoEffect.parse(effect['type']),
      effectColor: parseHex(effect['color']) ?? const Color(0xFFFFD54F),
    );
  }

  /// `#RGB`, `#RRGGBB` or `#AARRGGBB` (the admin's colour fields).
  static Color? parseHex(Object? v) {
    final s = J.str(v)?.replaceFirst('#', '');
    if (s == null || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(s)) return null;
    final full = switch (s.length) {
      3 => 'FF${s.split('').map((c) => '$c$c').join()}',
      6 => 'FF$s',
      8 => s,
      _ => null,
    };
    return full == null ? null : Color(int.parse(full, radix: 16));
  }

  final String id;
  final String title;
  final String subtitle;
  final String ctaLabel;
  final String? imageUrl;
  final PromoLayout layout;
  final Color background;
  final Color? backgroundEnd;
  final Color text;
  final Color ctaBackground;
  final Color ctaText;
  final bool centered;
  final PromoHeight height;
  final double cornerRadius;

  /// 0–90: darkening over a background image, so the text stays readable.
  final double overlayOpacity;
  final PromoAction action;
  final bool dismissible;
  final PromoEffect effect;

  /// The effect's particles (confetti mixes it with its own colours).
  final Color effectColor;

  bool get hasText =>
      title.isNotEmpty || subtitle.isNotEmpty || ctaLabel.isNotEmpty;
}

/// One placement's banners, and how fast they rotate.
@immutable
class PromoBannerFeed {
  const PromoBannerFeed({
    this.banners = const [],
    this.rotateSeconds = 5,
    this.raw = const {},
  });

  static const empty = PromoBannerFeed();

  factory PromoBannerFeed.fromJson(Object? body) {
    if (body is! Map || body['enabled'] != true) return empty;
    final rows = body['banners'];
    return PromoBannerFeed(
      banners: [
        if (rows is List)
          for (final row in rows) ?PromoBanner.fromJson(row),
      ],
      rotateSeconds: (J.integer(body['rotateSeconds']) ?? 5).clamp(0, 30),
      raw: Map<String, dynamic>.from(body),
    );
  }

  /// The server's answer as it came, for the disk copy (shown at once on the
  /// next launch while the network refetches).
  final Map<String, dynamic> raw;
  Map<String, dynamic> toJson() => raw;

  final List<PromoBanner> banners;

  /// 0: no auto-slide.
  final int rotateSeconds;
}
