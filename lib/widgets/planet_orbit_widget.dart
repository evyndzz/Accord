import 'dart:math' as math;
import 'package:flutter/material.dart';

class PlanetOrbitWidget extends StatefulWidget {
  final double size;
  const PlanetOrbitWidget({super.key, this.size = 280});

  @override
  State<PlanetOrbitWidget> createState() => _PlanetOrbitWidgetState();
}

class _PlanetOrbitWidgetState extends State<PlanetOrbitWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 40),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            size: Size(widget.size, widget.size),
            painter: _PlanetOrbitPainter(
              orbitAngle: _controller.value * 2 * math.pi,
            ),
          );
        },
      ),
    );
  }
}

class _PlanetOrbitPainter extends CustomPainter {
  final double orbitAngle;

  _PlanetOrbitPainter({required this.orbitAngle});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    // 1. Draw subtle ambient space glow behind center
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF60A5FA).withValues(alpha: 0.12),
          const Color(0xFF10B981).withValues(alpha: 0.05),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: maxRadius * 0.9));
    canvas.drawCircle(center, maxRadius * 0.9, glowPaint);

    // 2. Draw Dotted Orbit Rings
    _drawDottedCircle(canvas, center, maxRadius * 0.88, 70);
    _drawDottedCircle(canvas, center, maxRadius * 0.65, 52);

    // 3. Draw Sparkle Stars (+ and x)
    _drawSparkleCross(canvas, Offset(size.width * 0.25, size.height * 0.74), 7, const Color(0xFFFDE68A));
    _drawSparkleX(canvas, Offset(size.width * 0.52, size.height * 0.11), 6, const Color(0xFF93C5FD));
    _drawMicroStar(canvas, Offset(size.width * 0.78, size.height * 0.78), 2, Colors.white60);
    _drawMicroStar(canvas, Offset(size.width * 0.16, size.height * 0.38), 1.5, Colors.white54);
    _drawMicroStar(canvas, Offset(size.width * 0.82, size.height * 0.26), 2, Colors.white70);

    // 4. Draw Orbiting Moons / Planets (Subtle slow orbital motion)
    // Planet A: Lime-yellow cratered moon
    final planetAAngle = -0.75 + math.sin(orbitAngle * 0.5) * 0.15;
    final planetARadius = maxRadius * 0.65;
    final planetACenter = Offset(
      center.dx + planetARadius * math.cos(planetAAngle),
      center.dy + planetARadius * math.sin(planetAAngle),
    );
    _drawCrateredMoon(canvas, planetACenter, 19);

    // Planet B: Coral-striped mini planet
    final planetBAngle = -0.22 + math.cos(orbitAngle * 0.5) * 0.12;
    final planetBRadius = maxRadius * 0.88;
    final planetBCenter = Offset(
      center.dx + planetBRadius * math.cos(planetBAngle),
      center.dy + planetBRadius * math.sin(planetBAngle),
    );
    _drawStripedMiniPlanet(canvas, planetBCenter, 13);

    // 5. Draw Central Striped Pixel Planet
    _drawPixelStripedPlanet(canvas, center, 48);
  }

  void _drawDottedCircle(Canvas canvas, Offset center, double radius, int dotCount) {
    final dotPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final path = Path();
    for (int i = 0; i < dotCount; i++) {
      final a1 = (i * 2 * math.pi) / dotCount;
      final a2 = a1 + (math.pi / dotCount * 0.5);
      path.moveTo(center.dx + radius * math.cos(a1), center.dy + radius * math.sin(a1));
      path.lineTo(center.dx + radius * math.cos(a2), center.dy + radius * math.sin(a2));
    }
    canvas.drawPath(path, dotPaint);
  }

  void _drawSparkleCross(Canvas canvas, Offset pos, double size, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.square;
    canvas.drawLine(Offset(pos.dx - size, pos.dy), Offset(pos.dx + size, pos.dy), paint);
    canvas.drawLine(Offset(pos.dx, pos.dy - size), Offset(pos.dx, pos.dy + size), paint);
  }

  void _drawSparkleX(Canvas canvas, Offset pos, double size, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.square;
    final d = size * 0.707;
    canvas.drawLine(Offset(pos.dx - d, pos.dy - d), Offset(pos.dx + d, pos.dy + d), paint);
    canvas.drawLine(Offset(pos.dx + d, pos.dy - d), Offset(pos.dx - d, pos.dy + d), paint);
  }

  void _drawMicroStar(Canvas canvas, Offset pos, double radius, Color color) {
    final paint = Paint()..color = color;
    canvas.drawCircle(pos, radius, paint);
  }

  void _drawCrateredMoon(Canvas canvas, Offset center, double radius) {
    // Base body: Lime yellow
    final basePaint = Paint()..color = const Color(0xFFD9F99D);
    canvas.drawCircle(center, radius, basePaint);

    // Pixelated black outline
    final outlinePaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    canvas.drawCircle(center, radius, outlinePaint);

    // Craters
    final craterPaint = Paint()..color = const Color(0xFF0F172A);
    canvas.drawCircle(Offset(center.dx - 6, center.dy - 3), 2.5, craterPaint);
    canvas.drawCircle(Offset(center.dx + 4, center.dy - 5), 2.0, craterPaint);
    canvas.drawCircle(Offset(center.dx - 2, center.dy + 5), 3.0, craterPaint);
    canvas.drawCircle(Offset(center.dx + 6, center.dy + 4), 2.2, craterPaint);
    canvas.drawCircle(Offset(center.dx - 9, center.dy + 4), 1.8, craterPaint);
  }

  void _drawStripedMiniPlanet(Canvas canvas, Offset center, double radius) {
    canvas.save();
    final path = Path()..addOval(Rect.fromCircle(center: center, radius: radius));
    canvas.clipPath(path);

    // Background coral
    final bgPaint = Paint()..color = const Color(0xFFFB7185);
    canvas.drawPaint(bgPaint);

    // Horizontal stripes: light pink & cream
    final stripe1 = Paint()..color = const Color(0xFFFEE2E2);
    final stripe2 = Paint()..color = const Color(0xFFE11D48);

    canvas.drawRect(Rect.fromLTWH(center.dx - radius, center.dy - 6, radius * 2, 3), stripe1);
    canvas.drawRect(Rect.fromLTWH(center.dx - radius, center.dy + 1, radius * 2, 3.5), stripe2);
    canvas.drawRect(Rect.fromLTWH(center.dx - radius, center.dy + 7, radius * 2, 2.5), stripe1);

    canvas.restore();

    // Outline
    final outlinePaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    canvas.drawCircle(center, radius, outlinePaint);
  }

  void _drawPixelStripedPlanet(Canvas canvas, Offset center, double radius) {
    canvas.save();

    // Circular clip with pixel border aesthetic
    final clipPath = Path()..addOval(Rect.fromCircle(center: center, radius: radius));
    canvas.clipPath(clipPath);

    // Color bands from reference:
    // Light sky blue (#93C5FD), Sage mint green (#A7F3D0), Lavender blue (#BFDBFE), Deep sapphire (#1E3A8A)
    final colors = [
      const Color(0xFF93C5FD), // light blue
      const Color(0xFF60A5FA), // sky blue
      const Color(0xFFA7F3D0), // sage green
      const Color(0xFF34D399), // mint green
      const Color(0xFF93C5FD), // light blue
      const Color(0xFFA7F3D0), // sage green
      const Color(0xFF6EE7B7), // green accent
      const Color(0xFF60A5FA), // sky blue
      const Color(0xFF3B82F6), // royal blue
    ];

    final bandHeight = (radius * 2) / colors.length;
    final startY = center.dy - radius;

    for (int i = 0; i < colors.length; i++) {
      final p = Paint()..color = colors[i];
      final y = startY + i * bandHeight;
      canvas.drawRect(
        Rect.fromLTWH(center.dx - radius - 5, y, radius * 2 + 10, bandHeight + 0.8),
        p,
      );

      // Add retro pixel shading notches across the stripe boundary
      if (i % 2 == 1) {
        final darkPixelPaint = Paint()..color = const Color(0xFF1E3A8A).withValues(alpha: 0.35);
        canvas.drawRect(
          Rect.fromLTWH(center.dx - radius + (i * 7) % 30, y, 14, bandHeight * 0.4),
          darkPixelPaint,
        );
      }
    }

    canvas.restore();

    // Pixelated black outline around the planet
    final borderPaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;
    canvas.drawCircle(center, radius, borderPaint);

    // Outer subtle cyan rim glow
    final rimPaint = Paint()
      ..color = const Color(0xFF93C5FD).withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, radius + 2.0, rimPaint);
  }

  @override
  bool shouldRepaint(covariant _PlanetOrbitPainter oldDelegate) {
    return oldDelegate.orbitAngle != orbitAngle;
  }
}
