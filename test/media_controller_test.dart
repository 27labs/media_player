import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/media/media_control_service.dart';
import 'package:media_player/media/media_controller.dart';

import 'fakes/fake_media_control_service.dart';
import 'fixtures.dart';

void main() {
  late FakeMediaControlService service;
  late MediaController controller;

  setUp(() {
    service = FakeMediaControlService();
    controller = MediaController(
      service,
      nowSinceEpoch: () => const Duration(seconds: 40),
    );
  });

  tearDown(() async {
    controller.dispose();
    await service.close();
  });

  test('publishes ready state and extrapolates the playing position', () async {
    service.emit(MediaSessionAvailable(mediaSnapshot()));
    await _flushEvents();

    expect(controller.status, MediaControllerStatus.ready);
    expect(controller.snapshot?.title, 'Night Drive');
    expect(controller.currentPosition, const Duration(seconds: 70));
  });

  test('ignores stale artwork when a newer session replaces it', () async {
    final oldArtwork = Completer<Uint8List?>();
    service.artwork[1] = oldArtwork.future;
    service.emit(
      MediaSessionAvailable(
        mediaSnapshot(revision: 1, artworkAvailable: true, artworkRevision: 1),
      ),
    );
    await _flushEvents();
    expect(controller.isArtworkLoading, isTrue);

    service.emit(
      MediaSessionAvailable(mediaSnapshot(revision: 2, title: 'New Track')),
    );
    await _flushEvents();
    oldArtwork.complete(Uint8List.fromList([1, 2, 3]));
    await _flushEvents();

    expect(controller.snapshot?.revision, 2);
    expect(controller.artwork, isNull);
    expect(controller.isArtworkLoading, isFalse);
  });

  test(
    'binds commands to the rendered session and ignores stale results',
    () async {
      service.emit(MediaSessionAvailable(mediaSnapshot(revision: 10)));
      await _flushEvents();
      final command = Completer<MediaCommandResult>();
      service.nextCommand = command;

      final pending = controller.next();
      await _flushEvents();
      expect(service.sentCommands.single.expectedRevision, 10);
      expect(controller.isCommandPending, isTrue);

      service.emit(
        MediaSessionAvailable(
          mediaSnapshot(revision: 11, title: 'Replacement'),
        ),
      );
      await _flushEvents();
      expect(controller.isCommandPending, isFalse);
      command.complete(const MediaCommandResult(accepted: false, revision: 10));
      await pending;

      expect(controller.actionMessage, isNull);
    },
  );

  test('surfaces a command rejection for the current session', () async {
    service.emit(MediaSessionAvailable(mediaSnapshot(revision: 4)));
    await _flushEvents();
    service.nextCommand = Completer<MediaCommandResult>()
      ..complete(const MediaCommandResult(accepted: false, revision: 4));

    await controller.previous();

    expect(controller.actionMessage, contains('rejected'));
  });

  test('normalizes seek bounds before sending the command', () async {
    service.emit(
      MediaSessionAvailable(
        mediaSnapshot(
          revision: 8,
          maximumSeek: Duration.zero,
          end: const Duration(minutes: 2),
        ),
      ),
    );
    await _flushEvents();

    await controller.seek(const Duration(minutes: 3));

    expect(service.sentCommands.single.position, const Duration(minutes: 2));
  });

  test('retries after a terminal integration error', () async {
    service.emit(
      const MediaSessionFailure(code: 'denied', message: 'Access denied.'),
    );
    await _flushEvents();
    expect(controller.status, MediaControllerStatus.error);

    await controller.retry();

    expect(controller.status, MediaControllerStatus.loading);
    expect(service.sentCommands.single.command, MediaCommand.retry);
    expect(service.sentCommands.single.expectedRevision, 0);
  });

  test('keeps the initializing event in a loading state', () async {
    service.emit(const MediaSessionUnavailable('initializing'));
    await _flushEvents();

    expect(controller.status, MediaControllerStatus.loading);
  });

  test(
    'loads artwork when native pending becomes ready at one revision',
    () async {
      service.artwork[6] = Future.value(Uint8List.fromList([1, 2, 3]));
      service.emit(
        MediaSessionAvailable(
          mediaSnapshot(
            revision: 3,
            artworkAvailable: false,
            artworkPending: true,
            artworkRevision: 6,
          ),
        ),
      );
      await _flushEvents();
      expect(controller.isArtworkLoading, isTrue);

      service.emit(
        MediaSessionAvailable(
          mediaSnapshot(
            revision: 3,
            artworkAvailable: true,
            artworkRevision: 6,
          ),
        ),
      );
      await _flushEvents();
      await _flushEvents();

      expect(controller.artwork, Uint8List.fromList([1, 2, 3]));
      expect(controller.isArtworkLoading, isFalse);
    },
  );

  test(
    'turns a stream disconnect into a reconnectable terminal error',
    () async {
      service.emit(MediaSessionAvailable(mediaSnapshot()));
      await _flushEvents();

      service.emitError(StateError('channel closed'));
      await _flushEvents();

      expect(controller.status, MediaControllerStatus.error);
      expect(controller.snapshot, isNull);
      expect(controller.errorMessage, contains('disconnected'));
    },
  );

  test('recovers when a platform command times out', () async {
    final shortController = MediaController(
      service,
      commandTimeout: const Duration(milliseconds: 10),
    );
    addTearDown(shortController.dispose);
    service.emit(MediaSessionAvailable(mediaSnapshot(revision: 12)));
    await _flushEvents();
    service.nextCommand = Completer<MediaCommandResult>();

    await shortController.next();

    expect(shortController.isCommandPending, isFalse);
    expect(shortController.actionMessage, contains('could not be sent'));
  });
}

Future<void> _flushEvents() => Future<void>.delayed(Duration.zero);
