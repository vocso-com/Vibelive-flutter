import 'package:flutter/foundation.dart';

import '../../../core/network/strapi.dart';
import 'promo_content.dart';

export 'promo_content.dart';

/// The admin's app-open popup templates (backend `src/utils/promo-templates.js`,
/// kind `popup`).
enum PromoPopupTemplate {
  offerCard('offer_card'),
  poster('poster'),
  celebration('celebration'),
  bottomSheet('bottom_sheet'),
  countdown('countdown'),
  spotlight('spotlight'),
  announcement('announcement'),
  fullscreen('fullscreen');

  const PromoPopupTemplate(this.wire);
  final String wire;

  static PromoPopupTemplate? parse(Object? v) {
    for (final t in values) {
      if (t.wire == v) return t;
    }
    return null;
  }

  /// Whether [c] has what this template needs to draw.
  bool canShow(PromoContent c, DateTime now) => switch (this) {
    poster || fullscreen => c.hasImage,
    spotlight => c.hasImage && c.title.isNotEmpty,
    countdown => c.title.isNotEmpty && !c.endedAt(now),
    offerCard || celebration || bottomSheet || announcement =>
      c.title.isNotEmpty,
  };

  /// Templates that cannot draw without their image.
  bool get needsImage => this == poster || this == fullscreen || this == spotlight;
}

/// How often a popup comes back (admin: "When it shows").
enum PromoPopupFrequency {
  /// Every app open.
  everyOpen('every_open'),

  /// Again [PromoPopupRules.reshowAfterHours] after the user closed it.
  afterClose('after_close'),

  /// At most once per local calendar day.
  daily('daily'),

  /// Only once on this phone.
  once('once');

  const PromoPopupFrequency(this.wire);
  final String wire;

  static PromoPopupFrequency parse(Object? v) => values.firstWhere(
    (f) => f.wire == v,
    orElse: () => PromoPopupFrequency.afterClose,
  );
}

@immutable
class PromoPopupRules {
  const PromoPopupRules({
    this.frequency = PromoPopupFrequency.afterClose,
    this.reshowAfterHours = 24,
    this.maxShows = 0,
    this.delaySeconds = 2,
    this.stopAfterAction = true,
    this.closeOnBackdrop = true,
  });

  factory PromoPopupRules.fromJson(Object? json) {
    final r = json is Map ? json : const {};
    return PromoPopupRules(
      frequency: PromoPopupFrequency.parse(r['frequency']),
      reshowAfterHours: (J.integer(r['reshowAfterHours']) ?? 24).clamp(1, 720),
      maxShows: (J.integer(r['maxShows']) ?? 0).clamp(0, 100),
      delaySeconds: (J.integer(r['delaySeconds']) ?? 2).clamp(0, 30),
      stopAfterAction: r['stopAfterAction'] != false,
      closeOnBackdrop: r['closeOnBackdrop'] != false,
    );
  }

  final PromoPopupFrequency frequency;
  final int reshowAfterHours;

  /// 0 = no limit.
  final int maxShows;
  final int delaySeconds;

  /// After the main button, never again.
  final bool stopAfterAction;

  /// A tap outside closes it.
  final bool closeOnBackdrop;
}

@immutable
class PromoPopup {
  const PromoPopup({
    required this.id,
    required this.template,
    this.content = const PromoContent(),
    this.secondaryLabel = '',
    this.rules = const PromoPopupRules(),
  });

  /// Null for a row with no id or one that cannot draw. A template this
  /// build does not know draws as an announcement (title) or a poster
  /// (image only), so a new template still reaches older apps.
  static PromoPopup? fromJson(Object? json, {DateTime? now}) {
    if (json is! Map) return null;
    final id = J.str(json['id']);
    if (id == null) return null;
    final content = PromoContent.fromJson(json);
    final at = now ?? DateTime.now();
    var template = PromoPopupTemplate.parse(json['template']);
    template ??= content.title.isNotEmpty
        ? PromoPopupTemplate.announcement
        : (content.hasImage ? PromoPopupTemplate.poster : null);
    if (template == null || !template.canShow(content, at)) return null;
    return PromoPopup(
      id: id,
      template: template,
      content: content,
      secondaryLabel: J.str(json['secondaryLabel'])?.trim() ?? '',
      rules: PromoPopupRules.fromJson(json['rules']),
    );
  }

  final String id;
  final PromoPopupTemplate template;
  final PromoContent content;

  /// "Maybe later": a text button that closes.
  final String secondaryLabel;
  final PromoPopupRules rules;
}

/// `GET /app-popups`: the live popups for this user, in the admin's order.
@immutable
class PromoPopupFeed {
  const PromoPopupFeed({
    this.enabled = false,
    this.openGapMinutes = 30,
    this.popups = const [],
  });

  static const empty = PromoPopupFeed();

  factory PromoPopupFeed.fromJson(Object? body, {DateTime? now}) {
    if (body is! Map || body['enabled'] != true) return empty;
    final rows = body['popups'];
    return PromoPopupFeed(
      enabled: true,
      openGapMinutes: (J.integer(body['openGapMinutes']) ?? 30).clamp(5, 1440),
      popups: [
        if (rows is List)
          for (final row in rows) ?PromoPopup.fromJson(row, now: now),
      ],
    );
  }

  final bool enabled;

  /// Back in the app after this long in the background = a new app open.
  final int openGapMinutes;
  final List<PromoPopup> popups;
}
