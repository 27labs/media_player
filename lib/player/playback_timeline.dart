import 'package:fluent_ui/fluent_ui.dart';

import '../media/media_controller.dart';

class PlaybackTimeline extends StatefulWidget {
  const PlaybackTimeline({super.key, required this.controller});

  final MediaController controller;

  @override
  State<PlaybackTimeline> createState() => _PlaybackTimelineState();
}

class _PlaybackTimelineState extends State<PlaybackTimeline> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: widget.controller.positionTick,
      builder: (context, _, _) => _buildTimeline(context),
    );
  }

  Widget _buildTimeline(BuildContext context) {
    final snapshot = widget.controller.snapshot;
    if (snapshot == null || !snapshot.timeline.hasDuration) {
      return const SizedBox.shrink();
    }
    final timeline = snapshot.timeline;
    final minimum = timeline.minimumSeek.inMilliseconds.toDouble();
    final maximum = timeline.effectiveMaximumSeek.inMilliseconds.toDouble();
    if (maximum <= minimum) {
      return const SizedBox.shrink();
    }
    final current =
        (_dragValue ?? widget.controller.currentPosition.inMilliseconds)
            .clamp(minimum, maximum)
            .toDouble();
    final canSeek =
        snapshot.capabilities.canSeek && !widget.controller.isCommandPending;

    return MergeSemantics(
      child: Semantics(
        label: 'Playback position',
        value:
            '${_formatDuration(Duration(milliseconds: current.round()))} '
            'of ${_formatDuration(timeline.end)}',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Slider(
              value: current,
              min: minimum,
              max: maximum,
              onChanged: canSeek
                  ? (value) => setState(() => _dragValue = value)
                  : null,
              onChangeEnd: canSeek
                  ? (value) {
                      setState(() => _dragValue = null);
                      widget.controller.seek(
                        Duration(milliseconds: value.round()),
                      );
                    }
                  : null,
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ExcludeSemantics(
                  child: Text(
                    _formatDuration(Duration(milliseconds: current.round())),
                    style: FluentTheme.of(context).typography.caption,
                  ),
                ),
                ExcludeSemantics(
                  child: Text(
                    _formatDuration(timeline.end),
                    style: FluentTheme.of(context).typography.caption,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}
