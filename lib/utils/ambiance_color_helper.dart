import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/song.dart';

/// Helper to generate rich dynamic ambiance colors and gradients
/// derived from the current song's actual artwork and palette.
class AmbianceColorHelper {
  // Preset harmonic palettes used when a song has no explicit gradientColors or while loading cover art
  static const List<List<Color>> _presetPalettes = [
    // 0. Purple-Violet & Electric Indigo (Like Gambar 1 left)
    [Color(0xFF6B46C1), Color(0xFF3B82F6)],
    // 1. Deep Magenta, Ruby & Crimson (Like Gambar 1 right)
    [Color(0xFF9D174D), Color(0xFFE11D48)],
    // 2. Midnight Coral & Radiant Amber (Like Gambar 2 mix 1)
    [Color(0xFFDC2626), Color(0xFFF97316)],
    // 3. Deep Oceanic Cyan & Sapphire (Like Gambar 2 mix 2)
    [Color(0xFF1E40AF), Color(0xFF06B6D4)],
    // 4. Emerald Aurora & Neon Lime
    [Color(0xFF059669), Color(0xFF84CC16)],
    // 5. Cyber Lavender & Soft Violet
    [Color(0xFF7C3AED), Color(0xFFC084FC)],
    // 6. Sunset Rose & Deep Plum
    [Color(0xFFBE185D), Color(0xFF701A75)],
    // 7. Twilight Teal & Mint Glow
    [Color(0xFF0D9488), Color(0xFF10B981)],
  ];

  // In-memory cache for colors extracted directly from album artwork
  static final Map<String, List<Color>> _extractedColorsCache = {};
  static final Set<String> _inFlightExtractions = {};

  /// Notifier triggered whenever new artwork colors are extracted,
  /// allowing widgets (Player, Dashboard) to reactively rebuild.
  static final ValueNotifier<int> colorExtractionNotifier = ValueNotifier<int>(0);

  /// Allows setting or mocking extracted colors (used in unit tests and manual overrides)
  static void setExtractedColors(String key, List<Color> colors) {
    if (colors.isNotEmpty) {
      _extractedColorsCache[key] = colors;
      colorExtractionNotifier.value++;
    }
  }

  /// Normalizes an ambiance color so it NEVER washes out to bright white, pale pastel,
  /// or unreadable high-luminance tones. Keeps all foreground text 100% readable.
  static Color ensureReadableAmbiance(Color color) {
    final hsl = HSLColor.fromColor(color);
    if (hsl.lightness <= 0.52 && hsl.saturation >= 0.35) {
      return color;
    }
    final clampedLightness = hsl.lightness.clamp(0.18, 0.50);
    final boostedSaturation = (hsl.saturation < 0.35) ? 0.55 : hsl.saturation;
    return hsl.withLightness(clampedLightness).withSaturation(boostedSaturation).toColor();
  }

  /// Returns the primary vibrant color for the song.
  static Color getPrimaryColor(Song? song) {
    if (song == null) return const Color(0xFF6B46C1);

    if (song.albumArtUrl != null && song.albumArtUrl!.isNotEmpty) {
      final cached = _extractedColorsCache[song.albumArtUrl!];
      if (cached != null && cached.isNotEmpty) {
        return ensureReadableAmbiance(cached.first);
      }
      // Trigger background extraction if not already running
      extractColorsForSong(song);
    }

    if (song.gradientColors != null && song.gradientColors!.isNotEmpty) {
      return ensureReadableAmbiance(song.gradientColors!.first);
    }
    final palette = _getPaletteForSong(song);
    return ensureReadableAmbiance(palette.first);
  }

  /// Returns the secondary accent color for the song.
  static Color getSecondaryColor(Song? song) {
    if (song == null) return const Color(0xFF3B82F6);

    if (song.albumArtUrl != null && song.albumArtUrl!.isNotEmpty) {
      final cached = _extractedColorsCache[song.albumArtUrl!];
      if (cached != null && cached.length >= 2) {
        return ensureReadableAmbiance(cached[1]);
      }
      extractColorsForSong(song);
    }

    if (song.gradientColors != null && song.gradientColors!.length >= 2) {
      return ensureReadableAmbiance(song.gradientColors![1]);
    }
    final palette = _getPaletteForSong(song);
    return ensureReadableAmbiance(palette.last);
  }

  /// Asynchronously extracts dominant vibrant and accent colors directly from the song's albumArtUrl.
  /// Works with local files (`FileImage`) and remote URLs (`NetworkImage`).
  static Future<void> extractColorsForSong(Song song) async {
    final artUrl = song.albumArtUrl?.trim();
    if (artUrl == null || artUrl.isEmpty) return;
    if (_extractedColorsCache.containsKey(artUrl) || _inFlightExtractions.contains(artUrl)) {
      return;
    }

    _inFlightExtractions.add(artUrl);

    try {
      final ImageProvider provider;
      if (artUrl.startsWith('http://') || artUrl.startsWith('https://')) {
        provider = NetworkImage(artUrl);
      } else if (!kIsWeb && File(artUrl).existsSync()) {
        provider = FileImage(File(artUrl));
      } else {
        _inFlightExtractions.remove(artUrl);
        return;
      }

      final completer = Completer<ui.Image>();
      final stream = provider.resolve(const ImageConfiguration());
      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (ImageInfo info, bool _) {
          if (!completer.isCompleted) completer.complete(info.image);
          stream.removeListener(listener);
        },
        onError: (dynamic error, StackTrace? _) {
          if (!completer.isCompleted) completer.completeError(error);
          stream.removeListener(listener);
        },
      );
      stream.addListener(listener);

      final image = await completer.future.timeout(const Duration(seconds: 4));

      // Downscale to 8x8 bitmap via Canvas (instant, ~1ms, negligible CPU)
      const targetSize = 8;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final paint = Paint()..filterQuality = FilterQuality.low;

      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        const Rect.fromLTWH(0, 0, 8.0, 8.0),
        paint,
      );

      final picture = recorder.endRecording();
      final smallImage = await picture.toImage(targetSize, targetSize);
      final byteData = await smallImage.toByteData(format: ui.ImageByteFormat.rawRgba);

      if (byteData != null) {
        Color? bestVibrant;
        double maxScore = -1.0;
        final candidateColors = <Color>[];

        for (int i = 0; i < targetSize * targetSize; i++) {
          final offset = i * 4;
          final r = byteData.getUint8(offset);
          final g = byteData.getUint8(offset + 1);
          final b = byteData.getUint8(offset + 2);
          final a = byteData.getUint8(offset + 3);

          if (a < 128) continue; // Skip transparent pixels

          final color = Color.fromARGB(255, r, g, b);
          final hsl = HSLColor.fromColor(color);

          // Discard near-black (< 12% lightness), washed-out pale pastels, and bright white (> 65% lightness)
          if (hsl.lightness < 0.12 || hsl.lightness > 0.65 || (hsl.lightness > 0.50 && hsl.saturation < 0.25)) continue;

          // Score based on saturation (chroma) and balanced lightness
          final lightnessFactor = 1.0 - (hsl.lightness - 0.5).abs() * 1.5;
          final score = (hsl.saturation * 1.6) + lightnessFactor;

          candidateColors.add(color);
          if (score > maxScore) {
            maxScore = score;
            bestVibrant = color;
          }
        }

        if (bestVibrant != null) {
          // Secondary color: pick a candidate with distinct hue (> 35 deg apart)
          final primaryHsl = HSLColor.fromColor(bestVibrant);
          Color? secondaryColor;
          double maxHueDiff = -1.0;

          for (final c in candidateColors) {
            final hsl = HSLColor.fromColor(c);
            final hueDiff = (hsl.hue - primaryHsl.hue).abs();
            final normalizedDiff = hueDiff > 180 ? 360 - hueDiff : hueDiff;
            if (normalizedDiff > 35 && normalizedDiff > maxHueDiff) {
              maxHueDiff = normalizedDiff;
              secondaryColor = c;
            }
          }

          // If no distinct hue was found, generate harmonious accent by shifting hue slightly
          if (secondaryColor == null) {
            final shiftedHue = (primaryHsl.hue + 45.0) % 360.0;
            final adjustedLightness = (primaryHsl.lightness > 0.5)
                ? math.max(0.35, primaryHsl.lightness - 0.20)
                : math.min(0.75, primaryHsl.lightness + 0.20);
            secondaryColor = primaryHsl
                .withHue(shiftedHue)
                .withLightness(adjustedLightness)
                .toColor();
          }

          _extractedColorsCache[artUrl] = [bestVibrant, secondaryColor];
          colorExtractionNotifier.value++;
        }
      }
    } catch (_) {
      // Graceful fallback to deterministic palette on decode failure or network timeout
    } finally {
      _inFlightExtractions.remove(artUrl);
    }
  }

  static List<Color> _getPaletteForSong(Song song) {
    // Generate deterministic index based on title and artist
    final key = '${song.title}_${song.artist}_${song.id}';
    final hash = key.hashCode.abs();
    return _presetPalettes[hash % _presetPalettes.length];
  }

  /// Returns a rich ambient radial/linear gradient for the Player background.
  static BoxDecoration getAmbientBackground(Song? song) {
    final primary = getPrimaryColor(song);
    final secondary = getSecondaryColor(song);

    return BoxDecoration(
      color: const Color(0xFF090A0F),
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          primary.withValues(alpha: 0.42),
          secondary.withValues(alpha: 0.22),
          primary.withValues(alpha: 0.12),
          secondary.withValues(alpha: 0.08),
          const Color(0xFF090A0F),
        ],
        stops: const [0.0, 0.30, 0.60, 0.85, 1.0],
      ),
    );
  }

  /// Ambient glow positioned behind the album cover artwork.
  static Widget buildArtworkGlow(Song? song, {double size = 260}) {
    final primary = getPrimaryColor(song);
    final secondary = getSecondaryColor(song);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            primary.withValues(alpha: 0.55),
            secondary.withValues(alpha: 0.25),
            Colors.transparent,
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
    );
  }

  /// Drop shadow color for the album cover artwork card.
  static Color getArtworkShadowColor(Song? song) {
    final primary = getPrimaryColor(song);
    return primary.withValues(alpha: 0.45);
  }

  /// Gradient for the main glowing Play button (matching Image 1).
  static Gradient getPlayButtonGradient(Song? song) {
    final primary = getPrimaryColor(song);
    final secondary = getSecondaryColor(song);

    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color.lerp(primary, Colors.white, 0.22) ?? primary,
        secondary,
      ],
    );
  }
}
