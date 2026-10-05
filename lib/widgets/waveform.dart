import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Clean linear audio progress slider ("garis biasa aja")
/// with tactile seeking, neon lime accent, and clean timestamps.
class WaveformWidget extends StatefulWidget {
  final double progress;
  final String currentTime;
  final String totalTime;
  final ValueChanged<double>? onSeek;
  final Color activeColor;
  final Color inactiveColor;

  const WaveformWidget({
    super.key,
    required this.progress,
    required this.currentTime,
    required this.totalTime,
    this.onSeek,
    this.activeColor = const Color(0xFFD9F99D),
    this.inactiveColor = const Color(0x26FFFFFF),
  });

  @override
  State<WaveformWidget> createState() => _WaveformWidgetState();
}

class _WaveformWidgetState extends State<WaveformWidget> {
  bool _isDragging = false;
  double _dragProgress = 0.0;

  double get _currentProgress =>
      _isDragging ? _dragProgress : widget.progress.clamp(0.0, 1.0);

  void _updateSeek(Offset localPosition, double width) {
    if (width <= 0) return;
    final ratio = (localPosition.dx / width).clamp(0.0, 1.0);
    setState(() {
      _dragProgress = ratio;
    });
  }

  void _finalizeSeek() {
    if (widget.onSeek != null) {
      widget.onSeek!(_dragProgress);
    }
    setState(() {
      _isDragging = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final progress = _currentProgress;

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (details) {
                _isDragging = true;
                _updateSeek(details.localPosition, width);
              },
              onHorizontalDragUpdate: (details) {
                _updateSeek(details.localPosition, width);
              },
              onHorizontalDragEnd: (details) {
                _finalizeSeek();
              },
              onTapDown: (details) {
                _isDragging = true;
                _updateSeek(details.localPosition, width);
                _finalizeSeek();
              },
              child: Container(
                height: 28,
                alignment: Alignment.center,
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    // Inactive Track (Full Width Line)
                    Container(
                      height: 4.0,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: widget.inactiveColor,
                        borderRadius: BorderRadius.circular(2.0),
                      ),
                    ),
                    // Active Track Line (Lime)
                    FractionallySizedBox(
                      widthFactor: progress.clamp(0.0, 1.0),
                      child: Container(
                        height: 4.0,
                        decoration: BoxDecoration(
                          color: widget.activeColor,
                          borderRadius: BorderRadius.circular(2.0),
                          boxShadow: [
                            BoxShadow(
                              color: widget.activeColor.withValues(alpha: 0.4),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Thumb Knob
                    Positioned(
                      left: (width * progress - (_isDragging ? 7.0 : 6.0)).clamp(
                        0.0,
                        math.max(0.0, width - (_isDragging ? 14.0 : 12.0)),
                      ),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 100),
                        width: _isDragging ? 14.0 : 12.0,
                        height: _isDragging ? 14.0 : 12.0,
                        decoration: BoxDecoration(
                          color: widget.activeColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: widget.activeColor.withValues(alpha: 0.5),
                              blurRadius: _isDragging ? 8.0 : 5.0,
                              spreadRadius: _isDragging ? 2.0 : 1.0,
                            ),
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.currentTime,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                  letterSpacing: 0.2,
                  shadows: [
                    Shadow(
                      color: Color(0xD9000000),
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
              Text(
                widget.totalTime,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  letterSpacing: 0.2,
                  shadows: const [
                    Shadow(
                      color: Color(0xD9000000),
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
