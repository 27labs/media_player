import 'dart:typed_data';

import 'package:fluent_ui/fluent_ui.dart';

import '../media/media_controller.dart';
import '../media/media_session_snapshot.dart';
import 'playback_controls.dart';
import 'playback_timeline.dart';

class MediaPlayerView extends StatelessWidget {
  const MediaPlayerView({super.key, required this.controller});

  static const _ultraCompactWidth = 0.0;
  static const _ultraCompactHeight = 150.0;
  static const _compactWidth = 370.0;
  static const _compactHeight = 350.0;
  static const _largeWidth =
      // 600.0;
      400.0;
  static const _largeHeight =
      // 270.0;
      0.0;

  final MediaController controller;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final ultraCompact =
              constraints.maxWidth < _ultraCompactWidth ||
              constraints.maxHeight < _ultraCompactHeight;
          final compact =
              constraints.maxWidth < _compactWidth ||
              constraints.maxHeight < _compactHeight;
          final large =
              constraints.maxWidth >= _largeWidth &&
              constraints.maxHeight >= _largeHeight;
          return Padding(
            padding: EdgeInsets.all(13),
            child: _Surface(
              child: switch (controller.status) {
                MediaControllerStatus.loading => const _LoadingState(),
                MediaControllerStatus.unavailable => const _UnavailableState(),
                MediaControllerStatus.error => _ErrorState(
                  message:
                      controller.errorMessage ??
                      'Windows media controls are unavailable.',
                  onRetry: controller.retry,
                ),
                MediaControllerStatus.ready => _ReadyState(
                  controller: controller,
                  compact: compact,
                  ultraCompact: ultraCompact,
                  large: large,
                ),
              },
            ),
          );
        },
      ),
    );
  }
}

class _Surface extends StatelessWidget {
  const _Surface({required this.child});

  static const _darkTint = Color.fromARGB(0, 28, 28, 28);
  static const _lightTint = Color.fromARGB(0, 250, 250, 250);
  static const _darkBorder = Color.fromARGB(0, 255, 255, 255);
  static const _lightBorder = Color.fromARGB(0, 0, 0, 0);
  static const _surfaceRadius = BorderRadius.all(Radius.circular(12));

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark ? _darkTint : _lightTint,
        border: Border.all(color: isDark ? _darkBorder : _lightBorder),
        borderRadius: _surfaceRadius,
        boxShadow: const [
          BoxShadow(
            color: Color.fromARGB(0, 0, 0, 0),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(borderRadius: _surfaceRadius, child: child),
    );
  }
}

class _ReadyState extends StatelessWidget {
  const _ReadyState({
    required this.controller,
    required this.compact,
    required this.ultraCompact,
    required this.large,
  });

  final MediaController controller;
  final bool compact;
  final bool ultraCompact;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final snapshot = controller.snapshot!;
    final statusMessage = controller.errorMessage ?? controller.actionMessage;
    final backgroundArtworkOpacity = 0.13;
    if (ultraCompact) {
      return Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: backgroundArtworkOpacity,
              child: _Artwork(
                bytes: controller.artwork,
                loading: controller.isArtworkLoading,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(4),
            child: Center(
              child: Column(
                mainAxisAlignment: .center,
                spacing: 10,
                children: [
                  FittedBox(
                    child: _Metadata(
                      snapshot: snapshot,
                      compact: true,
                      minimal: true,
                    ),
                  ),
                  const SizedBox(width: 6),
                  PlaybackControls(controller: controller, compact: true),
                  if (statusMessage case final message?) ...[
                    const SizedBox(width: 6),
                    Semantics(
                      liveRegion: true,
                      child: Tooltip(
                        message: message,
                        excludeFromSemantics: true,
                        child: Icon(
                          controller.errorMessage == null
                              ? FluentIcons.warning
                              : FluentIcons.error,
                          size: 18,
                          semanticLabel: message,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      );
    }

    final content = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Metadata(snapshot: snapshot, compact: compact),
        SizedBox(height: compact ? 8 : 16),
        if (!compact) ...[
          PlaybackTimeline(controller: controller),
          const SizedBox(height: 12),
        ],
        Center(
          child: PlaybackControls(controller: controller, compact: compact),
        ),
        if (statusMessage case final message?) ...[
          const SizedBox(height: 10),
          if (compact)
            Semantics(
              liveRegion: true,
              child: Text(
                message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FluentTheme.of(context).typography.caption,
              ),
            )
          else
            Semantics(
              liveRegion: true,
              child: InfoBar(
                title: Text(message),
                severity: controller.errorMessage == null
                    ? InfoBarSeverity.warning
                    : InfoBarSeverity.error,
                onClose: controller.errorMessage == null
                    ? controller.dismissActionMessage
                    : controller.dismissErrorMessage,
              ),
            ),
        ],
      ],
    );

    return Stack(
      children: [
        Positioned.fill(
          child: Opacity(
            opacity: backgroundArtworkOpacity,
            child: _Artwork(
              bytes: controller.artwork,
              loading: controller.isArtworkLoading,
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.all(compact ? 14 : 22),
          child: large
              ? Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: _Artwork(
                        bytes: controller.artwork,
                        loading: controller.isArtworkLoading,
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(flex: 6, child: content),
                  ],
                )
              : content,
        ),
      ],
    );
  }
}

class _Metadata extends StatelessWidget {
  const _Metadata({
    required this.snapshot,
    required this.compact,
    this.minimal = false,
  });

  final MediaSessionSnapshot snapshot;
  final bool compact;
  final bool minimal;

  @override
  Widget build(BuildContext context) {
    final typography = FluentTheme.of(context).typography;
    final title = snapshot.title.trim().isEmpty
        ? 'Unknown title'
        : snapshot.title;
    final artist = snapshot.artist.trim().isEmpty
        ? 'Unknown artist'
        : snapshot.artist;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          title,
          textAlign: .center,
          key: const ValueKey('media-title'),
          maxLines: compact ? 1 : 2,
          overflow: TextOverflow.ellipsis,
          style: compact ? typography.subtitle : typography.title,
        ),
        if (!minimal) ...[
          const SizedBox(height: 3),
          Text(
            artist,
            textAlign: .center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: typography.body,
          ),
        ],
        if (!compact && snapshot.albumTitle.trim().isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            snapshot.albumTitle,
            textAlign: .center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: typography.caption,
          ),
        ],
        if (!compact && snapshot.sourceLabel.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            snapshot.sourceLabel,
            textAlign: .center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: typography.caption,
          ),
        ],
      ],
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.bytes, required this.loading});

  final Uint8List? bytes;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const ValueKey('artwork'),
      label: loading
          ? 'Loading album artwork'
          : bytes == null
          ? 'No album artwork'
          : 'Album artwork',
      image: true,
      child: AspectRatio(
        aspectRatio: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: FluentTheme.of(
              context,
            ).resources.cardBackgroundFillColorDefault,
            borderRadius: BorderRadius.circular(10),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: loading
                ? const Center(child: ExcludeSemantics(child: ProgressRing()))
                : bytes == null
                ? const Center(child: Icon(FluentIcons.music_note, size: 42))
                : Image.memory(
                    bytes!,
                    fit: BoxFit.cover,
                    cacheWidth: 1024,
                    cacheHeight: 1024,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => const Center(
                      child: Icon(FluentIcons.image_pixel, size: 42),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: const Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ProgressRing(),
              SizedBox(height: 10),
              Text(
                'Connecting to Windows media controls…',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnavailableState extends StatelessWidget {
  const _UnavailableState();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: const _CenteredMessage(
        icon: FluentIcons.music_note,
        title: 'Nothing is playing',
        message: 'Start media in an app that supports Windows media controls.',
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _CenteredMessage(
                icon: FluentIcons.error,
                title: 'Media controls unavailable',
                message: message,
              ),
              const SizedBox(height: 12),
              Button(onPressed: onRetry, child: const Text('Reconnect')),
            ],
          ),
        ),
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final typography = FluentTheme.of(context).typography;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: typography.subtitle,
            ),
            const SizedBox(height: 5),
            Text(message, textAlign: TextAlign.center, style: typography.body),
          ],
        ),
      ),
    );
  }
}
