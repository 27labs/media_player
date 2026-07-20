import 'package:fluent_ui/fluent_ui.dart';

import '../media/media_controller.dart';

class PlaybackControls extends StatelessWidget {
  const PlaybackControls({
    super.key,
    required this.controller,
    this.compact = false,
  });

  final MediaController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final snapshot = controller.snapshot;
    final capabilities = snapshot?.capabilities;
    final isPlaying = snapshot?.isPlaying == true;
    final canPlayPause =
        capabilities?.canToggle == true ||
        (isPlaying
            ? capabilities?.canPause == true
            : capabilities?.canPlay == true);
    final iconSize = compact ? 18.0 : 22.0;
    final commandPending = controller.isCommandPending;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ControlButton(
          key: const ValueKey('previous'),
          tooltip: 'Previous',
          icon: FluentIcons.previous,
          iconSize: iconSize,
          enabled: capabilities?.canPrevious == true && !commandPending,
          onPressed: controller.previous,
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 8),
          child: _ControlButton(
            key: const ValueKey('play-pause'),
            tooltip: isPlaying ? 'Pause' : 'Play',
            icon: isPlaying ? FluentIcons.pause : FluentIcons.play,
            iconSize: compact ? 22 : 28,
            emphasized: true,
            enabled: canPlayPause && !commandPending,
            onPressed: controller.playPause,
            pending: commandPending,
          ),
        ),
        _ControlButton(
          key: const ValueKey('next'),
          tooltip: 'Next',
          icon: FluentIcons.next,
          iconSize: iconSize,
          enabled: capabilities?.canNext == true && !commandPending,
          onPressed: controller.next,
        ),
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.iconSize,
    required this.enabled,
    required this.onPressed,
    this.emphasized = false,
    this.pending = false,
  });

  final String tooltip;
  final IconData icon;
  final double iconSize;
  final bool enabled;
  final VoidCallback onPressed;
  final bool emphasized;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final button = emphasized
        ? FilledButton(
            onPressed: enabled ? onPressed : null,
            child: pending
                ? SizedBox.square(
                    dimension: iconSize,
                    child: const ProgressRing(strokeWidth: 2),
                  )
                : Icon(icon, size: iconSize, semanticLabel: tooltip),
          )
        : IconButton(
            onPressed: enabled ? onPressed : null,
            icon: Icon(icon, size: iconSize, semanticLabel: tooltip),
          );
    return Tooltip(message: tooltip, excludeFromSemantics: true, child: button);
  }
}
