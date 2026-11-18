import 'package:flutter/foundation.dart';

import '../../../core/session/session_store.dart';
import '../../../core/storage/app_prefs.dart';

/// Where the app points a host at private photos.
enum PrivatePhotoSpot {
  /// The card above the composer in a chat ("Send one").
  tip,

  /// The banner at the top of the Chats list.
  list,

  /// The dot on the photo button (goes once the host has opened the sheet).
  button,
}

/// Teaching hosts that private photos exist: no host had ever sent one, the
/// option sat third in the photo button's sheet. Per account, on this phone.
///
/// Each spot goes when the host closes it (or, for the dot, opens the sheet);
/// all of them go for good once the host sends their first private photo.
/// Whether a spot may show at all (host side, feature on, a real chat) is the
/// caller's question: this only remembers what the host has done.
class PrivatePhotoPromo extends ChangeNotifier {
  PrivatePhotoPromo._();

  static final instance = PrivatePhotoPromo._();

  static const prefix = 'chat.private_promo.';
  static const _sent = 'sent';

  String? get _key {
    final id = SessionStore.instance.value.userId;
    return id == null ? null : '$prefix$id';
  }

  Set<String> _read(String key) => (AppPrefs.getString(key) ?? '')
      .split(',')
      .where((s) => s.isNotEmpty)
      .toSet();

  /// The host has sent a private photo (from this phone): nothing shows.
  bool get sent {
    final key = _key;
    return key != null && _read(key).contains(_sent);
  }

  /// [spot] may show: signed in, nothing sent yet, not closed.
  bool showing(PrivatePhotoSpot spot) {
    final key = _key;
    if (key == null) return false;
    final done = _read(key);
    return !done.contains(_sent) && !done.contains(spot.name);
  }

  Future<void> dismiss(PrivatePhotoSpot spot) => _add(spot.name);

  Future<void> markSent() => _add(_sent);

  Future<void> _add(String flag) async {
    final key = _key;
    if (key == null) return;
    final done = _read(key);
    if (!done.add(flag)) return;
    await AppPrefs.setString(key, done.join(','));
    notifyListeners();
  }
}
