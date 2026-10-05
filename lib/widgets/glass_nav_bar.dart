import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

class GlassNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemTapped;

  const GlassNavBar({
    super.key,
    required this.selectedIndex,
    required this.onItemTapped,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 20, left: 24, right: 24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildSeparateNavItem(
              icon: Icons.home_rounded,
              label: 'Home',
              index: 0,
            ),
            const SizedBox(width: 14),
            _buildSeparateNavItem(
              icon: Icons.search_rounded,
              label: 'Search',
              index: 1,
            ),
            const SizedBox(width: 14),
            _buildSeparateNavItem(
              icon: Icons.folder_copy_rounded,
              label: 'Library',
              index: 2,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeparateNavItem({
    required IconData icon,
    required String label,
    required int index,
  }) {
    final active = selectedIndex == index;
    final radius = active ? 32.0 : 28.0;

    return GestureDetector(
      onTap: () => onItemTapped(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        height: 56,
        child: LiquidGlassLens(
          style: LiquidGlassStyle(
            shape: LiquidGlassShape.roundedRectangle(cornerRadius: radius),
            appearance: LiquidGlassAppearance(
              blur: const LiquidGlassBlur(sigmaX: 10, sigmaY: 10),
              color: active
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.white.withValues(alpha: 0.04),
            ),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            height: 56,
            padding: active
                ? const EdgeInsets.only(left: 6, right: 18, top: 4, bottom: 4)
                : const EdgeInsets.all(4),
            child: active
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Active circular lime badge with neon glow
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD9F99D),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFD9F99D).withValues(alpha: 0.45),
                              blurRadius: 14,
                              spreadRadius: 1,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Icon(
                          icon,
                          color: const Color(0xFF09090B),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  )
                : SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: Icon(
                        icon,
                        color: Colors.white.withValues(alpha: 0.85),
                        size: 22,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
