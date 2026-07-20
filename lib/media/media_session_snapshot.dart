enum MediaPlaybackStatus {
  closed,
  opened,
  changing,
  stopped,
  playing,
  paused,
  unknown;

  static MediaPlaybackStatus fromPlatformValue(Object? value) {
    return switch (value) {
      'closed' => closed,
      'opened' => opened,
      'changing' => changing,
      'stopped' => stopped,
      'playing' => playing,
      'paused' => paused,
      _ => unknown,
    };
  }
}

class MediaPlaybackCapabilities {
  const MediaPlaybackCapabilities({
    required this.canPlay,
    required this.canPause,
    required this.canToggle,
    required this.canPrevious,
    required this.canNext,
    required this.canSeek,
  });

  final bool canPlay;
  final bool canPause;
  final bool canToggle;
  final bool canPrevious;
  final bool canNext;
  final bool canSeek;
}

class MediaTimeline {
  const MediaTimeline({
    required this.position,
    required this.start,
    required this.end,
    required this.minimumSeek,
    required this.maximumSeek,
    required this.updatedAt,
    required this.playbackRate,
  });

  final Duration position;
  final Duration start;
  final Duration end;
  final Duration minimumSeek;
  final Duration maximumSeek;
  final Duration updatedAt;
  final double playbackRate;

  bool get hasDuration => end > start;

  Duration get effectiveMaximumSeek {
    if (maximumSeek > minimumSeek) {
      return maximumSeek;
    }
    return end > minimumSeek ? end : minimumSeek;
  }

  Duration clampSeekPosition(Duration value) {
    return Duration(
      milliseconds: value.inMilliseconds.clamp(
        minimumSeek.inMilliseconds,
        effectiveMaximumSeek.inMilliseconds,
      ),
    );
  }

  Duration estimatedPosition({
    required Duration nowSinceEpoch,
    required bool isPlaying,
  }) {
    final elapsed = nowSinceEpoch - updatedAt;
    final shouldAdvance = isPlaying && playbackRate > 0 && !elapsed.isNegative;
    final estimatedMilliseconds = shouldAdvance
        ? position.inMilliseconds +
              (elapsed.inMilliseconds * playbackRate).round()
        : position.inMilliseconds;
    return clampSeekPosition(Duration(milliseconds: estimatedMilliseconds));
  }
}

class MediaSessionSnapshot {
  const MediaSessionSnapshot({
    required this.revision,
    required this.sourceAppId,
    required this.title,
    required this.artist,
    required this.albumTitle,
    required this.playbackStatus,
    required this.capabilities,
    required this.timeline,
    required this.artworkAvailable,
    required this.artworkPending,
    required this.artworkRevision,
  });

  factory MediaSessionSnapshot.fromPlatformMap(Map<Object?, Object?> value) {
    final session = _requiredMap(value['session'], 'session');
    final playback = _requiredMap(value['playback'], 'playback');
    final timeline = _requiredMap(value['timeline'], 'timeline');
    final artwork = _requiredMap(value['artwork'], 'artwork');

    return MediaSessionSnapshot(
      revision: _requiredInt(value['revision'], 'revision'),
      sourceAppId: _requiredString(session['sourceAppId'], 'sourceAppId'),
      title: _requiredString(session['title'], 'title'),
      artist: _requiredString(session['artist'], 'artist'),
      albumTitle: _requiredString(session['albumTitle'], 'albumTitle'),
      playbackStatus: MediaPlaybackStatus.fromPlatformValue(playback['status']),
      capabilities: MediaPlaybackCapabilities(
        canPlay: _requiredBool(playback['canPlay'], 'canPlay'),
        canPause: _requiredBool(playback['canPause'], 'canPause'),
        canToggle: _requiredBool(playback['canToggle'], 'canToggle'),
        canPrevious: _requiredBool(playback['canPrevious'], 'canPrevious'),
        canNext: _requiredBool(playback['canNext'], 'canNext'),
        canSeek: _requiredBool(playback['canSeek'], 'canSeek'),
      ),
      timeline: MediaTimeline(
        position: Duration(
          milliseconds: _requiredInt(timeline['positionMs'], 'positionMs'),
        ),
        start: Duration(
          milliseconds: _requiredInt(timeline['startMs'], 'startMs'),
        ),
        end: Duration(milliseconds: _requiredInt(timeline['endMs'], 'endMs')),
        minimumSeek: Duration(
          milliseconds: _requiredInt(timeline['minSeekMs'], 'minSeekMs'),
        ),
        maximumSeek: Duration(
          milliseconds: _requiredInt(timeline['maxSeekMs'], 'maxSeekMs'),
        ),
        updatedAt: Duration(
          milliseconds: _requiredInt(
            timeline['updatedAtEpochMs'],
            'updatedAtEpochMs',
          ),
        ),
        playbackRate: _requiredDouble(playback['rate'], 'rate'),
      ),
      artworkAvailable: _requiredBool(artwork['available'], 'available'),
      artworkPending: _requiredBool(artwork['pending'], 'pending'),
      artworkRevision: artwork['revision'] == null
          ? null
          : _requiredInt(artwork['revision'], 'artworkRevision'),
    );
  }

  final int revision;
  final String sourceAppId;
  final String title;
  final String artist;
  final String albumTitle;
  final MediaPlaybackStatus playbackStatus;
  final MediaPlaybackCapabilities capabilities;
  final MediaTimeline timeline;
  final bool artworkAvailable;
  final bool artworkPending;
  final int? artworkRevision;

  bool get isPlaying => playbackStatus == MediaPlaybackStatus.playing;

  String get sourceLabel {
    final packageSeparator = sourceAppId.indexOf('_');
    final appId = packageSeparator < 0
        ? sourceAppId
        : sourceAppId.substring(0, packageSeparator);
    return appId.replaceAll('.', ' ').trim();
  }
}

Map<Object?, Object?> _requiredMap(Object? value, String field) {
  if (value is Map<Object?, Object?>) {
    return value;
  }
  throw FormatException('Expected $field to be a map.');
}

String _requiredString(Object? value, String field) {
  if (value is String) {
    return value;
  }
  throw FormatException('Expected $field to be a string.');
}

bool _requiredBool(Object? value, String field) {
  if (value is bool) {
    return value;
  }
  throw FormatException('Expected $field to be a boolean.');
}

int _requiredInt(Object? value, String field) {
  if (value is num) {
    return value.toInt();
  }
  throw FormatException('Expected $field to be a number.');
}

double _requiredDouble(Object? value, String field) {
  if (value is num) {
    return value.toDouble();
  }
  throw FormatException('Expected $field to be a number.');
}
