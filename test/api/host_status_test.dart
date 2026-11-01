import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/api/host_status/host_status_models.dart';

void main() {
  group('HostStatus', () {
    test('reads what the server sends a client', () {
      final s = HostStatus.fromJson(const {
        'documentId': 'st_1',
        'media': '/uploads/clip.mp4',
        'recordedAt': '2026-11-01T10:00:00.000Z',
        'visibleUntil': '2026-11-02T10:00:00.000Z',
      });
      expect(s, isNotNull);
      expect(s!.documentId, 'st_1');
      expect(s.media, '/uploads/clip.mp4');
      expect(s.recordedAt?.toUtc().hour, 10);
    });

    test('a status with no media is not a status', () {
      // The server nulls the file for anything unapproved, and nulls it again
      // once purged. Either way there is nothing to show.
      expect(HostStatus.fromJson(const {'documentId': 'st_1'}), isNull);
      expect(
        HostStatus.fromJson(const {'documentId': 'st_1', 'media': ''}),
        isNull,
      );
    });

    test('junk is dropped rather than throwing', () {
      expect(HostStatus.fromJson(null), isNull);
      expect(HostStatus.fromJson('nope'), isNull);
      expect(HostStatus.fromJson(const {}), isNull);
    });

    test('an unparseable date leaves the field null, not the whole row', () {
      final s = HostStatus.fromJson(const {
        'documentId': 'st_1',
        'media': '/uploads/clip.mp4',
        'recordedAt': 'whenever',
      });
      expect(s, isNotNull);
      expect(s!.recordedAt, isNull);
    });

    test('a list keeps only the rows that can be shown, in order', () {
      final list = HostStatus.listFrom(const {
        'results': [
          {'documentId': 'a', 'media': '/a.mp4'},
          {'documentId': 'b'},
          {'documentId': 'c', 'media': '/c.mp4'},
        ],
      });
      expect(list.map((s) => s.documentId), ['a', 'c']);
    });

    test('a missing or malformed envelope yields no rows', () {
      expect(HostStatus.listFrom(null), isEmpty);
      expect(HostStatus.listFrom(const {'results': 'nope'}), isEmpty);
      expect(HostStatus.listFrom(const {}), isEmpty);
    });
  });

  group('HostOwnStatus', () {
    test('the host sees their own review state', () {
      final s = HostOwnStatus.fromJson(const {
        'documentId': 'st_1',
        'media': '/uploads/clip.mp4',
        'status': 'pending',
        'state': 'pending',
        'recordedAt': '2026-11-01T10:00:00.000Z',
      });
      expect(s, isNotNull);
      expect(s!.status, 'pending');
      expect(s.state, 'pending');
      expect(s.isLive, isFalse);
    });

    test('only an approved clip inside its window counts as live', () {
      final live = HostOwnStatus.fromJson(const {
        'documentId': 'a',
        'media': '/a.mp4',
        'status': 'approved',
        'state': 'visible',
      });
      expect(live!.isLive, isTrue);

      final expired = HostOwnStatus.fromJson(const {
        'documentId': 'b',
        'media': '/b.mp4',
        'status': 'approved',
        'state': 'expired',
      });
      expect(expired!.isLive, isFalse);
    });

    test('a host keeps seeing a clip the server withheld the file for', () {
      // Their own pending clip is exempt from the strip, but a purged one has
      // no file at all - and it still belongs in their history.
      final s = HostOwnStatus.fromJson(const {
        'documentId': 'st_1',
        'status': 'rejected',
        'state': 'rejected',
      });
      expect(s, isNotNull);
      expect(s!.media, isNull);
    });
  });
}
