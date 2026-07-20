import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'window_backdrop.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    backgroundColor: Color.fromRGBO(0, 0, 0, 0),
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );
  await windowManager.waitUntilReadyToShow(windowOptions);

  final transparencyEnabled = await WindowBackdrop.initialize(
    PlatformDispatcher.instance.platformBrightness,
  );

  runApp(
    MediaPlayerApp(
      transparencyEnabled: transparencyEnabled,
      onBrightnessChanged: transparencyEnabled ? WindowBackdrop.refresh : null,
    ),
  );
}
