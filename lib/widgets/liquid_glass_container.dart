import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

/// A layout-driven liquid glass container powered by [LiquidGlassLens].
///
/// On Android Impeller: full refraction + live-backdrop liquid glass.
/// On Linux / Skia: graceful frosted-glass fallback (blur + tint + border).
class LiquidGlassContainer extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final double blur;
  final Color? backgroundColor;
  final Color? borderColor;
  final Gradient? backgroundGradient;
  final Gradient? borderGradient;
  final List<BoxShadow>? shadows;
  final VoidCallback? onTap;

  const LiquidGlassContainer({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.borderRadius = 22,
    this.blur = 8,
    this.backgroundColor,
    this.borderColor,
    this.backgroundGradient,
    this.borderGradient,
    this.shadows,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Widget innerChild = child;
    if (padding != null) {
      innerChild = Padding(padding: padding!, child: innerChild);
    }
    if (borderColor != null || borderGradient != null || backgroundGradient != null) {
      innerChild = Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          gradient: backgroundGradient,
          border: borderColor != null
              ? Border.all(color: borderColor!, width: 1.0)
              : null,
        ),
        child: innerChild,
      );
    }

    Widget lens = LiquidGlassLens(
      style: LiquidGlassStyle(
        shape: LiquidGlassShape.roundedRectangle(cornerRadius: borderRadius),
        appearance: LiquidGlassAppearance(
          blur: LiquidGlassBlur(sigmaX: blur, sigmaY: blur),
          color: backgroundColor ?? Colors.white.withValues(alpha: 0.10),
        ),
      ),
      child: innerChild,
    );

    if (width != null || height != null) {
      lens = SizedBox(
        width: width,
        height: height,
        child: lens,
      );
    }

    if (shadows != null && shadows!.isNotEmpty) {
      lens = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          boxShadow: shadows,
        ),
        child: lens,
      );
    }

    if (margin != null) {
      lens = Padding(padding: margin!, child: lens);
    }

    if (onTap != null) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: lens,
      );
    }
    return lens;
  }
}
