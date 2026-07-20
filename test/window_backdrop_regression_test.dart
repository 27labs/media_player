import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_acrylic/window_effect.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/main.dart' as app;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const windowManagerChannel = MethodChannel('window_manager');
  const acrylicChannel = MethodChannel('com.alexmercerind/flutter_acrylic');
  const mediaEvents = EventChannel('media_controls/events');

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(windowManagerChannel, null);
    messenger.setMockMethodCallHandler(acrylicChannel, null);
    messenger.setMockStreamHandler(mediaEvents, null);
  });

  testWidgets('startup uses Acrylic without window-manager activation', (
    tester,
  ) async {
    MethodCall? effectCall;
    final windowManagerCalls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowManagerChannel, (call) async {
          windowManagerCalls.add(call.method);
          return switch (call.method) {
            'isFullScreen' || 'isMaximized' || 'isMinimized' => false,
            _ => null,
          };
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(acrylicChannel, (call) async {
          if (call.method == 'SetEffect') {
            effectCall = call;
          }
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          mediaEvents,
          MockStreamHandler.inline(onListen: (_, _) {}),
        );

    await app.main();
    await tester.pump();

    expect(effectCall?.method, 'SetEffect');
    expect(
      (effectCall?.arguments as Map<Object?, Object?>)['effect'],
      WindowEffect.acrylic.index,
    );
    expect(windowManagerCalls, isNot(contains('focus')));
    expect(windowManagerCalls, isNot(contains('show')));

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
