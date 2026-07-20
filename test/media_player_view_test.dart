import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/app.dart';
import 'package:media_player/media/media_control_service.dart';

import 'fakes/fake_media_control_service.dart';
import 'fixtures.dart';

void main() {
  testWidgets('shows loading, unavailable, and reconnectable error states', (
    tester,
  ) async {
    final service = await _pumpApp(tester, const Size(520, 320));

    expect(find.text('Connecting to Windows media controls…'), findsOneWidget);

    service.emit(const MediaSessionUnavailable('no_session'));
    await tester.pump();
    expect(find.text('Nothing is playing'), findsOneWidget);

    service.emit(
      const MediaSessionFailure(code: 'denied', message: 'Access denied.'),
    );
    await tester.pump();
    expect(find.text('Media controls unavailable'), findsOneWidget);
    expect(find.text('Reconnect'), findsOneWidget);

    await tester.tap(find.text('Reconnect'));
    await tester.pump(const Duration(milliseconds: 150));
    expect(service.sentCommands.single.command, MediaCommand.retry);
    expect(find.text('Connecting to Windows media controls…'), findsOneWidget);
  });

  testWidgets('keeps compact layouts to metadata and controls', (tester) async {
    final service = await _pumpApp(tester, const Size(360, 220));
    service.emit(MediaSessionAvailable(mediaSnapshot()));
    await tester.pump();

    expect(find.byKey(const ValueKey('media-title')), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
    expect(find.byKey(const ValueKey('artwork')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the timeline and source at medium sizes', (tester) async {
    final service = await _pumpApp(tester, const Size(600, 400));
    service.emit(MediaSessionAvailable(mediaSnapshot()));
    await tester.pump();

    expect(find.byType(Slider), findsOneWidget);
    expect(find.text('Example Player'), findsOneWidget);
    expect(find.byKey(const ValueKey('artwork')), findsNothing);
  });

  testWidgets('adds artwork when enough width and height are available', (
    tester,
  ) async {
    final service = await _pumpApp(tester, const Size(800, 500));
    final artwork = Completer<Uint8List?>();
    service.artwork[4] = artwork.future;
    service.emit(
      MediaSessionAvailable(
        mediaSnapshot(artworkAvailable: true, artworkRevision: 4),
      ),
    );
    await tester.pump();

    expect(find.byType(Slider), findsOneWidget);
    expect(find.byKey(const ValueKey('artwork')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('artwork')),
        matching: find.byType(ProgressRing),
      ),
      findsOneWidget,
    );

    artwork.complete(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
        'AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('artwork')),
        matching: find.byType(Image),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('sends enabled controls and timeline gestures to the session', (
    tester,
  ) async {
    final service = await _pumpApp(tester, const Size(600, 400));
    service.emit(MediaSessionAvailable(mediaSnapshot(revision: 9)));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('next')));
    await tester.pump(const Duration(milliseconds: 150));
    expect(service.sentCommands.single.command, MediaCommand.next);
    expect(service.sentCommands.single.expectedRevision, 9);

    final slider = find.byType(Slider);
    final rect = tester.getRect(slider);
    await tester.tapAt(Offset(rect.left + rect.width * 0.75, rect.center.dy));
    await tester.pump(const Duration(milliseconds: 150));

    final seek = service.sentCommands.last;
    expect(seek.command, MediaCommand.seek);
    expect(seek.expectedRevision, 9);
    expect(seek.position, isNotNull);
    expect(seek.position!, greaterThan(const Duration(minutes: 1)));
  });

  testWidgets('shows a busy affordance while a command is pending', (
    tester,
  ) async {
    final service = await _pumpApp(tester, const Size(360, 220));
    service.emit(MediaSessionAvailable(mediaSnapshot(revision: 5)));
    await tester.pump();
    final command = Completer<MediaCommandResult>();
    service.nextCommand = command;

    await tester.tap(find.byKey(const ValueKey('play-pause')));
    await tester.pump();

    final playPause = find.byKey(const ValueKey('play-pause'));
    expect(
      find.descendant(of: playPause, matching: find.byType(ProgressRing)),
      findsOneWidget,
    );
    command.complete(const MediaCommandResult(accepted: true, revision: 5));
    await tester.pump(const Duration(milliseconds: 150));
    expect(
      find.descendant(of: playPause, matching: find.byType(ProgressRing)),
      findsNothing,
    );
  });

  testWidgets('scales down safely at widget-sized minimums', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final service = await _pumpApp(tester, const Size(280, 120));
    service.emit(MediaSessionAvailable(mediaSnapshot()));
    await tester.pump();

    expect(find.byKey(const ValueKey('media-title')), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('exposes unique control names and a merged timeline value', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final service = await _pumpApp(tester, const Size(600, 400));
    service.emit(MediaSessionAvailable(mediaSnapshot()));
    await tester.pump();

    expect(find.bySemanticsLabel('Previous'), findsOneWidget);
    expect(find.bySemanticsLabel('Pause'), findsOneWidget);
    expect(find.bySemanticsLabel('Next'), findsOneWidget);
    expect(find.bySemanticsLabel('Playback position'), findsOneWidget);
    final timeline = tester.getSemantics(
      find.bySemanticsLabel('Playback position'),
    );
    expect(timeline.value, contains('of 03:00'));
    semantics.dispose();
  });

  testWidgets('disables controls that the active session cannot handle', (
    tester,
  ) async {
    final service = await _pumpApp(tester, const Size(360, 220));
    service.emit(
      MediaSessionAvailable(
        mediaSnapshot(
          canPlay: false,
          canPause: false,
          canToggle: false,
          canPrevious: false,
          canNext: false,
          canSeek: false,
        ),
      ),
    );
    await tester.pump();

    final playPause = find.descendant(
      of: find.byKey(const ValueKey('play-pause')),
      matching: find.byType(FilledButton),
    );
    expect(tester.widget<FilledButton>(playPause).onPressed, isNull);
    await tester.tap(playPause);
    await tester.pump();
    expect(service.sentCommands, isEmpty);
  });
}

Future<FakeMediaControlService> _pumpApp(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  final service = FakeMediaControlService();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await service.close();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
  await tester.pumpWidget(
    MediaPlayerApp(service: service, transparencyEnabled: false),
  );
  return service;
}
