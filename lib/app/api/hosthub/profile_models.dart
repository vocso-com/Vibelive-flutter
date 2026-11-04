import '../../../core/network/strapi.dart';
import 'catalog_models.dart';
import 'expertise_models.dart';
import 'verification_models.dart';

/// The flag readers the RN host code used (the backend mixes bools, 0/1 and
/// strings).
abstract final class HostFlag {
  /// `true`, `1` or `'true'` (RN `truthy` / `isApproved` checks).
  static bool isOn(dynamic v) =>
      v == true || v == 1 || (v is String && v.toLowerCase() == 'true');

  /// [isOn] plus `'approved'` / `'verified'` (RN `isTruthyFlag`).
  static bool isTruthy(dynamic v) {
    if (isOn(v)) return true;
    final s = v is String ? v.toLowerCase() : '';
    return s == 'approved' || s == 'verified';
  }
}

/// The host's own expert profile (`/expert-profiles`), normalized like RN
/// `normalizeExpert`. [raw] keeps every field (and is what the session
/// stores); getters cover what the host screens read.
class HostProfile {
  const HostProfile(this.raw);

  final JsonMap raw;

  static const genders = ['Male', 'Female', 'Others'];

  static HostProfile? fromResponse(dynamic body) => from(Strapi.body(body));

  static HostProfile? from(dynamic expert) {
    final n = normalize(expert);
    return n == null ? null : HostProfile(n);
  }

  factory HostProfile.fromJson(Object? json) =>
      HostProfile(Map<String, dynamic>.from(json! as Map));

  JsonMap toJson() => raw;

  /// Unwraps the relations the host screens read. Only keys the server sent
  /// are touched, so a PUT response (no relations) can be merged over a
  /// populated copy without wiping it. Null without an id.
  static JsonMap? normalize(dynamic expert) {
    final node = Strapi.map(expert);
    if (node == null || (node['id'] == null && node['documentId'] == null)) {
      return null;
    }
    final out = <String, dynamic>{...node};
    void list(String k) {
      if (node.containsKey(k)) out[k] = Strapi.list(node[k]);
    }

    if (node.containsKey('audio_intro')) {
      out['audio_intro'] = Strapi.map(node['audio_intro']);
    }
    if (node.containsKey('video_intro')) {
      out['video_intro'] = Strapi.map(node['video_intro']);
    }
    for (final k in const ['rates', 'durations']) {
      if (node.containsKey(k)) {
        out[k] = Strapi.map(node[k]) ?? <String, dynamic>{};
      }
    }
    if (node.containsKey('schedule')) {
      out['schedule'] = [
        for (final row in Strapi.list(node['schedule'])) _scheduleRow(row),
      ];
    }
    list('language');
    list('categories');
    list('expert_profile_approvals');
    list('expert_verifications');
    list('host_profile_images');
    list('service_area_selections');
    return out;
  }

  static JsonMap _scheduleRow(JsonMap row) => {
    ...row,
    'days': (J.str(row['days']) ?? '').trim(),
    'timeSlots': [
      for (final slot in Strapi.list(row['timeSlots']))
        if (J.str(slot['startTime']) != null && J.str(slot['endTime']) != null)
          slot,
    ],
  };

  /// Layers maps left to right (later wins) into a profile; null without id.
  static HostProfile? merge(Iterable<JsonMap?> layers) =>
      from(<String, dynamic>{for (final l in layers) ...?l});

  int? get id => J.integer(raw['id']);
  String? get documentId => J.str(raw['documentId']);

  /// documentId first, like RN `expert.documentId || expert.id`.
  String get key => documentId ?? J.str(raw['id']) ?? '';

  bool isSameRecord(String ref) =>
      ref.isNotEmpty && (ref == documentId || ref == J.str(raw['id']));

  /// Whether a raw expert map (e.g. the session's) is the record [ref].
  static bool sameRecord(JsonMap? expert, String ref) {
    final m = Strapi.map(expert);
    if (m == null || ref.isEmpty) return false;
    return ref == J.str(m['documentId']) || ref == J.str(m['id']);
  }

  String get handler => J.str(raw['handler']) ?? '';
  String get tagline => J.str(raw['tagline']) ?? '';
  String get descriptions => J.str(raw['descriptions']) ?? '';
  String get website => J.str(raw['website']) ?? '';
  String? get gender => normalizeGender(J.str(raw['gender']));

  bool get isApproved => HostFlag.isOn(raw['isApproved']);
  bool get isActive => HostFlag.isOn(raw['isActive']);
  bool get isVerified => HostFlag.isOn(raw['isVerified']);

  /// RN screens skip the onboarding hand-off for approved or live hosts.
  bool get isLiveOrApproved => isApproved || isActive;

  bool get callAnyTime => J.boolean(raw['callAnyTime']);

  /// Backend field is spelled `vocationMode`.
  bool get vacationMode => J.boolean(raw['vocationMode']);

  HostAvailability get availability => vacationMode
      ? HostAvailability.vacation
      : (callAnyTime ? HostAvailability.available : HostAvailability.custom);

  HostRates get rates => HostRates.from(raw['rates']);

  /// Backend-controlled pricing for this host (call_pricing §5.2), present on
  /// the host's own profile only when the feature is active for them;
  /// [CallPricing.inactive] otherwise, which keeps the editable rate screen.
  CallPricing get callPricing => CallPricing.from(raw['callPricing']);

  List<HostOption> get languages => [
    for (final row in Strapi.list(raw['language'])) ?HostOption.language(row),
  ];

  /// Only populated when the read asked for `categories`.
  List<HostOption> get categories => [
    for (final row in Strapi.list(raw['categories'])) ?HostOption.category(row),
  ];

  /// Schedule rows with a day (RN `normalizeExpertSchedule`).
  List<JsonMap> get scheduleRows => [
    for (final row in Strapi.list(raw['schedule']))
      if ((J.str(row['days']) ?? '').trim().isNotEmpty) _scheduleRow(row),
  ];

  /// Slots per weekday, sorted by start (RN ScheduleScreen `fromApiSchedule`).
  Map<HostWeekday, List<HostTimeSlot>> get weeklySchedule {
    final rows = scheduleRows;
    return {
      for (final day in HostWeekday.values)
        day: () {
          final row = rows.where((r) => HostWeekday.fromApi(r['days']) == day);
          final slots = [
            if (row.isNotEmpty)
              for (final s in Strapi.list(row.first['timeSlots']))
                ?HostTimeSlot.fromApi(s),
          ]..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
          return slots;
        }(),
    };
  }

  /// Photos with a URL, primary first, then by priority (RN
  /// `normalizeExpertProfileImages`).
  List<HostProfileImage> get profileImages {
    final rows = Strapi.list(raw['host_profile_images']);
    return HostProfileImage.sorted([
      for (var i = 0; i < rows.length; i++)
        HostProfileImage.fromRow(rows[i], i),
    ]).where((img) => img.imageUrl != null).toList();
  }

  List<JsonMap> get approvals => Strapi.list(raw['expert_profile_approvals']);

  List<VerificationRecord> get verifications => [
    for (final row in Strapi.list(raw['expert_verifications']))
      VerificationRecord(row),
  ];

  JsonMap? get audioIntro => Strapi.map(raw['audio_intro']);
  String? get audioIntroUrl => Strapi.mediaFromAsset(audioIntro);
  Object? get audioIntroMediaId =>
      audioIntro?['id'] ?? audioIntro?['documentId'];

  JsonMap? get videoIntro => Strapi.map(raw['video_intro']);
  String? get videoIntroUrl => Strapi.mediaFromAsset(videoIntro);
  Object? get videoIntroMediaId =>
      videoIntro?['id'] ?? videoIntro?['documentId'];

  // ── Moderation (read by the RN ModerationStatus banners) ────────────────
  /// `pending_review`, `rejected`, … or null.
  String? get moderationStatus => J.str(raw['moderation_status']);
  String? get moderationNote => J.str(raw['moderation_note']);
  String? get audioIntroStatus => J.str(raw['audio_intro_status']);
  String? get videoIntroStatus => J.str(raw['video_intro_status']);

  /// Fields waiting for review (`pending_changes` keys minus `submittedAt`).
  List<String> get pendingChangeFields {
    final pending = raw['pending_changes'];
    if (pending is! Map) return const [];
    return [
      for (final k in pending.keys)
        if (k != 'submittedAt') k.toString(),
    ];
  }

  // ── Completion (RN isExpertProfileComplete / getExpertProfileCompletion) ─
  bool get hasProfessionalDetails =>
      handler.trim().isNotEmpty &&
      tagline.trim().isNotEmpty &&
      descriptions.trim().isNotEmpty &&
      Strapi.list(raw['language']).isNotEmpty;

  bool get hasSchedule =>
      scheduleRows.isNotEmpty ||
      HostFlag.isTruthy(raw['callAnyTime']) ||
      HostFlag.isTruthy(raw['vocationMode']);

  /// Without the expertise check (RN `isExpertProfileComplete`).
  HostProfileCompletion completion() => HostProfileCompletion([
    if (!hasProfessionalDetails) HostProfileSection.professional,
    if (!hasSchedule) HostProfileSection.schedule,
    if (!rates.hasAny) HostProfileSection.rates,
  ]);

  /// With the expertise check (RN `getExpertProfileCompletion`); a null
  /// [expertise] counts as "not set", as RN did when the read failed.
  HostProfileCompletion completionWith(ExpertiseSelections? expertise) =>
      HostProfileCompletion([
        if (!hasProfessionalDetails) HostProfileSection.professional,
        if (!(expertise?.hasAny ?? false)) HostProfileSection.expertise,
        if (!hasSchedule) HostProfileSection.schedule,
        if (!rates.hasAny) HostProfileSection.rates,
      ]);

  /// Profile handle as saved (RN `sanitizeProfileHandle`).
  static String sanitizeHandle(String? raw) => (raw ?? '')
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll(RegExp(r'[^a-z_]'), '');

  /// Canonical gender value (Male/Female/Others), case-insensitive.
  static String? normalizeGender(String? value) {
    final v = (value ?? '').trim().toLowerCase();
    if (v.isEmpty) return null;
    for (final g in genders) {
      if (g.toLowerCase() == v) return g;
    }
    return null;
  }
}

enum HostAvailability { vacation, available, custom }

class HostRates {
  const HostRates({this.voiceCallRate = 0, this.videoCallRate = 0});

  /// Per-minute rates; anything unparsable reads as 0 (RN `parseRate`).
  factory HostRates.from(dynamic rates) {
    final m = Strapi.map(rates) ?? const {};
    double rate(dynamic v) {
      final n = J.number(v);
      return n != null && n.isFinite ? n : 0;
    }

    return HostRates(
      voiceCallRate: rate(m['voiceCallRate']),
      videoCallRate: rate(m['videoCallRate']),
    );
  }

  final double voiceCallRate;
  final double videoCallRate;

  bool get hasAny => voiceCallRate > 0 || videoCallRate > 0;

  JsonMap toJson() => {
    'voiceCallRate': voiceCallRate,
    'videoCallRate': videoCallRate,
  };
}

/// What VibeLive pays this host per minute when the backend controls pricing
/// (call_pricing §5.2): read from the `callPricing` block the backend adds to
/// the host's own expert-profile. Parsed leniently — absent or `active:false`
/// reads as [inactive] (the host keeps the editable rate screen), and a
/// missing amount reads as null (the screen shows nothing for it rather than
/// crashing). The app never sends any of this back; it is display-only.
class CallPricing {
  const CallPricing({
    required this.active,
    this.level,
    this.voiceEarn,
    this.videoEarn,
    this.currency = '₹',
  });

  /// The feature is off for this host: the current editable rate screen.
  static const inactive = CallPricing(active: false);

  factory CallPricing.from(dynamic raw) {
    final m = Strapi.map(raw);
    if (m == null || !HostFlag.isOn(m['active'])) return inactive;
    // A non-finite or negative amount is treated as absent (show nothing).
    double? earn(dynamic v) {
      final n = J.number(v);
      return n != null && n.isFinite && n >= 0 ? n.toDouble() : null;
    }

    final cur = (J.str(m['currency']) ?? '').trim();
    return CallPricing(
      active: true,
      level: J.integer(m['level']),
      voiceEarn: earn(m['voiceEarn']),
      videoEarn: earn(m['videoEarn']),
      currency: cur.isEmpty ? '₹' : cur,
    );
  }

  final bool active;

  /// The host's earning level (1–5), for an optional note. Null = not sent.
  final int? level;

  /// Per-minute host earnings (₹). Null = the backend sent no number.
  final double? voiceEarn;
  final double? videoEarn;
  final String currency;
}

enum HostWeekday {
  monday('Monday'),
  tuesday('Tuesday '),
  wednesday('Wednesday'),
  thursday('Thursday'),
  friday('Friday'),
  saturday('Saturday'),
  sunday('Sunday');

  const HostWeekday(this.apiValue);

  /// Exact backend enum value: `'Tuesday '` really ends with a space (RN
  /// ScheduleScreen `DAYS` table); reads compare trimmed.
  final String apiValue;

  static HostWeekday? fromApi(dynamic value) {
    final v = (J.str(value) ?? '').trim().toLowerCase();
    for (final d in values) {
      if (d.apiValue.trim().toLowerCase() == v) return d;
    }
    return null;
  }
}

/// A slot in minutes since midnight.
class HostTimeSlot {
  const HostTimeSlot(this.startMinutes, this.endMinutes);

  final int startMinutes;
  final int endMinutes;

  static HostTimeSlot? fromApi(dynamic slot) {
    final m = Strapi.map(slot);
    final start = parseTime(J.str(m?['startTime']));
    final end = parseTime(J.str(m?['endTime']));
    return start == null || end == null ? null : HostTimeSlot(start, end);
  }

  /// Strapi time (`HH:mm[:ss.SSS]`) or display time (`9:05 PM`).
  static int? parseTime(String? value) {
    final s = (value ?? '').trim();
    final m12 = RegExp(
      r'^(\d{1,2}):(\d{2})\s*(AM|PM)$',
      caseSensitive: false,
    ).firstMatch(s);
    if (m12 != null) {
      var h = int.parse(m12[1]!);
      final min = int.parse(m12[2]!);
      final pm = m12[3]!.toUpperCase() == 'PM';
      if (pm && h != 12) h += 12;
      if (!pm && h == 12) h = 0;
      return _valid(h, min);
    }
    final m24 = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(s);
    if (m24 == null) return null;
    return _valid(int.parse(m24[1]!), int.parse(m24[2]!));
  }

  static int? _valid(int h, int m) =>
      h < 0 || h > 23 || m < 0 || m > 59 ? null : h * 60 + m;

  /// Strapi `time` format the RN app wrote: `HH:mm:00.000`.
  static String formatTime(int minutes) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(minutes ~/ 60)}:${two(minutes % 60)}:00.000';
  }

  int get durationMinutes => endMinutes - startMinutes;

  bool overlaps(HostTimeSlot other) =>
      startMinutes < other.endMinutes && other.startMinutes < endMinutes;

  JsonMap toJson() => {
    'startTime': formatTime(startMinutes),
    'endTime': formatTime(endMinutes),
  };
}

/// A `/profile-images` row (RN `normalizeProfileImageRow`).
class HostProfileImage {
  const HostProfileImage(this.raw, {required this.priority});

  final JsonMap raw;

  /// The row's priority, or its 1-based position when missing.
  final int priority;

  factory HostProfileImage.fromRow(dynamic row, int index) {
    final m = Strapi.map(row) ?? <String, dynamic>{};
    final p = J.integer(m['priority']) ?? 0;
    return HostProfileImage(m, priority: p > 0 ? p : index + 1);
  }

  int? get id => J.integer(raw['id']);
  String? get documentId => J.str(raw['documentId']);

  /// documentId first: what PUT/DELETE address.
  String? get key => documentId ?? J.str(raw['id']);

  /// RN `${documentId}:${id}` identity.
  String get identity => '${documentId ?? ''}:${J.str(raw['id']) ?? ''}';

  bool get isPrimary => HostFlag.isOn(raw['isprimary']);

  JsonMap get image => Strapi.map(raw['image']) ?? const {};

  /// Media id to re-attach this photo to a slot.
  Object? get imageId => image['id'] ?? image['documentId'];

  String? get imageUrl => image.isEmpty ? null : Strapi.mediaFromAsset(image);

  /// Moderation state; rows without one are still `pending`.
  String get moderationStatus => J.str(raw['status_enum']) ?? 'pending';

  /// Primary first, then priority; stable for equal priorities.
  static List<HostProfileImage> sorted(List<HostProfileImage> rows) {
    final indexed = [for (var i = 0; i < rows.length; i++) (i, rows[i])];
    indexed.sort((a, b) {
      final (ia, ra) = a;
      final (ib, rb) = b;
      if (ra.isPrimary != rb.isPrimary) return ra.isPrimary ? -1 : 1;
      final byPriority = ra.priority.compareTo(rb.priority);
      return byPriority != 0 ? byPriority : ia.compareTo(ib);
    });
    return [for (final (_, row) in indexed) row];
  }
}

/// Host-profile sections the approval flow requires, in RN order.
enum HostProfileSection {
  professional,
  expertise,
  schedule,
  rates;

  String get i18nKey => 'hosthub:sections.$name';
}

class HostProfileCompletion {
  const HostProfileCompletion(this.missing);

  final List<HostProfileSection> missing;

  bool get complete => missing.isEmpty;

  /// RN `nextStepFromMissing`: schedule, then rates; null means "go to
  /// approval".
  HostProfileSection? get nextSection {
    if (missing.contains(HostProfileSection.schedule)) {
      return HostProfileSection.schedule;
    }
    if (missing.contains(HostProfileSection.rates)) {
      return HostProfileSection.rates;
    }
    return null;
  }
}
