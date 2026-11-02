import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../../core/network/strapi.dart';
import 'promo_content.dart';

export 'promo_content.dart';

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

/// The admin's banner templates (backend `src/utils/promo-templates.js`).
/// `custom` and keys this build does not know draw with the legacy look
/// fields ([PromoLayout], height, corners…): forward compatible.
enum PromoBannerTemplate {
  spotlight('spotlight'),
  offer('offer'),
  fullImage('full_image'),
  glass('glass'),
  minimal('minimal'),
  countdown('countdown');

  const PromoBannerTemplate(this.wire);
  final String wire;

  /// Null: `custom`, or a template this build does not know.
  static PromoBannerTemplate? parse(Object? v) {
    for (final t in values) {
      if (t.wire == v) return t;
    }
    return null;
  }

  /// Height at a 340-wide card (spec section 3).
  double get baseHeight => switch (this) {
    spotlight => 160,
    offer => 150,
    fullImage => 170,
    glass => 160,
    minimal => 92,
    countdown => 150,
  };

  /// Whether [c] has what this template needs to draw.
  bool canShow(PromoContent c, DateTime now) => switch (this) {
    spotlight || glass => c.hasImage && c.title.isNotEmpty,
    fullImage => c.hasImage,
    offer => c.title.isNotEmpty && c.offerValue.isNotEmpty,
    minimal => c.title.isNotEmpty,
    countdown => c.title.isNotEmpty && !c.endedAt(now),
  };
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
    this.template,
    this.content = const PromoContent(),
  });

  /// Null for a row with no id, or one that cannot draw (a template missing
  /// what it needs, an ended countdown; legacy: an image layout with no
  /// image, a text layout with no title).
  static PromoBanner? fromJson(Object? json, {DateTime? now}) {
    if (json is! Map) return null;
    final id = J.str(json['id']);
    if (id == null) return null;
    final colors = json['colors'] is Map ? json['colors'] as Map : const {};
    final effect = json['effect'] is Map ? json['effect'] as Map : const {};
    final layout = PromoLayout.parse(json['layout']);
    final image = Strapi.mediaUrl(J.str(json['image']));
    final title = J.str(json['title']) ?? '';
    final template = PromoBannerTemplate.parse(json['template']);
    final content = PromoContent.fromJson(json);
    if (template != null) {
      if (!template.canShow(content, now ?? DateTime.now())) return null;
    } else {
      if (layout.hasImage && image == null) return null;
      if (!layout.hasImage && title.isEmpty) return null;
    }
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
      template: template,
      content: content,
    );
  }

  /// `#RGB`, `#RRGGBB` or `#AARRGGBB` (the admin's colour fields).
  static Color? parseHex(Object? v) => parsePromoHex(v);

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

  /// The admin's template; null = the legacy look ([layout] and friends).
  final PromoBannerTemplate? template;

  /// Everything a template draws (rich title, badge, offer, icons, colours).
  final PromoContent content;
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

  factory PromoBannerFeed.fromJson(Object? body, {DateTime? now}) {
    if (body is! Map || body['enabled'] != true) return empty;
    final rows = body['banners'];
    return PromoBannerFeed(
      banners: [
        if (rows is List)
          for (final row in rows) ?PromoBanner.fromJson(row, now: now),
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
