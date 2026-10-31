import 'package:flutter/foundation.dart' show immutable;

import '../../../core/network/strapi.dart';
import 'host_presence.dart';

export 'host_badges.dart';
export 'host_presence.dart';

/// What the client-side filters read, shared by [HostCard] and search rows.
abstract interface class HostTraits {
  List<String> get languages;
  List<String> get topics;

  /// Option values of the support-topic answers (labels can be reworded by
  /// an admin; values cannot).
  List<String> get topicValues;
  List<String> get categories;
  String get specialization;
}

/// A host as Discover, search and the profile sheet show it (RN `mapExpert`).
///
/// Accepts an expert-profile row (user populated) or a public-user row
/// (expert populated), Strapi v4 or v5. [raw] keeps the unwrapped payload.
///
/// RN's English fallbacks are left to the UI: an empty [name], [city] or
/// [tags] means "show [unknownNameKey] / [defaultCityKey] / [defaultTagKey]".
@immutable
class HostCard implements HostTraits {
  const HostCard._({
    required this.raw,
    required this.id,
    required this.receiverId,
    required this.documentId,
    required this.userDocumentId,
    required this.expertProfileDocumentId,
    required this.name,
    required this.city,
    required this.rating,
    required this.reviewCount,
    required this.vPrice,
    required this.aPrice,
    required this.verified,
    required this.instaVerified,
    required this.facebookVerified,
    required this.snapchatVerified,
    required this.instaUrl,
    required this.facebookUrl,
    required this.snapchatUrl,
    required this.websiteUrl,
    required this.isFeatured,
    required this.featuredSequence,
    required this.tagline,
    required this.description,
    required this.handler,
    required this.languages,
    required this.categories,
    required this.tags,
    required this.presence,
    required this.audioIntro,
    this.videoIntro,
    required this.topics,
    required this.topicValues,
    required this.images,
    required this.imageThumbs,
    required this.cardImage,
    required this.cardPlaceholder,
    required this.isApprovedHost,
  });

  static const unknownNameKey = 'listing:host.unknown_name';
  static const defaultCityKey = 'listing:host.default_city';
  static const defaultTagKey = 'listing:host.default_tag';

  /// [index] is the row's position in its list: the last-resort [id].
  factory HostCard.fromJson(Object? json, {int index = 0}) {
    final n = Strapi.map(json) ?? <String, dynamic>{};
    final isPublicUser = _truthy(n['role']) || _truthy(n['mobile']);
    final u = isPublicUser ? n : (Strapi.map(n['user']) ?? const {});
    final e = isPublicUser ? (Strapi.map(n['expert']) ?? const {}) : n;
    final district = Strapi.map(u['district']) ?? const {};

    // Rates: `{videoCallRate, voiceCallRate}` component, else rows of
    // `{callType, ratePerMin}` (video first / audio second by position).
    final rateObject = Strapi.map(e['rates']);
    final rateRows = Strapi.list(e['rates']);
    Object? rateFor(String type) {
      for (final r in rateRows) {
        final callType = (J.str(r['callType']) ?? '').toLowerCase();
        if (callType.contains(type)) return r['ratePerMin'];
      }
      return null;
    }

    final videoRate =
        rateObject?['videoCallRate'] ??
        rateFor('video') ??
        (rateRows.isNotEmpty ? rateRows[0]['ratePerMin'] : null);
    final voiceRate =
        rateObject?['voiceCallRate'] ??
        rateFor('audio') ??
        (rateRows.length > 1 ? rateRows[1]['ratePerMin'] : null);

    // profile_pic_status is mostly null on existing rows, so only explicitly
    // flagged pictures are withheld (an approved-only rule would blank every
    // avatar).
    final picStatus = _trimLower(u['profile_pic_status']);
    final picWithheld = picStatus == 'pending' || picStatus == 'rejected';
    final pic = picWithheld ? null : Strapi.mediaFromAsset(u['profilePic']);
    final picThumb = picWithheld
        ? null
        : Strapi.mediaThumbFromAsset(u['profilePic']);

    final gallery = _gallery(e['host_profile_images']);
    final images = gallery.isNotEmpty
        ? [for (final g in gallery) g.url]
        : [?pic];
    final imageThumbs = gallery.isNotEmpty
        ? [for (final g in gallery) g.thumb ?? g.url]
        : [if (pic != null) picThumb ?? pic];
    final cardImage = gallery.isNotEmpty
        ? (gallery.first.thumb ?? gallery.first.url)
        : picThumb;
    final cardPlaceholder = gallery.isNotEmpty
        ? gallery.first.tiny
        : (picWithheld ? null : Strapi.mediaTinyFromAsset(u['profilePic']));

    // Voice intro only once moderated: the server resets the status to
    // pending whenever the recording changes.
    final audioUrl = Strapi.mediaFromAsset(e['audio_intro']);
    final audioApproved = _trimLower(e['audio_intro_status']) == 'approved';
    // Checked here as well as on the server. The server withholds the file for
    // anything other than `approved`, so this is the second of two locks rather
    // than the only one — and it keeps the client honest if an older build of
    // the backend ever serves one.
    final videoUrl = Strapi.mediaFromAsset(e['video_intro']);
    final videoApproved = _trimLower(e['video_intro_status']) == 'approved';

    final featuredSequence =
        e['featured_sequence'] ??
        e['featuredSequence'] ??
        n['featured_sequence'] ??
        n['featuredSequence'];
    final featuredFlag =
        e['isFeatured'] ??
        e['is_featured'] ??
        n['isFeatured'] ??
        n['is_featured'] ??
        u['isFeatured'] ??
        u['is_featured'];
    final hasSequence =
        featuredSequence != null && featuredSequence.toString() != '';

    final verifications = Strapi.list(
      _or([e['expert_verifications'], n['expert_verifications']]),
    );
    final ver = verifications.isEmpty
        ? const <String, dynamic>{}
        : verifications.first;
    final isVerified = e['isVerified'];
    final badge = ver['Verified_Badge'];
    final badgeVerified =
        isVerified == true ||
        isVerified == 'true' ||
        badge == true ||
        badge == 1 ||
        _lower(badge) == 'true';
    bool social(String key) =>
        badgeVerified && (ver[key] == true || ver[key] == 'true');

    final categories = [
      for (final c in _items(
        _or([e['categories'], n['categories'], u['categories']]),
      ))
        ?_nonEmpty(c is Map ? J.str(_or([c['name'], c['label']])) : J.str(c)),
    ];

    final selections = Strapi.list(e['service_area_selections']);
    final supportTopics = [
      for (final s in selections)
        if (J.str(_dig(s, const ['snapshot', 'question', 'key'])) ==
            SupportTopicKey.question)
          s,
    ];

    return HostCard._(
      raw: n,
      id: J.integer(_or([e['id'], u['id']])) ?? index + 1,
      receiverId: J.integer(_or([u['id'], e['id']])),
      documentId: J.str(
        _or([u['documentId'], e['documentId'], u['id'], e['id']]),
      ),
      userDocumentId: J.str(_or([u['documentId'], u['id']])),
      expertProfileDocumentId: J.str(_or([e['documentId'], e['id']])),
      name: (J.str(_or([u['name'], e['handler']])) ?? '').toUpperCase(),
      city: (J.str(district['name']) ?? '').toUpperCase(),
      rating: _number(e['averageRating']),
      reviewCount: _number(e['reviewCount']).toInt(),
      vPrice: _number(videoRate),
      aPrice: _number(voiceRate),
      verified: badgeVerified,
      instaVerified: social('insta_verified'),
      facebookVerified: social('facebook_verified'),
      snapchatVerified: social('snapchat_verified'),
      instaUrl: J.str(ver['insta_url']),
      facebookUrl: J.str(ver['facebook_url']),
      snapchatUrl: J.str(ver['snapchat_url']),
      websiteUrl: J.str(e['website']),
      isFeatured: _truthy(featuredFlag) || hasSequence,
      featuredSequence: hasSequence ? J.number(featuredSequence) : null,
      tagline: (J.str(e['tagline']) ?? '').trim(),
      description: (J.str(_or([e['descriptions'], e['description']])) ?? '')
          .trim(),
      handler: J.str(e['handler']) ?? '',
      languages: [
        for (final l in Strapi.list(_or([e['language'], e['languages']])))
          ?_nonEmpty(
            J.str(
              _or([l['languageNames'], l['name'], l['language'], l['label']]),
            ),
          ),
      ],
      categories: categories,
      tags: [
        for (final s in selections)
          ?J.str(_dig(s, const ['snapshot', 'option', 'label'])),
      ],
      presence: HostPresence.fromExpert(e),
      audioIntro: audioApproved ? audioUrl : null,
      videoIntro: videoApproved ? videoUrl : null,
      topics: [
        for (final s in supportTopics)
          ?_nonEmpty(J.str(_dig(s, const ['snapshot', 'option', 'label']))),
      ],
      topicValues: [
        for (final s in supportTopics)
          ?_nonEmpty(J.str(_dig(s, const ['snapshot', 'option', 'value']))),
      ],
      images: images,
      imageThumbs: imageThumbs,
      cardImage: cardImage,
      cardPlaceholder: cardPlaceholder,
      isApprovedHost: _isApproved(e),
    );
  }

  /// Persisted/raw form: [HostCard.fromJson] maps it back.
  JsonMap toJson() => raw;

  final JsonMap raw;

  /// Expert-profile id, else user id.
  final int id;

  /// User id: the call receiver.
  final int? receiverId;

  /// User documentId, else expert-profile documentId.
  final String? documentId;
  final String? userDocumentId;
  final String? expertProfileDocumentId;

  /// Upper-cased user name (or handler). Empty → [unknownNameKey].
  final String name;

  /// Upper-cased district. Empty → [defaultCityKey].
  final String city;
  final double rating;
  final int reviewCount;

  /// Video / voice rate per minute.
  final double vPrice;
  final double aPrice;

  /// Verified badge. The social flags only count once the badge itself is
  /// verified, otherwise an unapproved claim would render as a crown.
  final bool verified;
  final bool instaVerified;
  final bool facebookVerified;
  final bool snapchatVerified;
  final String? instaUrl;
  final String? facebookUrl;
  final String? snapchatUrl;
  final String? websiteUrl;
  final bool isFeatured;
  final double? featuredSequence;
  final String tagline;
  final String description;
  final String handler;
  @override
  final List<String> languages;
  @override
  final List<String> categories;

  /// Every service-area answer label. Empty → [defaultTagKey]. Mixes in
  /// gender / relationship answers: public cards show [topics] instead.
  final List<String> tags;

  /// Can take a call right now (`user_status`): the card dot, busy label.
  final HostPresence presence;
  bool get isAvailable => presence.isAvailable;

  /// Playable voice intro: approved recordings only.
  final String? audioIntro;

  /// An approved video intro's URL, or null. Null covers both "no clip" and
  /// "not approved yet": the client has no reason to tell those apart, and a
  /// profile should never hint that there is a clip it is not showing.
  final String? videoIntro;

  /// Support-topic labels: what the person wants to talk about.
  @override
  final List<String> topics;
  @override
  final List<String> topicValues;

  /// Approved gallery images (primary first, then priority), else the
  /// profile picture.
  final List<String> images;

  /// Card-sized rendition (Strapi `medium`) of each of [images], same order:
  /// what Discover already loaded, shown while the original loads.
  final List<String> imageThumbs;

  /// Card-sized rendition of the first image.
  final String? cardImage;

  /// [cardImage]'s few-KB `thumbnail`, shown until [cardImage] arrives.
  final String? cardPlaceholder;

  /// Approved host: the `isApproved` flag or an approved row in
  /// `expert_profile_approvals`. Availability and listing are deliberately
  /// not part of it: an offline host still owns a shareable profile.
  final bool isApprovedHost;

  @override
  String get specialization => categories.isEmpty ? '' : categories.first;

  /// Read with the full populate (feed, popular, search, profile lookups):
  /// everything the profile sheet shows. A summary (call log, favourites)
  /// lacks the rates and service areas.
  bool get hasFullProfile {
    final expert = raw.containsKey('user')
        ? raw
        : (Strapi.map(raw['expert']) ?? const <String, dynamic>{});
    return expert.containsKey('rates') &&
        expert.containsKey('service_area_selections');
  }

  /// `4.0`-style label, as RN rendered `rating`.
  String get ratingLabel => rating.toStringAsFixed(1);

  /// Flags in the shape `VerificationBadge` reads (`user:` or `expert:`).
  JsonMap get badgeFlags => {
    'verified': verified,
    'instaVerified': instaVerified,
    'facebookVerified': facebookVerified,
    'snapchatVerified': snapchatVerified,
  };

  /// Whether [id] (a documentId or numeric id of the user or the expert
  /// profile) points at this host: deep links, blocks, "is this me".
  bool refersTo(Object? id) {
    final target = J.str(id);
    if (target == null) return false;
    return target == documentId ||
        target == userDocumentId ||
        target == expertProfileDocumentId ||
        target == receiverId?.toString() ||
        target == J.str(raw['id']);
  }

  static bool _isApproved(JsonMap e) {
    final flag = e['isApproved'];
    if (flag == true || flag == 1 || _lower(flag) == 'true') return true;
    return Strapi.list(e['expert_profile_approvals']).any(
      (r) =>
          r['is_approved'] == true ||
          r['approved'] == true ||
          _lower(r['status']) == 'approved',
    );
  }

  /// Approved gallery rows only (unreviewed or rejected photos never reach
  /// viewers), primary first, then by priority; ties keep server order.
  static List<_GalleryImage> _gallery(Object? rows) {
    final list = Strapi.list(rows);
    final out = <_GalleryImage>[];
    for (var i = 0; i < list.length; i++) {
      final row = list[i];
      if (_trimLower(row['status_enum']) != 'approved') continue;
      final url = Strapi.mediaFromAsset(row['image']);
      if (url == null) continue;
      final priority = J.number(row['priority']);
      final primary = row['isprimary'];
      out.add(
        _GalleryImage(
          url: url,
          thumb: Strapi.mediaThumbFromAsset(row['image']),
          tiny: Strapi.mediaTinyFromAsset(row['image']),
          priority: priority != null && priority.isFinite && priority > 0
              ? priority
              : (i + 1).toDouble(),
          isPrimary:
              primary == true || primary == 1 || _lower(primary) == 'true',
          order: i,
        ),
      );
    }
    out.sort((a, b) {
      if (a.isPrimary != b.isPrimary) return a.isPrimary ? -1 : 1;
      final byPriority = a.priority.compareTo(b.priority);
      return byPriority != 0 ? byPriority : a.order.compareTo(b.order);
    });
    return out;
  }
}

/// Interests-form question whose options are Discover's topics.
abstract final class SupportTopicKey {
  static const question = 'support_topic';
}

class _GalleryImage {
  const _GalleryImage({
    required this.url,
    required this.thumb,
    required this.tiny,
    required this.priority,
    required this.isPrimary,
    required this.order,
  });

  final String url;
  final String? thumb;
  final String? tiny;
  final double priority;
  final bool isPrimary;
  final int order;
}

/// JS truthiness, for the `a || b` fallbacks ported from RN.
bool _truthy(Object? v) => switch (v) {
  null => false,
  final bool b => b,
  final num n => n != 0 && !n.isNaN,
  final String s => s.isNotEmpty,
  _ => true,
};

/// First truthy value (RN `a || b || c`).
Object? _or(List<Object?> values) {
  for (final v in values) {
    if (_truthy(v)) return v;
  }
  return null;
}

/// RN `Number(x || 0) || 0`.
double _number(Object? v) {
  final n = J.number(v);
  return n == null || !n.isFinite ? 0 : n;
}

/// RN `String(x || '').toLowerCase()`.
String _lower(Object? v) => (J.str(_or([v])) ?? '').toLowerCase();

/// RN `String(x || '').trim().toLowerCase()`.
String _trimLower(Object? v) => _lower(v).trim();

String? _nonEmpty(String? s) {
  final t = s?.trim();
  return t == null || t.isEmpty ? null : t;
}

Object? _dig(Object? map, List<String> path) {
  Object? v = map;
  for (final key in path) {
    if (v is! Map) return null;
    v = v[key];
  }
  return v;
}

/// RN `xlist` without dropping non-map items (categories may be strings).
List<Object?> _items(Object? n) {
  final v = Strapi.node(n);
  if (v == null) return const [];
  final items = v is List ? v : [v];
  return [for (final item in items) Strapi.node(item)];
}
