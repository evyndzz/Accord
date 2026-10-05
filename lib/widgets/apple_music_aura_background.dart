import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// An animated liquid aura mesh background inspired by Apple Music's Now Playing screen.
/// Features dynamic undulating wave ribbons, flowing sinusoidal curtains, and multi-color
/// morphing liquid orbs extracted from album artwork over a pure OLED black canvas (#000000).
class AppleMusicAuraBackground extends StatefulWidget {
  final Color primaryColor;
  final Color secondaryColor;
  final Color? tertiaryColor;
  final Widget? child;
  final bool isPlaying;
  final double vignetteOpacity;

  const AppleMusicAuraBackground({
    super.key,
    required this.primaryColor,
    required this.secondaryColor,
    this.tertiaryColor,
    this.child,
    this.isPlaying = true,
    this.vignetteOpacity = 0.40,
  });

  @override
  State<AppleMusicAuraBackground> createState() => _AppleMusicAuraBackgroundState();
}

class _AppleMusicAuraBackgroundState extends State<AppleMusicAuraBackground>
    with TickerProviderStateMixin {
  late final AnimationController _motionController;
  late AnimationController _colorTransitionController;

  late Color _oldPrimary;
  late Color _newPrimary;
  late Color _oldSecondary;
  late Color _newSecondary;
  late Color _oldTertiary;
  late Color _newTertiary;
  late Color _oldQuaternary;
  late Color _newQuaternary;

  @override
  void initState() {
    super.initState();

    _oldPrimary = widget.primaryColor;
    _newPrimary = widget.primaryColor;
    _oldSecondary = widget.secondaryColor;
    _newSecondary = widget.secondaryColor;

    final initialTertiary = widget.tertiaryColor ?? _deriveTertiary(widget.primaryColor, widget.secondaryColor);
    _oldTertiary = initialTertiary;
    _newTertiary = initialTertiary;

    final initialQuaternary = _deriveQuaternary(widget.primaryColor, widget.secondaryColor);
    _oldQuaternary = initialQuaternary;
    _newQuaternary = initialQuaternary;

    // Smooth fluid motion controller with clearly visible 9-second loop
    _motionController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    );

    // Color transition controller for smooth crossfades between song palettes
    _colorTransitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      value: 1.0,
    );

    // Safe in test environments: avoids infinite pump timers in flutter test
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      _motionController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant AppleMusicAuraBackground oldWidget) {
    super.didUpdateWidget(oldWidget);

    final newTertiary = widget.tertiaryColor ?? _deriveTertiary(widget.primaryColor, widget.secondaryColor);
    final newQuaternary = _deriveQuaternary(widget.primaryColor, widget.secondaryColor);

    if (oldWidget.primaryColor != widget.primaryColor ||
        oldWidget.secondaryColor != widget.secondaryColor ||
        oldWidget.tertiaryColor != widget.tertiaryColor) {
      _oldPrimary = Color.lerp(_oldPrimary, _newPrimary, _colorTransitionController.value) ?? _oldPrimary;
      _oldSecondary = Color.lerp(_oldSecondary, _newSecondary, _colorTransitionController.value) ?? _oldSecondary;
      _oldTertiary = Color.lerp(_oldTertiary, _newTertiary, _colorTransitionController.value) ?? _oldTertiary;
      _oldQuaternary = Color.lerp(_oldQuaternary, _newQuaternary, _colorTransitionController.value) ?? _oldQuaternary;

      _newPrimary = widget.primaryColor;
      _newSecondary = widget.secondaryColor;
      _newTertiary = newTertiary;
      _newQuaternary = newQuaternary;

      _colorTransitionController.forward(from: 0.0);
    }
  }

  Color _deriveTertiary(Color primary, Color secondary) {
    // Derive a rich complementary warm or highlighted hue between primary & secondary
    final blended = Color.lerp(primary, secondary, 0.45) ?? primary;
    final hsl = HSLColor.fromColor(blended);
    return hsl.withLightness((hsl.lightness + 0.08).clamp(0.22, 0.46)).withSaturation((hsl.saturation + 0.10).clamp(0.40, 1.0)).toColor();
  }

  Color _deriveQuaternary(Color primary, Color secondary) {
    // Derive a deep radiant tone with shifted hue for richer chromatic interplay
    final hsl = HSLColor.fromColor(secondary);
    final shiftedHue = (hsl.hue + 38.0) % 360.0;
    return hsl.withHue(shiftedHue).withLightness((hsl.lightness - 0.06).clamp(0.16, 0.42)).toColor();
  }

  @override
  void dispose() {
    _motionController.dispose();
    _colorTransitionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Pure OLED Black Base (#000000)
          const ColoredBox(color: Colors.black),

          // 2. Animated Liquid Wavy Aura Mesh Canvas
          AnimatedBuilder(
            animation: Listenable.merge([_motionController, _colorTransitionController]),
            builder: (context, _) {
              final colorT = Curves.easeInOutCubic.transform(_colorTransitionController.value);
              final currentPrimary = Color.lerp(_oldPrimary, _newPrimary, colorT) ?? _newPrimary;
              final currentSecondary = Color.lerp(_oldSecondary, _newSecondary, colorT) ?? _newSecondary;
              final currentTertiary = Color.lerp(_oldTertiary, _newTertiary, colorT) ?? _newTertiary;
              final currentQuaternary = Color.lerp(_oldQuaternary, _newQuaternary, colorT) ?? _newQuaternary;

              return CustomPaint(
                painter: _AppleMusicWavyAuraPainter(
                  progress: _motionController.value,
                  primary: currentPrimary,
                  secondary: currentSecondary,
                  tertiary: currentTertiary,
                  quaternary: currentQuaternary,
                ),
                isComplex: true,
                willChange: true,
              );
            },
          ),

          // 3. Apple Music Silk Diffusion Filter (Melts waves & blobs into liquid light)
          Positioned.fill(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 46, sigmaY: 46),
              child: const SizedBox.expand(),
            ),
          ),

          // 3b. Protective OLED dark scrim (prevents white/bright backgrounds from obscuring text)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black.withValues(alpha: 0.28),
            ),
          ),

          // 4. Subtle Vignette Contrast Overlay (keeps text, chords, and cards crystal sharp)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.15),
                    Colors.transparent,
                    Colors.black.withValues(alpha: widget.vignetteOpacity * 0.50),
                    Colors.black.withValues(alpha: widget.vignetteOpacity),
                  ],
                  stops: const [0.0, 0.35, 0.85, 1.0],
                ),
              ),
            ),
          ),

          // 5. Optional Foreground Content
          if (widget.child != null) widget.child!,
        ],
      ),
    );
  }
}

class _AppleMusicWavyAuraPainter extends CustomPainter {
  final double progress;
  final Color primary;
  final Color secondary;
  final Color tertiary;
  final Color quaternary;

  const _AppleMusicWavyAuraPainter({
    required this.progress,
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.quaternary,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final angle = progress * 2.0 * math.pi;

    // ==========================================
    // 1. WAVY UNDULATING AURA CURTAINS / RIBBONS
    // ==========================================

    // Wave Curtain 1: Upper flowing sinusoidal wave ribbon
    final wave1Path = Path();
    final wave1BaseY = size.height * (0.28 + 0.09 * math.sin(angle));
    wave1Path.moveTo(0, wave1BaseY);
    for (double x = 0; x <= size.width; x += 16) {
      final nx = x / size.width;
      final y = wave1BaseY +
          34.0 * math.sin(nx * 2.0 * math.pi + angle * 1.2) +
          20.0 * math.cos(nx * 4.0 * math.pi - angle * 0.8) +
          12.0 * math.sin(nx * math.pi + angle * 0.5);
      wave1Path.lineTo(x, y);
    }
    wave1Path.lineTo(size.width, size.height);
    wave1Path.lineTo(0, size.height);
    wave1Path.close();

    final wave1Paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          primary.withValues(alpha: 0.55),
          tertiary.withValues(alpha: 0.48),
          secondary.withValues(alpha: 0.35),
          Colors.transparent,
        ],
        stops: const [0.0, 0.35, 0.70, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(wave1Path, wave1Paint);

    // Wave Curtain 2: Lower counter-undulating wave ribbon
    final wave2Path = Path();
    final wave2BaseY = size.height * (0.58 + 0.08 * math.cos(angle * 1.1 + 0.9));
    wave2Path.moveTo(0, wave2BaseY);
    for (double x = 0; x <= size.width; x += 16) {
      final nx = x / size.width;
      final y = wave2BaseY +
          30.0 * math.cos(nx * 2.2 * math.pi - angle * 1.0) +
          18.0 * math.sin(nx * 3.6 * math.pi + angle * 1.3) +
          10.0 * math.cos(nx * math.pi - angle * 0.6);
      wave2Path.lineTo(x, y);
    }
    wave2Path.lineTo(size.width, size.height);
    wave2Path.lineTo(0, size.height);
    wave2Path.close();

    final wave2Paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
        colors: [
          secondary.withValues(alpha: 0.52),
          quaternary.withValues(alpha: 0.44),
          tertiary.withValues(alpha: 0.28),
          Colors.transparent,
        ],
        stops: const [0.0, 0.30, 0.65, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(wave2Path, wave2Paint);

    // Diagonal Sweeping Wave Ribbon across center
    final ribbonPath = Path();
    final ribYStart = size.height * (0.15 + 0.10 * math.cos(angle * 0.9));
    final ribYEnd = size.height * (0.80 + 0.10 * math.sin(angle * 0.85));
    ribbonPath.moveTo(0, ribYStart);
    ribbonPath.quadraticBezierTo(
      size.width * 0.5 + 40 * math.sin(angle * 1.4),
      size.height * 0.45 + 35 * math.cos(angle * 1.2),
      size.width,
      ribYEnd,
    );
    ribbonPath.lineTo(size.width, ribYEnd + 140);
    ribbonPath.quadraticBezierTo(
      size.width * 0.5 - 30 * math.cos(angle * 1.3),
      size.height * 0.55 - 25 * math.sin(angle * 1.1),
      0,
      ribYStart + 160,
    );
    ribbonPath.close();

    final ribbonPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [
          tertiary.withValues(alpha: 0.46),
          primary.withValues(alpha: 0.40),
          quaternary.withValues(alpha: 0.30),
          Colors.transparent,
        ],
        stops: const [0.0, 0.35, 0.70, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(ribbonPath, ribbonPaint);

    // ==========================================
    // 2. ORBITING & MORPHING LIQUID AURA BLOBS
    // ==========================================

    // Orb 1: Upper-left dominant primary aura vortex
    final ox1 = size.width * (0.35 + 0.28 * math.sin(angle));
    final oy1 = size.height * (0.26 + 0.18 * math.cos(angle));
    final r1 = size.width * (0.75 + 0.18 * math.sin(angle * 2.0));

    // Orb 2: Lower-right vibrant secondary aura stream
    final ox2 = size.width * (0.65 + 0.26 * math.cos(angle + 1.2));
    final oy2 = size.height * (0.64 + 0.22 * math.sin(angle + 0.8));
    final r2 = size.width * (0.80 + 0.16 * math.cos(angle * 2.0 + 1.0));

    // Orb 3: Mid-left floating tertiary aura (intertwines with waves)
    final ox3 = size.width * (0.30 + 0.24 * math.cos(angle * 1.5 + 2.5));
    final oy3 = size.height * (0.52 + 0.24 * math.sin(angle * 1.5 + 1.5));
    final r3 = size.width * (0.68 + 0.14 * math.sin(angle + 2.0));

    // Orb 4: Upper-right atmospheric highlight aura
    final ox4 = size.width * (0.72 + 0.22 * math.sin(angle * 1.2 + 3.2));
    final oy4 = size.height * (0.32 + 0.16 * math.cos(angle * 1.2 + 2.0));
    final r4 = size.width * (0.62 + 0.12 * math.cos(angle * 1.5));

    // Orb 5: Bottom-center deep radiant base
    final ox5 = size.width * (0.48 + 0.20 * math.cos(angle * 0.8 + 1.8));
    final oy5 = size.height * (0.82 + 0.12 * math.sin(angle * 0.9 + 2.6));
    final r5 = size.width * (0.70 + 0.15 * math.sin(angle * 1.3));

    // Draw multi-stop radiant glowing liquid aura blobs
    _drawAuraBlob(canvas, Offset(ox1, oy1), r1, primary, 0.70);
    _drawAuraBlob(canvas, Offset(ox2, oy2), r2, secondary, 0.65);
    _drawAuraBlob(canvas, Offset(ox3, oy3), r3, tertiary, 0.60);
    _drawAuraBlob(canvas, Offset(ox4, oy4), r4, quaternary, 0.54);
    _drawAuraBlob(canvas, Offset(ox5, oy5), r5, secondary, 0.50);
  }

  void _drawAuraBlob(Canvas canvas, Offset center, double radius, Color color, double maxAlpha) {
    if (radius <= 0) return;

    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: maxAlpha),
          color.withValues(alpha: maxAlpha * 0.80),
          color.withValues(alpha: maxAlpha * 0.50),
          color.withValues(alpha: maxAlpha * 0.20),
          color.withValues(alpha: maxAlpha * 0.05),
          Colors.transparent,
        ],
        stops: const [0.0, 0.25, 0.50, 0.75, 0.90, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _AppleMusicWavyAuraPainter oldDelegate) {
    return true; // Continuously renders frame-by-frame for fluid 60/120fps liquid motion
  }
}
