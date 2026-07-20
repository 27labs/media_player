import 'dart:developer' as developer;
import 'dart:ui';

import 'package:flutter_acrylic/flutter_acrylic.dart';

class WindowBackdrop {
  const WindowBackdrop._();

  static Future<bool> initialize(Brightness brightness) async {
    try {
      await Window.initialize();
      await _apply(brightness);
      return true;
    } catch (error, stackTrace) {
      _logFailure('initialize', error, stackTrace);
      return false;
    }
  }

  static Future<void> refresh(Brightness brightness) async {
    try {
      await _apply(brightness);
    } catch (error, stackTrace) {
      _logFailure('refresh', error, stackTrace);
    }
  }

  static Future<void> _apply(Brightness brightness) {
    return Window.setEffect(
      effect: WindowEffect.acrylic,
      dark: brightness == Brightness.dark,
    );
  }

  static void _logFailure(
    String operation,
    Object error,
    StackTrace stackTrace,
  ) {
    final recovery = operation == 'initialize'
        ? 'using the opaque fallback'
        : 'keeping the previous backdrop';
    developer.log(
      'Windows backdrop $operation failed; $recovery.',
      name: 'media_player.window_backdrop',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
