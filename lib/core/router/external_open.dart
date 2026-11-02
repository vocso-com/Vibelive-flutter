import 'package:flutter/foundation.dart';

/// When the app was last sent somewhere from outside: a notification tap or
/// a link (scheme, website, share, campaign). The app-open popup stays away
/// from an open like that: the user came for something specific.
abstract final class ExternalOpen {
  static DateTime? _at;
  static String? _source;

  static void mark(String source) {
    _at = DateTime.now();
    _source = source;
  }

  /// Something opened the app from outside at or after [time].
  static bool since(DateTime time) => _at != null && !_at!.isBefore(time);

  static String? get lastSource => _source;

  @visibleForTesting
  static void reset() {
    _at = null;
    _source = null;
  }
}
