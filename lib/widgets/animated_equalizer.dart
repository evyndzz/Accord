import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Animated vertical bar equalizer that jumps up and down rhythmically.
/// Used over dimmed album art cards when a song is playing.
class AnimatedEqualizer extends StatefulWidget {
  final Color color;
  final double maxHeight;
  final double minHeight;
  final double barWidth;
  final double barSpacing;
  final int barCount;

  const AnimatedEqualizer({
    super.key,
    this.color = const Color(0xFFD9F99D),
    this.maxHeight = 18.0,
    this.minHeight = 4.0,
    this.barWidth = 3.2,
    this.barSpacing = 2.5,
    this.barCount = 4,
  });

  @override
  State<AnimatedEqualizer> createState() => _AnimatedEqualizerState();
}

class _AnimatedEqualizerState extends State<AnimatedEqualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value * 2 * math.pi;

        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(widget.barCount, (index) {
            // Distinct phase shift and frequency multiplier for each bar
            final phase = index * (math.pi / (widget.barCount * 0.75));
            final freq = (index % 2 == 0) ? 1.0 : 1.4;
            
            // Generate rhythmic oscillation between 0.0 and 1.0
            final rawSine = (math.sin(t * freq + phase) + 1.0) / 2.0;
            // Add subtle secondary harmonic for organic audio-wave feel
            final secondary = (math.sin(t * 2.2 + index) + 1.0) / 4.0;
            final normalized = (rawSine * 0.75 + secondary * 0.25).clamp(0.0, 1.0);

            final barHeight = widget.minHeight +
                (widget.maxHeight - widget.minHeight) * normalized;

            return Container(
              margin: EdgeInsets.symmetric(horizontal: widget.barSpacing / 2),
              width: widget.barWidth,
              height: barHeight,
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(widget.barWidth / 2),
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.4),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            );
          }),
        );
      },
    );
  }
}
