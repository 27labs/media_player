import 'package:flutter/services.dart';

import 'media_session_snapshot.dart';

enum MediaCommand {
  playPause('playPause'),
  play('play'),
  pause('pause'),
  previous('previous'),
  next('next'),
  seek('seek'),
  retry('retry');

  const MediaCommand(this.platformName);

  final String platformName;
}

sealed class MediaSessionEvent {
  const MediaSessionEvent();
}

class MediaSessionAvailable extends MediaSessionEvent {
  const MediaSessionAvailable(this.snapshot);

  final MediaSessionSnapshot snapshot;
}

class MediaSessionUnavailable extends MediaSessionEvent {
  const MediaSessionUnavailable(this.reason);

  final String reason;
}

class MediaSessionFailure extends MediaSessionEvent {
  const MediaSessionFailure({required this.code, required this.message});

  final String code;
  final String message;
}

class MediaCommandResult {
  const MediaCommandResult({required this.accepted, required this.revision});

  final bool accepted;
  final int revision;
}

abstract interface class MediaControlService {
  Stream<MediaSessionEvent> get events;

  Future<MediaCommandResult> send(
    MediaCommand command, {
    required int expectedRevision,
    Duration? position,
  });

  Future<Uint8List?> loadArtwork(int revision);
}

class PlatformMediaControlService implements MediaControlService {
  const PlatformMediaControlService();

  static const _commands = MethodChannel('media_controls/commands');
  static const _events = EventChannel('media_controls/events');

  @override
  Stream<MediaSessionEvent> get events {
    return _events.receiveBroadcastStream().map(_decodeEvent);
  }

  @override
  Future<MediaCommandResult> send(
    MediaCommand command, {
    required int expectedRevision,
    Duration? position,
  }) async {
    final arguments = <String, Object?>{
      'expectedRevision': expectedRevision,
      if (command == MediaCommand.seek)
        'positionMs': position?.inMilliseconds ?? 0,
    };
    final response = await _commands.invokeMapMethod<Object?, Object?>(
      command.platformName,
      arguments,
    );
    return MediaCommandResult(
      accepted: response?['accepted'] == true,
      revision: (response?['revision'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<Uint8List?> loadArtwork(int revision) async {
    return _commands.invokeMethod<Uint8List>('getArtwork', <String, Object?>{
      'revision': revision,
    });
  }

  MediaSessionEvent _decodeEvent(Object? value) {
    if (value is! Map<Object?, Object?>) {
      return const MediaSessionFailure(
        code: 'invalid_event',
        message: 'Windows returned an invalid media-session event.',
      );
    }
    try {
      return switch (value['type']) {
        'snapshot' => MediaSessionAvailable(
          MediaSessionSnapshot.fromPlatformMap(value),
        ),
        'unavailable' => MediaSessionUnavailable(
          value['reason'] is String ? value['reason']! as String : 'no_session',
        ),
        'error' => MediaSessionFailure(
          code: value['code'] is String ? value['code']! as String : 'unknown',
          message: value['message'] is String
              ? value['message']! as String
              : 'Windows media controls are unavailable.',
        ),
        _ => const MediaSessionFailure(
          code: 'unknown_event',
          message: 'Windows returned an unknown media-session event.',
        ),
      };
    } on FormatException {
      return const MediaSessionFailure(
        code: 'invalid_event',
        message: 'Windows returned an invalid media-session snapshot.',
      );
    }
  }
}
