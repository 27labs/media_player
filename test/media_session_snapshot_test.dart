import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/media/media_session_snapshot.dart';

import 'fixtures.dart';

void main() {
  group('MediaSessionSnapshot', () {
    test('decodes the native snapshot contract', () {
      final snapshot = MediaSessionSnapshot.fromPlatformMap(
        platformSnapshotMap(),
      );

      expect(snapshot.revision, 7);
      expect(snapshot.title, 'Night Drive');
      expect(snapshot.artist, 'Example Artist');
      expect(snapshot.playbackStatus, MediaPlaybackStatus.playing);
      expect(snapshot.capabilities.canPrevious, isFalse);
      expect(snapshot.capabilities.canNext, isTrue);
      expect(snapshot.artworkRevision, 3);
    });

    test('rejects malformed required fields', () {
      final missingTimeline = platformSnapshotMap()..remove('timeline');
      expect(
        () => MediaSessionSnapshot.fromPlatformMap(missingTimeline),
        throwsFormatException,
      );

      final wrongRevision = platformSnapshotMap()..['revision'] = 'seven';
      expect(
        () => MediaSessionSnapshot.fromPlatformMap(wrongRevision),
        throwsFormatException,
      );
    });

    test('extrapolates playing position and clamps it to the seek range', () {
      const timeline = MediaTimeline(
        position: Duration(seconds: 119),
        start: Duration.zero,
        end: Duration(seconds: 180),
        minimumSeek: Duration.zero,
        maximumSeek: Duration(seconds: 120),
        updatedAt: Duration(seconds: 10),
        playbackRate: 1,
      );

      expect(
        timeline.estimatedPosition(
          nowSinceEpoch: const Duration(seconds: 15),
          isPlaying: true,
        ),
        const Duration(seconds: 120),
      );
      expect(
        timeline.estimatedPosition(
          nowSinceEpoch: const Duration(seconds: 15),
          isPlaying: false,
        ),
        const Duration(seconds: 119),
      );
    });
  });
}
