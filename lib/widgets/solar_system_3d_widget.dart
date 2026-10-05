import 'dart:math' as math;
import 'package:flutter/material.dart';

class _PlanetConfig {
  final String name;
  final String assetPath;
  final double radiusRatio;
  final double baseSize;
  final double orbitalSpeed;
  final double initialAngle;
  final Color orbitColor;

  const _PlanetConfig({
    required this.name,
    required this.assetPath,
    required this.radiusRatio,
    required this.baseSize,
    required this.orbitalSpeed,
    required this.initialAngle,
    required this.orbitColor,
  });
}

class SolarSystem3DWidget extends StatefulWidget {
  final double? height;
  final double scrollOffset;
  final double scrollVelocity;

  const SolarSystem3DWidget({
    super.key,
    this.height = 300,
    this.scrollOffset = 0.0,
    this.scrollVelocity = 0.0,
  });

  @override
  State<SolarSystem3DWidget> createState() => _SolarSystem3DWidgetState();
}

class _SolarSystem3DWidgetState extends State<SolarSystem3DWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // Dynamic physics state
  double _accumulatedTime = 0.0;
  double _speedMultiplier = 1.0;
  double _currentVelocity = 0.0;
  double _prevScrollOffset = 0.0;

  static const List<_PlanetConfig> _planets = [
    _PlanetConfig(
      name: 'Merkurius',
      assetPath: 'assets/planets/mercury.png',
      radiusRatio: 0.12,
      baseSize: 13,
      orbitalSpeed: 3.8,
      initialAngle: 0.8,
      orbitColor: Color(0xFF9E9E9E),
    ),
    _PlanetConfig(
      name: 'Venus',
      assetPath: 'assets/planets/venus.png',
      radiusRatio: 0.17,
      baseSize: 17,
      orbitalSpeed: 2.2,
      initialAngle: 2.4,
      orbitColor: Color(0xFFD4AF37),
    ),
    _PlanetConfig(
      name: 'Bumi',
      assetPath: 'assets/planets/earth.png',
      radiusRatio: 0.23,
      baseSize: 19,
      orbitalSpeed: 1.4,
      initialAngle: 4.2,
      orbitColor: Color(0xFF38BDF8),
    ),
    _PlanetConfig(
      name: 'Mars',
      assetPath: 'assets/planets/mars.png',
      radiusRatio: 0.28,
      baseSize: 15,
      orbitalSpeed: 1.0,
      initialAngle: 1.5,
      orbitColor: Color(0xFFF87171),
    ),
    _PlanetConfig(
      name: 'Jupiter',
      assetPath: 'assets/planets/jupiter.png',
      radiusRatio: 0.34,
      baseSize: 29,
      orbitalSpeed: 0.6,
      initialAngle: 5.1,
      orbitColor: Color(0xFFFBBF24),
    ),
    _PlanetConfig(
      name: 'Saturnus',
      assetPath: 'assets/planets/saturn.png',
      radiusRatio: 0.40,
      baseSize: 35,
      orbitalSpeed: 0.42,
      initialAngle: 3.3,
      orbitColor: Color(0xFFFDE68A),
    ),
    _PlanetConfig(
      name: 'Uranus',
      assetPath: 'assets/planets/uranus.png',
      radiusRatio: 0.445,
      baseSize: 21,
      orbitalSpeed: 0.28,
      initialAngle: 0.3,
      orbitColor: Color(0xFF67E8F9),
    ),
    _PlanetConfig(
      name: 'Neptunus',
      assetPath: 'assets/planets/neptune.png',
      radiusRatio: 0.485,
      baseSize: 20,
      orbitalSpeed: 0.20,
      initialAngle: 2.9,
      orbitColor: Color(0xFF60A5FA),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _prevScrollOffset = widget.scrollOffset;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(_onTick);
    _controller.repeat();
  }

  void _onTick() {
    // Measure instant scroll delta
    final double scrollDelta = (widget.scrollOffset - _prevScrollOffset).abs();
    _prevScrollOffset = widget.scrollOffset;

    if (scrollDelta > 0.05) {
      final instantVel = scrollDelta * 60.0;
      _currentVelocity = math.max(_currentVelocity, instantVel);
    }
    if (widget.scrollVelocity.abs() > 0) {
      _currentVelocity = math.max(_currentVelocity, widget.scrollVelocity.abs());
    }

    // Decay velocity smoothly frame-by-frame when scroll comes to rest
    _currentVelocity *= 0.88;

    // Accelerate orbital revolution smoothly during scrolling
    final targetMultiplier = 1.0 + (_currentVelocity * 0.005).clamp(0.0, 7.0);
    _speedMultiplier = _speedMultiplier * 0.82 + targetMultiplier * 0.18;

    // Delta time step
    const dt = 1.0 / 60.0;
    _accumulatedTime += dt * _speedMultiplier;

    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Fade out and subtle scale as user scrolls down
    final double scrollOffset = widget.scrollOffset;
    final double fade = (1.0 - (scrollOffset / 280.0)).clamp(0.0, 1.0);
    final double scale = (1.0 - (scrollOffset / 800.0)).clamp(0.80, 1.0);
    final double height = widget.height ?? 300;

    if (fade <= 0.0) {
      return SizedBox(height: height * scale);
    }

    // ── Continuous 3D to 2D Transition ──
    // progress2D: 0.0 at top (full 3D inclined perspective), 1.0 when scrolled down (flat 2D top-down)
    final double progress2D = (scrollOffset / 200.0).clamp(0.0, 1.0);
    const double base3DPitch = 1.15; // ~66 degrees tilt for 3D depth
    final double totalPitch = base3DPitch * (1.0 - progress2D);

    final double t = _accumulatedTime;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth > 0
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width;

        return Opacity(
          opacity: fade,
          child: Transform.scale(
            scale: scale,
            child: SizedBox(
              width: width,
              height: height,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  // 1. Background CustomPainter for 3D/2D Orbit Lines & Ambient Stars
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _SolarOrbitsPainter(
                        pitch: totalPitch,
                        planets: _planets,
                        time: t,
                        width: width,
                      ),
                    ),
                  ),

                  // 2. Celestial Bodies with depth sorting
                  ..._buildCelestialBodies(width, height, totalPitch, progress2D, t),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildCelestialBodies(
    double width,
    double height,
    double pitch,
    double progress2D,
    double t,
  ) {
    final center = Offset(width / 2, height / 2);
    final List<_CelestialItem> items = [];

    // Central Sun with pulsing corona
    final double sunPulse = 1.0 + 0.04 * math.sin(t * 2.2);
    const double sunBaseSize = 58.0;
    final double sunSize = sunBaseSize * sunPulse;

    items.add(_CelestialItem(
      zIndex: 0.0,
      widget: Positioned(
        left: center.dx - (sunSize / 2),
        top: center.dy - (sunSize / 2),
        width: sunSize,
        height: sunSize,
        child: IgnorePointer(
          child: Image.asset(
            'assets/planets/sun.png',
            fit: BoxFit.contain,
          ),
        ),
      ),
    ));

    // 8 Planets with pure revolution
    for (int i = 0; i < _planets.length; i++) {
      final p = _planets[i];
      final angle = p.initialAngle + (t * p.orbitalSpeed * 0.5);

      // Scale orbit radius to fill the full width without clipping at edges
      final r = width * p.radiusRatio;

      // 3D/2D coordinates: when pitch=0 (2D), x=r*cos, y=r*sin (perfect circle)
      final x = r * math.cos(angle);
      final y = r * math.sin(angle) * math.cos(pitch);
      final z = r * math.sin(angle) * math.sin(pitch);

      // Perspective scale factor based on depth (normalizes to 1.0 in 2D)
      final double perspectiveScale =
          (1.0 + (z / (width * 0.5)) * 0.35 * (1.0 - progress2D)).clamp(0.65, 1.45);
      final double planetSize = p.baseSize * perspectiveScale;

      items.add(_CelestialItem(
        zIndex: z,
        widget: Positioned(
          left: center.dx + x - (planetSize / 2),
          top: center.dy + y - (planetSize / 2),
          width: planetSize,
          height: planetSize,
          child: IgnorePointer(
            child: Image.asset(
              p.assetPath,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ));
    }

    // Sort by Z-Index so planets behind Sun render first, then Sun, then planets in front
    items.sort((a, b) => a.zIndex.compareTo(b.zIndex));

    return items.map((item) => item.widget).toList();
  }
}

class _CelestialItem {
  final double zIndex;
  final Widget widget;
  _CelestialItem({required this.zIndex, required this.widget});
}

class _CrossStarConfig {
  final double relX;
  final double relY;
  final double baseSize;
  final double speed;
  final double phase;
  final Color haloColor;
  final double hRatio;

  const _CrossStarConfig({
    required this.relX,
    required this.relY,
    required this.baseSize,
    required this.speed,
    required this.phase,
    required this.haloColor,
    required this.hRatio,
  });
}

class _SolarOrbitsPainter extends CustomPainter {
  final double pitch;
  final List<_PlanetConfig> planets;
  final double time;
  final double width;

  _SolarOrbitsPainter({
    required this.pitch,
    required this.planets,
    required this.time,
    required this.width,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Multi-layer solar corona glow
    final sunGlowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFF59E0B).withValues(alpha: 0.25),
          const Color(0xFFD9F99D).withValues(alpha: 0.08),
          Colors.transparent,
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: 85));
    canvas.drawCircle(center, 85, sunGlowPaint);

    // Draw 3D Elliptical Dotted Orbits across full frame
    for (final p in planets) {
      final orbitPaint = Paint()
        ..color = p.orbitColor.withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9;

      final orbitRadius = size.width * p.radiusRatio;

      final rect = Rect.fromCenter(
        center: center,
        width: orbitRadius * 2,
        height: orbitRadius * 2 * math.cos(pitch),
      );

      _drawDottedEllipse(canvas, rect, orbitPaint, 48);
    }

    // ── Ambient Glistening Space Stars (Sesuai Gambar Referensi Pengguna) ──
    _drawStarField(canvas, size, time);
  }

  void _drawStarField(Canvas canvas, Size size, double t) {
    // 1. Bintang Berpijar 4-Titik Utama (Cross-Flare Stars) - Redup, Halus & Berukuran Pas
    final primaryStars = [
      // Star 1 (Kiri Atas - Halus & Elegan)
      _CrossStarConfig(
        relX: 0.16,
        relY: 0.20,
        baseSize: 10.0,
        speed: 2.2,
        phase: 0.0,
        haloColor: const Color(0xFFC7D2FE), // lavender white halo
        hRatio: 0.80,
      ),
      // Star 2 (Kanan Atas)
      _CrossStarConfig(
        relX: 0.85,
        relY: 0.20,
        baseSize: 11.5,
        speed: 2.5,
        phase: 2.4,
        haloColor: const Color(0xFFE0E7FF), // celestial halo
        hRatio: 0.78,
      ),
      // Star 3 (Kiri Bawah - Kecil & Redup)
      _CrossStarConfig(
        relX: 0.11,
        relY: 0.72,
        baseSize: 8.5,
        speed: 2.0,
        phase: 4.1,
        haloColor: const Color(0xFFBAE6FD), // sky blue halo
        hRatio: 0.80,
      ),
    ];

    for (final s in primaryStars) {
      final pos = Offset(size.width * s.relX, size.height * s.relY);
      _drawGlisteningCrossStar(
        canvas: canvas,
        center: pos,
        baseSize: s.baseSize,
        time: t,
        speed: s.speed,
        phase: s.phase,
        haloColor: s.haloColor,
        hRatio: s.hRatio,
      );
    }

    // 2. Taburan Bintang-Bintang Titik Halus (Ambient Star Dust) - Redup & Lembut
    final dotStars = const [
      [0.06, 0.35, 0.9, 2.5, 0.4],
      [0.26, 0.14, 0.8, 2.1, 1.2],
      [0.82, 0.10, 1.0, 2.8, 3.1],
      [0.92, 0.38, 0.9, 2.0, 0.5],
      [0.88, 0.68, 0.8, 2.4, 1.5],
      [0.20, 0.84, 0.9, 2.2, 2.8],
      [0.05, 0.60, 0.7, 2.9, 1.7],
    ];

    for (final d in dotStars) {
      final double x = size.width * d[0];
      final double y = size.height * d[1];
      final double r = d[2];
      final double speed = d[3];
      final double phase = d[4];

      final double twinkle = (0.3 + 0.7 * math.sin(t * speed + phase).abs()).clamp(0.0, 1.0);
      final p = Paint()
        ..color = Colors.white.withValues(alpha: 0.08 + 0.18 * twinkle);
      canvas.drawCircle(Offset(x, y), r * (0.8 + 0.25 * twinkle), p);
    }
  }

  /// Menggambar Bintang Berpijar Silang 4-Titik (Cross Flare)
  /// Dirancang halus, elegan, dan redup agar tidak mengganggu tata surya
  void _drawGlisteningCrossStar({
    required Canvas canvas,
    required Offset center,
    required double baseSize,
    required double time,
    required double speed,
    required double phase,
    required Color haloColor,
    required double hRatio,
  }) {
    // Pijar halus berdenyut (breathing twinkle animation)
    final double rawPulse = math.sin(time * speed + phase);
    final double pulse = 0.55 + 0.45 * ((rawPulse + 1.0) / 2.0); // 0.55 -> 1.0
    final double currentSize = baseSize * (0.80 + 0.25 * pulse);

    final double vRayLength = currentSize;
    final double hRayLength = currentSize * hRatio;
    final double rayThickness = math.max(0.9, currentSize * 0.11);

    // 1. Halo Radial Glow Lembut & Redup
    final double haloRadius = currentSize * 1.5;
    final haloPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          haloColor.withValues(alpha: 0.16 * pulse),
          haloColor.withValues(alpha: 0.05 * pulse),
          Colors.transparent,
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: haloRadius));
    canvas.drawCircle(center, haloRadius, haloPaint);

    // 2. Vertical Ray (Diamond Beam Meruncing Halus)
    final vPath = Path()
      ..moveTo(center.dx, center.dy - vRayLength)
      ..lineTo(center.dx + rayThickness / 2, center.dy)
      ..lineTo(center.dx, center.dy + vRayLength)
      ..lineTo(center.dx - rayThickness / 2, center.dy)
      ..close();

    final rayPaint = Paint()
      ..color = Colors.white.withValues(alpha: (0.28 + 0.20 * pulse).clamp(0.0, 1.0))
      ..style = PaintingStyle.fill;
    canvas.drawPath(vPath, rayPaint);

    // 3. Horizontal Ray (Diamond Beam Mendatar Meruncing Halus)
    final hThickness = rayThickness * 0.85;
    final hPath = Path()
      ..moveTo(center.dx - hRayLength, center.dy)
      ..lineTo(center.dx, center.dy - hThickness / 2)
      ..lineTo(center.dx + hRayLength, center.dy)
      ..lineTo(center.dx, center.dy + hThickness / 2)
      ..close();
    canvas.drawPath(hPath, rayPaint);

    // 4. Secondary Micro Flare 45-degree (Sangat Halus)
    if (baseSize >= 10.0) {
      final diagLength = currentSize * 0.32;
      final diagThickness = rayThickness * 0.45;
      final diagPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.14 * pulse)
        ..style = PaintingStyle.fill;

      final dPath1 = Path()
        ..moveTo(center.dx - diagLength, center.dy - diagLength)
        ..lineTo(center.dx + diagThickness / 2, center.dy)
        ..lineTo(center.dx + diagLength, center.dy + diagLength)
        ..lineTo(center.dx - diagThickness / 2, center.dy)
        ..close();
      canvas.drawPath(dPath1, diagPaint);

      final dPath2 = Path()
        ..moveTo(center.dx + diagLength, center.dy - diagLength)
        ..lineTo(center.dx, center.dy + diagThickness / 2)
        ..lineTo(center.dx - diagLength, center.dy + diagLength)
        ..lineTo(center.dx, center.dy - diagThickness / 2)
        ..close();
      canvas.drawPath(dPath2, diagPaint);
    }

    // 5. Inti Putih Berkilau Lembut (Stellar Core)
    final corePaint = Paint()
      ..color = Colors.white.withValues(alpha: (0.45 + 0.25 * pulse).clamp(0.0, 1.0))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, math.max(0.9, rayThickness * 0.75), corePaint);
  }

  void _drawDottedEllipse(Canvas canvas, Rect rect, Paint paint, int segments) {
    final rx = rect.width / 2;
    final ry = rect.height / 2;
    final cx = rect.center.dx;
    final cy = rect.center.dy;

    for (int i = 0; i < segments; i++) {
      final t1 = (i * 2 * math.pi) / segments;
      final t2 = t1 + (math.pi / segments * 0.45);
      final p1 = Offset(cx + rx * math.cos(t1), cy + ry * math.sin(t1));
      final p2 = Offset(cx + rx * math.cos(t2), cy + ry * math.sin(t2));
      canvas.drawLine(p1, p2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SolarOrbitsPainter oldDelegate) {
    return oldDelegate.pitch != pitch ||
        oldDelegate.time != time ||
        oldDelegate.width != width;
  }
}
