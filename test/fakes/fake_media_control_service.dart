import 'dart:async';
import 'dart:typed_data';

import 'package:media_player/media/media_control_service.dart';

class SentMediaCommand {
  const SentMediaCommand({
    required this.command,
    required this.expectedRevision,
    required this.position,
  });

  final MediaCommand command;
  final int expectedRevision;
  final Duration? position;
}

class FakeMediaControlService implements MediaControlService {
  final eventsController = StreamController<MediaSessionEvent>.broadcast();
  final sentCommands = <SentMediaCommand>[];
  final artwork = <int, Future<Uint8List?>>{};
  Completer<MediaCommandResult>? nextCommand;

  @override
  Stream<MediaSessionEvent> get events => eventsController.stream;

  void emit(MediaSessionEvent event) => eventsController.add(event);

  void emitError(Object error) => eventsController.addError(error);

  @override
  Future<Uint8List?> loadArtwork(int revision) {
    return artwork[revision] ?? Future<Uint8List?>.value();
  }

  @override
  Future<MediaCommandResult> send(
    MediaCommand command, {
    required int expectedRevision,
    Duration? position,
  }) {
    sentCommands.add(
      SentMediaCommand(
        command: command,
        expectedRevision: expectedRevision,
        position: position,
      ),
    );
    final pending = nextCommand;
    nextCommand = null;
    return pending?.future ??
        Future.value(
          MediaCommandResult(accepted: true, revision: expectedRevision),
        );
  }

  Future<void> close() => eventsController.close();
}
