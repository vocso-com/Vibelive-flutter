import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/core/config/runtime_config.dart';

/// The server decides whether host video intros and statuses are on, how long a
/// clip may be, and how many a host gets a day. The app has to be told, or it
/// offers a record button for a feature the server will refuse — which reads to
/// a host as the app being broken rather than as a feature not switched on.
void main() {
  group('RuntimeConfig.hostMedia', () {
    test('defaults keep both features off', () {
      // A build that never reaches the server must not offer either.
      const d = RuntimeConfig.defaults;
      expect(d.hostMedia.videoIntroEnabled, isFalse);
      expect(d.hostMedia.statusEnabled, isFalse);
    });

    test('limits are present even by default', () {
      // Enforced client-side the moment a feature turns on, so they can never
      // be missing when needed.
      const d = RuntimeConfig.defaults;
      expect(d.hostMedia.videoIntroMaxSeconds, 60);
      expect(d.hostMedia.statusMaxPerDay, 10);
      expect(d.hostMedia.statusVisibleHours, 24);
    });

    test('reads what the server sends', () {
      final c = RuntimeConfig.resolve(const {
        'hostMedia': {
          'videoIntroEnabled': true,
          'videoIntroMaxSeconds': 30,
          'statusEnabled': true,
          'statusMaxPerDay': 3,
          'statusVisibleHours': 12,
        },
      });
      expect(c.hostMedia.videoIntroEnabled, isTrue);
      expect(c.hostMedia.videoIntroMaxSeconds, 30);
      expect(c.hostMedia.statusEnabled, isTrue);
      expect(c.hostMedia.statusMaxPerDay, 3);
      expect(c.hostMedia.statusVisibleHours, 12);
    });

    test('an older server that sends no block leaves both off', () {
      // The app ships before the server does on some releases.
      final c = RuntimeConfig.resolve(const {'pricing': {}});
      expect(c.hostMedia.videoIntroEnabled, isFalse);
      expect(c.hostMedia.statusEnabled, isFalse);
      expect(c.hostMedia.videoIntroMaxSeconds, 60);
    });

    test('junk never becomes a zero limit', () {
      // A zero-second limit would refuse every recording the host makes.
      final c = RuntimeConfig.resolve(const {
        'hostMedia': {
          'videoIntroMaxSeconds': 'ages',
          'statusMaxPerDay': null,
          'statusVisibleHours': -4,
        },
      });
      expect(c.hostMedia.videoIntroMaxSeconds, 60);
      expect(c.hostMedia.statusMaxPerDay, 10);
      expect(c.hostMedia.statusVisibleHours, 24);
    });

    test('a daily cap of zero is honoured, because it means stop', () {
      // Distinct from missing: somebody typed 0 to stop posting.
      final c = RuntimeConfig.resolve(const {
        'hostMedia': {'statusEnabled': true, 'statusMaxPerDay': 0},
      });
      expect(c.hostMedia.statusMaxPerDay, 0);
      expect(
        c.hostMedia.canPostStatus,
        isFalse,
        reason: 'enabled but capped at zero still means no posting',
      );
    });

    test('canPostStatus and canRecordIntro fold the switch and the cap', () {
      final on = RuntimeConfig.resolve(const {
        'hostMedia': {'statusEnabled': true, 'videoIntroEnabled': true},
      });
      expect(on.hostMedia.canPostStatus, isTrue);
      expect(on.hostMedia.canRecordIntro, isTrue);
      expect(RuntimeConfig.defaults.hostMedia.canPostStatus, isFalse);
      expect(RuntimeConfig.defaults.hostMedia.canRecordIntro, isFalse);
    });

    test('Vibe length and review switch come from the admin', () {
      const d = RuntimeConfig.defaults;
      expect(d.hostMedia.statusLimit, const Duration(seconds: 30));
      expect(d.hostMedia.statusAutoApprove, isFalse);
      final c = RuntimeConfig.resolve(const {
        'hostMedia': {
          'statusEnabled': true,
          'statusMaxSeconds': 15,
          'statusAutoApprove': true,
        },
      });
      expect(c.hostMedia.statusLimit, const Duration(seconds: 15));
      expect(c.hostMedia.statusAutoApprove, isTrue);
      final junk = RuntimeConfig.resolve(const {
        'hostMedia': {'statusMaxSeconds': 0, 'statusAutoApprove': 'yes'},
      });
      expect(junk.hostMedia.statusLimit, const Duration(seconds: 30));
      expect(junk.hostMedia.statusAutoApprove, isFalse);
    });
  });
}
