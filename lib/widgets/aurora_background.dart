import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Ambient cosmic moving aurora background with interconnected, seamless fluid gradients.
/// Never resets or snaps; flows continuously with intertwined undulating ribbons.
class AuroraBackgroundWidget extends StatefulWidget {
  final Widget child;

  const AuroraBackgroundWidget({
    super.key,
    required this.child,
  });

  @override
  State<AuroraBackgroundWidget> createState() => _AuroraBackgroundWidgetState();
}

class _AuroraBackgroundWidgetState extends State<AuroraBackgroundWidget>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _time = 0.0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      if (mounted) {
        setState(() {
          _time = elapsed.inMicroseconds / 1000000.0;
        });
      }
    });

    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _time;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Deep Cosmic Charcoal Base
        const ColoredBox(color: Color(0xFF12131A)),

        // 2. Continuous Interconnected Aurora Mesh & Ribbons
        CustomPaint(
          painter: _SeamlessAuroraPainter(time: t),
        ),

        // 3. Subtle dark overlay to deepen the aurora
        ColoredBox(color: const Color(0xFF12131A).withValues(alpha: 0.22)),

        // 4. Foreground Content
        widget.child,
      ],
    );
  }
}

class _SeamlessAuroraPainter extends CustomPainter {
  final double time;

  const _SeamlessAuroraPainter({required this.time});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final t = time;

    // Smooth continuous coordinates without periodic resets
    // Ribbon 1: Upper cosmic lime & cyan wave
    final x1 = size.width * (0.30 + 0.16 * math.sin(t * 0.28));
    final y1 = size.height * (0.22 + 0.10 * math.cos(t * 0.22));
    final r1 = size.width * 0.55;

    // Ribbon 2: Center azure & indigo deep stream
    final x2 = size.width * (0.72 + 0.15 * math.cos(t * 0.24));
    final y2 = size.height * (0.42 + 0.12 * math.sin(t * 0.32));
    final r2 = size.width * 0.60;

    // Ribbon 3: Bottom-left emerald & teal glow
    final x3 = size.width * (0.28 + 0.18 * math.sin(t * 0.20 + 1.6));
    final y3 = size.height * (0.68 + 0.11 * math.cos(t * 0.26 + 1.0));
    final r3 = size.width * 0.58;

    // Ribbon 4: Bottom-right cosmic violet & azure flow
    final x4 = size.width * (0.75 + 0.14 * math.cos(t * 0.30 + 2.2));
    final y4 = size.height * (0.78 + 0.10 * math.sin(t * 0.25 + 1.8));
    final r4 = size.width * 0.52;

    // Draw intertwined gradient blobs that overlap continuously
    _drawGlow(canvas, Offset(x1, y1), r1, const Color(0xFF84CC16), 0.26); // Lime
    _drawGlow(canvas, Offset(x2, y2), r2, const Color(0xFF0284C7), 0.28); // Azure
    _drawGlow(canvas, Offset(x3, y3), r3, const Color(0xFF10B981), 0.22); // Emerald
    _drawGlow(canvas, Offset(x4, y4), r4, const Color(0xFF6366F1), 0.24); // Indigo

    // Flowing interconnected sinusoidal aurora curtain across center
    final curtainPath = Path();
    final curtainY = size.height * (0.35 + 0.08 * math.sin(t * 0.35));
    curtainPath.moveTo(0, curtainY);

    for (double x = 0; x <= size.width; x += 20) {
      final y = curtainY +
          28 * math.sin((x / size.width) * 2 * math.pi + t * 0.45) +
          14 * math.cos((x / size.width) * 4 * math.pi - t * 0.30);
      curtainPath.lineTo(x, y);
    }
    curtainPath.lineTo(size.width, size.height);
    curtainPath.lineTo(0, size.height);
    curtainPath.close();

    final curtainPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFF84CC16).withValues(alpha: 0.12),
          const Color(0xFF06B6D4).withValues(alpha: 0.15),
          const Color(0xFF3B82F6).withValues(alpha: 0.14),
          const Color(0xFF8B5CF6).withValues(alpha: 0.10),
          Colors.transparent,
        ],
        stops: const [0.0, 0.30, 0.60, 0.85, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawPath(curtainPath, curtainPaint);
  }

  void _drawGlow(Canvas canvas, Offset center, double radius, Color color, double alpha) {
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: alpha),
          color.withValues(alpha: alpha * 0.5),
          Colors.transparent,
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _SeamlessAuroraPainter oldDelegate) {
    return oldDelegate.time != time;
  }
}
