import 'dart:async';

import 'package:flutter/foundation.dart';

import 'media_control_service.dart';
import 'media_session_snapshot.dart';

enum MediaControllerStatus { loading, ready, unavailable, error }

class MediaController extends ChangeNotifier {
  MediaController(
    this._service, {
    Duration Function()? nowSinceEpoch,
    this._commandTimeout = const Duration(seconds: 8),
  }) : _nowSinceEpoch =
           nowSinceEpoch ??
           (() =>
               Duration(milliseconds: DateTime.now().millisecondsSinceEpoch)) {
    _subscription = _service.events.listen(
      _handleEvent,
      onError: (Object error, StackTrace stackTrace) {
        _handleStreamError();
      },
    );
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_snapshot?.isPlaying == true && !_disposed) {
        _positionTick.value++;
      }
    });
  }

  final MediaControlService _service;
  final Duration _commandTimeout;
  final Duration Function() _nowSinceEpoch;
  late final StreamSubscription<MediaSessionEvent> _subscription;
  late final Timer _ticker;
  final ValueNotifier<int> _positionTick = ValueNotifier(0);

  MediaControllerStatus _status = MediaControllerStatus.loading;
  MediaSessionSnapshot? _snapshot;
  Uint8List? _artwork;
  int? _loadedArtworkRevision;
  int? _loadingArtworkRevision;
  int _artworkRequestGeneration = 0;
  bool _isArtworkLoading = false;
  int? _pendingCommandRevision;
  String? _errorMessage;
  String? _actionMessage;
  bool _disposed = false;

  MediaControllerStatus get status => _status;
  MediaSessionSnapshot? get snapshot => _snapshot;
  Uint8List? get artwork => _artwork;
  bool get isArtworkLoading => _isArtworkLoading;
  bool get isCommandPending =>
      _pendingCommandRevision != null &&
      _pendingCommandRevision == _snapshot?.revision;
  String? get errorMessage => _errorMessage;
  String? get actionMessage => _actionMessage;
  ValueListenable<int> get positionTick => _positionTick;

  Duration get currentPosition {
    final current = _snapshot;
    if (current == null) {
      return Duration.zero;
    }
    return current.timeline.estimatedPosition(
      nowSinceEpoch: _nowSinceEpoch(),
      isPlaying: current.isPlaying,
    );
  }

  Future<void> playPause() async {
    final current = _snapshot;
    if (current == null) {
      return;
    }
    final capabilities = current.capabilities;
    final command = capabilities.canToggle
        ? MediaCommand.playPause
        : current.isPlaying && capabilities.canPause
        ? MediaCommand.pause
        : MediaCommand.play;
    await _sendCommand(command);
  }

  Future<void> previous() => _sendCommand(MediaCommand.previous);

  Future<void> next() => _sendCommand(MediaCommand.next);

  Future<void> seek(Duration position) {
    final current = _snapshot;
    if (current == null || !current.capabilities.canSeek) {
      return Future<void>.value();
    }
    return _sendCommand(
      MediaCommand.seek,
      position: current.timeline.clampSeekPosition(position),
    );
  }

  Future<void> retry() async {
    _status = MediaControllerStatus.loading;
    _errorMessage = null;
    notifyListeners();
    try {
      await _service
          .send(MediaCommand.retry, expectedRevision: _snapshot?.revision ?? 0)
          .timeout(_commandTimeout);
    } catch (_) {
      _setFailure('Windows media controls could not reconnect.');
      notifyListeners();
    }
  }

  void dismissActionMessage() {
    if (_actionMessage == null) {
      return;
    }
    _actionMessage = null;
    notifyListeners();
  }

  void dismissErrorMessage() {
    if (_errorMessage == null) {
      return;
    }
    _errorMessage = null;
    notifyListeners();
  }

  void _handleEvent(MediaSessionEvent event) {
    switch (event) {
      case MediaSessionAvailable(:final snapshot):
        _snapshot = snapshot;
        _status = MediaControllerStatus.ready;
        _errorMessage = null;
        _actionMessage = null;
        _refreshArtwork(snapshot);
      case MediaSessionUnavailable(:final reason):
        ++_artworkRequestGeneration;
        _snapshot = null;
        _artwork = null;
        _loadedArtworkRevision = null;
        _loadingArtworkRevision = null;
        _isArtworkLoading = false;
        _status = reason == 'initializing'
            ? MediaControllerStatus.loading
            : MediaControllerStatus.unavailable;
        _errorMessage = null;
        _actionMessage = null;
      case MediaSessionFailure(:final message):
        _setFailure(message);
    }
    notifyListeners();
  }

  Future<void> _refreshArtwork(MediaSessionSnapshot snapshot) async {
    final revision = snapshot.artworkRevision;
    if (snapshot.artworkPending) {
      ++_artworkRequestGeneration;
      _artwork = null;
      _loadedArtworkRevision = null;
      _loadingArtworkRevision = null;
      _isArtworkLoading = true;
      return;
    }
    if (!snapshot.artworkAvailable || revision == null) {
      ++_artworkRequestGeneration;
      _artwork = null;
      _loadedArtworkRevision = null;
      _loadingArtworkRevision = null;
      _isArtworkLoading = false;
      return;
    }
    if (_loadedArtworkRevision == revision ||
        _loadingArtworkRevision == revision) {
      return;
    }

    final requestGeneration = ++_artworkRequestGeneration;
    _loadingArtworkRevision = revision;
    _isArtworkLoading = true;
    try {
      final bytes = await _service.loadArtwork(revision);
      if (_snapshot?.artworkRevision != revision ||
          requestGeneration != _artworkRequestGeneration ||
          _disposed) {
        return;
      }
      _artwork = bytes;
      _loadedArtworkRevision = revision;
    } catch (_) {
      if (_snapshot?.artworkRevision == revision &&
          requestGeneration == _artworkRequestGeneration) {
        _artwork = null;
        _loadedArtworkRevision = revision;
        _actionMessage = 'Album artwork could not be loaded.';
      }
    } finally {
      if (requestGeneration == _artworkRequestGeneration) {
        _loadingArtworkRevision = null;
        _isArtworkLoading = false;
      }
      if (!_disposed && requestGeneration == _artworkRequestGeneration) {
        notifyListeners();
      }
    }
  }

  Future<void> _sendCommand(MediaCommand command, {Duration? position}) async {
    final initiatingRevision = _snapshot?.revision;
    if (initiatingRevision == null || isCommandPending) {
      return;
    }
    _pendingCommandRevision = initiatingRevision;
    _actionMessage = null;
    notifyListeners();
    try {
      final result = await _service
          .send(
            command,
            expectedRevision: initiatingRevision,
            position: position,
          )
          .timeout(_commandTimeout);
      if (_snapshot?.revision != initiatingRevision ||
          result.revision != initiatingRevision) {
        return;
      }
      if (!result.accepted) {
        _actionMessage = 'The current media source rejected that command.';
      }
    } catch (_) {
      if (_snapshot?.revision == initiatingRevision) {
        _actionMessage = 'The command could not be sent to Windows.';
      }
    } finally {
      if (_pendingCommandRevision == initiatingRevision) {
        _pendingCommandRevision = null;
      }
      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  void _setFailure(String message) {
    _errorMessage = message;
    _status = _snapshot == null
        ? MediaControllerStatus.error
        : MediaControllerStatus.ready;
  }

  void _handleStreamError() {
    ++_artworkRequestGeneration;
    _snapshot = null;
    _artwork = null;
    _loadedArtworkRevision = null;
    _loadingArtworkRevision = null;
    _isArtworkLoading = false;
    _pendingCommandRevision = null;
    _errorMessage = 'Windows media controls disconnected.';
    _actionMessage = null;
    _status = MediaControllerStatus.error;
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker.cancel();
    _subscription.cancel();
    _positionTick.dispose();
    super.dispose();
  }
}
