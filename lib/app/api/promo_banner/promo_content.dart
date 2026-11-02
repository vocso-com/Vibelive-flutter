import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../../core/network/strapi.dart';

/// A tap's destination (`action` of a banner or a popup). [path] / [link]:
/// an app screen (the app puts its own link scheme in front of a path);
/// [url]: a web page, in the app or the browser.
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

/// An animation over a banner or popup (admin: Effect). The admin preview
/// plays the same six (BannerPreview.jsx).
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

/// Where a cropped image keeps its middle: `top` keeps a face.
enum PromoImageFocus {
  top(Alignment(0, -0.7)),
  center(Alignment.center),
  bottom(Alignment(0, 0.7));

  const PromoImageFocus(this.alignment);
  final Alignment alignment;

  static PromoImageFocus parse(Object? v) => values.firstWhere(
    (f) => f.name == v,
    orElse: () => PromoImageFocus.center,
  );
}

/// `#RGB`, `#RRGGBB` or `#AARRGGBB` (the admin's colour fields).
Color? parsePromoHex(Object? v) {
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

/// The six colours of a template (`colors` in the API).
@immutable
class PromoPalette {
  const PromoPalette({
    this.background = const Color(0xFF7C3AED),
    this.backgroundEnd,
    this.text = const Color(0xFFFFFFFF),
    this.accent = const Color(0xFFFFD54F),
    this.ctaBackground = const Color(0xFFFFFFFF),
    this.ctaText = const Color(0xFF111827),
  });

  factory PromoPalette.fromJson(Object? json) {
    final c = json is Map ? json : const {};
    return PromoPalette(
      background: parsePromoHex(c['background']) ?? const Color(0xFF7C3AED),
      backgroundEnd: parsePromoHex(c['backgroundEnd']),
      text: parsePromoHex(c['text']) ?? const Color(0xFFFFFFFF),
      accent: parsePromoHex(c['accent']) ?? const Color(0xFFFFD54F),
      ctaBackground:
          parsePromoHex(c['ctaBackground']) ?? const Color(0xFFFFFFFF),
      ctaText: parsePromoHex(c['ctaText']) ?? const Color(0xFF111827),
    );
  }

  final Color background;

  /// Gradient end; null = a flat background.
  final Color? backgroundEnd;
  final Color text;

  /// Highlight colour: `{markup}`, offer values, badges, rings.
  final Color accent;
  final Color ctaBackground;
  final Color ctaText;

  Color get end => backgroundEnd ?? background;

  /// The colour a fading image melts into (half-way along the gradient).
  Color get fade => Color.lerp(background, end, 0.5)!;

  List<Color> get gradient => [background, end];
}

/// What the admin filled into a template, shared by banners and popups
/// (docs: backend docs/promo_templates.md). Text is ready to draw: [title] /
/// [subtitle] keep the colour markup (`{words}`) when the server sent it.
@immutable
class PromoContent {
  const PromoContent({
    this.template = '',
    this.badge = '',
    this.title = '',
    this.subtitle = '',
    this.offerValue = '',
    this.offerCaption = '',
    this.couponCode = '',
    this.ctaLabel = '',
    this.ctaIcon = 'arrow_right',
    this.icon = 'sparkles',
    this.imageUrl,
    this.imageFocus = PromoImageFocus.center,
    this.imageLeft = false,
    this.palette = const PromoPalette(),
    this.effect = PromoEffect.none,
    this.effectColor = const Color(0xFFFFD54F),
    this.action = PromoAction.none,
    this.endsAt,
  });

  factory PromoContent.fromJson(Map<dynamic, dynamic> json) {
    String text(String key) => J.str(json[key])?.trim() ?? '';
    final effect = json['effect'] is Map ? json['effect'] as Map : const {};
    final ends = J.str(json['endsAt']);
    return PromoContent(
      template: text('template'),
      badge: text('badge'),
      title: J.str(json['titleRich'])?.trim() ?? text('title'),
      subtitle: J.str(json['subtitleRich'])?.trim() ?? text('subtitle'),
      offerValue: text('offerValue'),
      offerCaption: text('offerCaption'),
      couponCode: text('couponCode'),
      ctaLabel: text('ctaLabel'),
      ctaIcon: J.str(json['ctaIcon']) ?? 'arrow_right',
      icon: J.str(json['icon']) ?? 'sparkles',
      imageUrl: Strapi.mediaUrl(J.str(json['image'])),
      imageFocus: PromoImageFocus.parse(json['imageFocus']),
      imageLeft: json['imageSide'] == 'left',
      palette: PromoPalette.fromJson(json['colors']),
      effect: PromoEffect.parse(effect['type']),
      effectColor: parsePromoHex(effect['color']) ?? const Color(0xFFFFD54F),
      action: PromoAction.fromJson(json['action']),
      endsAt: ends == null ? null : DateTime.tryParse(ends)?.toLocal(),
    );
  }

  /// Template key as sent (`spotlight`, `offer_card`, …).
  final String template;
  final String badge;

  /// May hold colour markup: `{words}` / `{#RRGGBB|words}`.
  final String title;
  final String subtitle;
  final String offerValue;
  final String offerCaption;
  final String couponCode;
  final String ctaLabel;

  /// Icon keys (`arrow_right`, `gift`…; `none` = no icon).
  final String ctaIcon;
  final String icon;
  final String? imageUrl;
  final PromoImageFocus imageFocus;

  /// `image_side: left` (banners): the template is mirrored.
  final bool imageLeft;
  final PromoPalette palette;
  final PromoEffect effect;
  final Color effectColor;
  final PromoAction action;

  /// Countdown templates count down to it.
  final DateTime? endsAt;

  bool get hasImage => imageUrl != null && imageUrl!.isNotEmpty;

  /// A countdown whose end has passed (or that has no end) cannot show.
  bool endedAt(DateTime now) => endsAt == null || !endsAt!.isAfter(now);
}
