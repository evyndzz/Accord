import 'dart:io';
import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

class MiniPlayer extends StatelessWidget {
  final String title;
  final String artist;
  final String? imageUrl;
  final bool isPlaying;
  final double progress;
  final List<Color>? gradientColors;
  final VoidCallback? onTap;
  final VoidCallback? onPlayPauseTap;
  final VoidCallback? onDragUp;
  final VoidCallback? onFavoriteTap;
  final bool isFavorite;

  const MiniPlayer({
    super.key,
    required this.title,
    required this.artist,
    this.imageUrl,
    required this.isPlaying,
    required this.progress,
    this.gradientColors,
    this.onTap,
    this.onPlayPauseTap,
    this.onDragUp,
    this.onFavoriteTap,
    this.isFavorite = false,
  });

  Widget _buildArtwork() {
    Widget? imageWidget;
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      if (imageUrl!.startsWith('http://') || imageUrl!.startsWith('https://')) {
        imageWidget = Image.network(
          imageUrl!,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const Icon(
            Icons.music_note_rounded,
            color: Colors.white,
            size: 22,
          ),
        );
      } else {
        imageWidget = Image.file(
          File(imageUrl!),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const Icon(
            Icons.music_note_rounded,
            color: Colors.white,
            size: 22,
          ),
        );
      }
    }

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors ??
              const [Color(0xFF27272A), Color(0xFF3F3F46)],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: imageWidget ??
            const Icon(
              Icons.music_note_rounded,
              color: Colors.white70,
              size: 22,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onVerticalDragUpdate: (details) {
        if (details.primaryDelta != null && details.primaryDelta! < -4) {
          onDragUp?.call();
        }
      },
      onVerticalDragEnd: (details) {
        if (details.primaryVelocity != null && details.primaryVelocity! < -150) {
          onDragUp?.call();
        }
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 28, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.30),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: SizedBox(
          height: 64,
          child: LiquidGlassLens(
            style: LiquidGlassStyle(
              shape: const LiquidGlassShape.roundedRectangle(cornerRadius: 30),
              appearance: LiquidGlassAppearance(
                blur: const LiquidGlassBlur(sigmaX: 16, sigmaY: 16),
                color: const Color(0x3814151C), // Latar bening transparan liquid glass
              ),
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.16),
                  width: 1.0,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    // Song Artwork
                    _buildArtwork(),
                    const SizedBox(width: 12),
                    // Song Title & Artist
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.1,
                              shadows: [
                                Shadow(color: Color(0xD9000000), blurRadius: 4, offset: Offset(0, 1)),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            artist,
                            style: const TextStyle(
                              color: Color(0xFFA1A1AA),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              shadows: [
                                Shadow(color: Color(0xD9000000), blurRadius: 4, offset: Offset(0, 1)),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  // Favorite / Like Button (Matching Gambar 2)
                  if (onFavoriteTap != null)
                    GestureDetector(
                      onTap: onFavoriteTap,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                        child: Icon(
                          isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          color: isFavorite ? const Color(0xFFF43F5E) : Colors.white70,
                          size: 22,
                        ),
                      ),
                    ),
                  // Play / Pause Button
                  GestureDetector(
                    onTap: onPlayPauseTap,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: Icon(
                        isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  }
}
