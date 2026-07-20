import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/media/media_control_service.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('media_controls/commands');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('sends the expected session revision with seek commands', () async {
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          received = call;
          return <String, Object?>{'accepted': true, 'revision': 12};
        });
    const service = PlatformMediaControlService();

    final result = await service.send(
      MediaCommand.seek,
      expectedRevision: 12,
      position: const Duration(seconds: 45),
    );

    expect(received?.method, 'seek');
    expect(received?.arguments, <String, Object?>{
      'expectedRevision': 12,
      'positionMs': 45000,
    });
    expect(result.accepted, isTrue);
    expect(result.revision, 12);
  });

  test('decodes snapshot, unavailable, error, and malformed events', () async {
    const events = EventChannel('media_controls/events');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          events,
          MockStreamHandler.inline(
            onListen: (_, sink) {
              sink.success(platformSnapshotMap());
              sink.success({'type': 'unavailable', 'reason': 'no_session'});
              sink.success({
                'type': 'error',
                'code': 'denied',
                'message': 'Access denied.',
              });
              sink.success({'type': 'snapshot', 'revision': 'bad'});
              sink.success({'type': 'surprise'});
              sink.endOfStream();
            },
          ),
        );
    const service = PlatformMediaControlService();

    final received = await service.events.toList();

    expect(received[0], isA<MediaSessionAvailable>());
    expect((received[1] as MediaSessionUnavailable).reason, 'no_session');
    expect((received[2] as MediaSessionFailure).code, 'denied');
    expect((received[3] as MediaSessionFailure).code, 'invalid_event');
    expect((received[4] as MediaSessionFailure).code, 'unknown_event');
  });
}
