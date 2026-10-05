import 'package:flutter/material.dart';

class CategoryChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback? onTap;

  const CategoryChip({
    super.key,
    required this.label,
    this.active = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFF8B5CF6)
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : Colors.white70,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

