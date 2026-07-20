import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';

import 'media/media_control_service.dart';
import 'media/media_controller.dart';
import 'player/media_player_view.dart';

class MediaPlayerApp extends StatefulWidget {
  const MediaPlayerApp({
    super.key,
    this.service = const PlatformMediaControlService(),
    this.transparencyEnabled = true,
    this.onBrightnessChanged,
  });

  final MediaControlService service;
  final bool transparencyEnabled;
  final Future<void> Function(Brightness brightness)? onBrightnessChanged;

  @override
  State<MediaPlayerApp> createState() => _MediaPlayerAppState();
}

class _MediaPlayerAppState extends State<MediaPlayerApp>
    with WidgetsBindingObserver {
  late final MediaController _controller = MediaController(widget.service);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    final callback = widget.onBrightnessChanged;
    if (callback != null) {
      unawaited(
        callback(WidgetsBinding.instance.platformDispatcher.platformBrightness),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FluentApp(
      title: 'Media controls',
      debugShowCheckedModeBanner: false,
      color: widget.transparencyEnabled ? Colors.transparent : null,
      themeMode: ThemeMode.system,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => MediaPlayerView(controller: _controller),
      ),
    );
  }

  FluentThemeData _theme(Brightness brightness) {
    return FluentThemeData(
      brightness: brightness,
      accentColor: Colors.green,
      scaffoldBackgroundColor: widget.transparencyEnabled
          ? Colors.transparent
          : null,
      micaBackgroundColor: widget.transparencyEnabled
          ? Colors.transparent
          : null,
    );
  }
}
