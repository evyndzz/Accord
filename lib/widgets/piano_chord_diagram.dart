import 'package:flutter/material.dart';
import '../models/piano_chord.dart';

/// Widget diagram tuts piano yang menampilkan posisi jari / nada akord ala Chordify
class PianoChordDiagramWidget extends StatelessWidget {
  final String chordName;
  final double width;
  final double height;
  final bool isCurrent;
  final bool showChordName;
  final Color? activeColor;
  final String? badgeText;
  final Color? badgeColor;

  const PianoChordDiagramWidget({
    super.key,
    required this.chordName,
    this.width = 140,
    this.height = 80,
    this.isCurrent = false,
    this.showChordName = true,
    this.activeColor,
    this.badgeText,
    this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    final cleanChord = chordName.trim();
    final isRest = cleanChord == '𝄽' || cleanChord == '--' || cleanChord.toLowerCase() == 'rest';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (badgeText != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              color: (badgeColor ?? (isCurrent ? const Color(0xFFD9F99D) : const Color(0xFFA1A1AA))).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: (badgeColor ?? (isCurrent ? const Color(0xFFD9F99D) : const Color(0xFFA1A1AA))).withValues(alpha: 0.35),
                width: 0.8,
              ),
            ),
            child: Text(
              badgeText!,
              style: TextStyle(
                color: badgeColor ?? (isCurrent ? const Color(0xFFD9F99D) : const Color(0xFFA1A1AA)),
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                shadows: const [
                  Shadow(
                    color: Color(0xD9000000),
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ],
        Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: const Color(0xFF181924),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: isCurrent
                    ? (activeColor ?? const Color(0xFFD9F99D)).withValues(alpha: 0.35)
                    : Colors.black.withValues(alpha: 0.25),
                blurRadius: isCurrent ? 12 : 4,
                spreadRadius: isCurrent ? 1 : 0,
                offset: const Offset(0, 2),
              ),
            ],
            border: Border.all(
              color: isCurrent
                  ? (activeColor ?? const Color(0xFFD9F99D))
                  : Colors.white.withValues(alpha: 0.15),
              width: isCurrent ? 2.0 : 1.0,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: isRest
              ? Center(
                  child: Text(
                    '𝄽',
                    style: TextStyle(
                      fontSize: height * 0.50,
                      color: isCurrent
                          ? const Color(0xFFD9F99D)
                          : Colors.white70,
                      fontWeight: FontWeight.w400,
                      shadows: const [
                        Shadow(
                          color: Color(0xD9000000),
                          blurRadius: 4,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                )
              : CustomPaint(
                  size: Size(width, height),
                  painter: _PianoKeyboardPainter(
                    voicing: PianoChordEngine.getVoicing(cleanChord),
                    isCurrent: isCurrent,
                    accentColor: activeColor ?? const Color(0xFFD9F99D),
                  ),
                ),
        ),
        if (showChordName) ...[
          const SizedBox(height: 5),
          Text(
            cleanChord.isEmpty ? '--' : cleanChord,
            style: TextStyle(
              color: isCurrent ? const Color(0xFFD9F99D) : Colors.white.withValues(alpha: 0.88),
              fontSize: 14,
              fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
              letterSpacing: 0.2,
              shadows: const [
                Shadow(
                  color: Color(0xD9000000),
                  blurRadius: 5,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

class _PianoKeyboardPainter extends CustomPainter {
  final PianoChordVoicing voicing;
  final bool isCurrent;
  final Color accentColor;

  _PianoKeyboardPainter({
    required this.voicing,
    required this.isCurrent,
    required this.accentColor,
  });

  // 11 tuts putih: C3, D3, E3, F3, G3, A3, B3, C4, D4, E4, F4
  // Mapping semitone tuts putih:
  // C3: 0, D3: 2, E3: 4, F3: 5, G3: 7, A3: 9, B3: 11, C4: 12, D4: 14, E4: 16, F4: 17
  static const List<int> whiteKeySemitones = [0, 2, 4, 5, 7, 9, 11, 12, 14, 16, 17];

  // 7 tuts hitam:
  // Antara C3-D3: C#3 (semitone 1) -> setelah tuts putih ke-0
  // Antara D3-E3: D#3 (semitone 3) -> setelah tuts putih ke-1
  // Antara F3-G3: F#3 (semitone 6) -> setelah tuts putih ke-3
  // Antara G3-A3: G#3 (semitone 8) -> setelah tuts putih ke-4
  // Antara A3-B3: A#3 (semitone 10) -> setelah tuts putih ke-5
  // Antara C4-D4: C#4 (semitone 13) -> setelah tuts putih ke-7
  // Antara D4-E4: D#4 (semitone 15) -> setelah tuts putih ke-8
  static const List<_BlackKeyDef> blackKeyDefs = [
    _BlackKeyDef(semitone: 1, whiteKeyIndexBefore: 0),
    _BlackKeyDef(semitone: 3, whiteKeyIndexBefore: 1),
    _BlackKeyDef(semitone: 6, whiteKeyIndexBefore: 3),
    _BlackKeyDef(semitone: 8, whiteKeyIndexBefore: 4),
    _BlackKeyDef(semitone: 10, whiteKeyIndexBefore: 5),
    _BlackKeyDef(semitone: 13, whiteKeyIndexBefore: 7),
    _BlackKeyDef(semitone: 15, whiteKeyIndexBefore: 8),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final totalWhiteKeys = whiteKeySemitones.length; // 11
    final whiteKeyWidth = size.width / totalWhiteKeys;
    final whiteKeyHeight = size.height;

    final blackKeyWidth = whiteKeyWidth * 0.62;
    final blackKeyHeight = whiteKeyHeight * 0.62;

    // Paints
    final whiteKeyPaint = Paint()
      ..color = const Color(0xFFF1F5F9)
      ..style = PaintingStyle.fill;

    final keyBorderPaint = Paint()
      ..color = const Color(0xFF94A3B8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final blackKeyPaint = Paint()
      ..color = const Color(0xFF111827)
      ..style = PaintingStyle.fill;

    // Titik pada tuts putih selalu HITAM pekat agar kontras dan mudah dilihat
    final whiteKeyDotPaint = Paint()
      ..color = const Color(0xFF09090B)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // Titik pada tuts hitam selalu PUTIH pekat agar kontras dan mudah dilihat
    final blackKeyDotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // 1. Gambar Tuts Putih
    for (int i = 0; i < totalWhiteKeys; i++) {
      final x = i * whiteKeyWidth;
      final rect = Rect.fromLTWH(x, 0, whiteKeyWidth, whiteKeyHeight);
      
      canvas.drawRect(rect, whiteKeyPaint);
      canvas.drawRect(rect, keyBorderPaint);

      final semitone = whiteKeySemitones[i];
      if (voicing.isKeyPressed(semitone)) {
        // Titik hitam pada tuts putih
        final dotCenterX = x + (whiteKeyWidth / 2);
        final dotCenterY = whiteKeyHeight * 0.76;
        final dotRadius = (whiteKeyWidth * 0.22).clamp(2.5, 4.8);

        canvas.drawCircle(Offset(dotCenterX, dotCenterY), dotRadius, whiteKeyDotPaint);
      }
    }

    // 2. Gambar Tuts Hitam di atas Tuts Putih
    for (final bk in blackKeyDefs) {
      final boundaryX = (bk.whiteKeyIndexBefore + 1) * whiteKeyWidth;
      final x = boundaryX - (blackKeyWidth / 2);
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(x, 0, blackKeyWidth, blackKeyHeight),
        bottomLeft: const Radius.circular(2.0),
        bottomRight: const Radius.circular(2.0),
      );

      canvas.drawRRect(rect, blackKeyPaint);

      if (voicing.isKeyPressed(bk.semitone)) {
        // Titik putih pada tuts hitam
        final dotCenterX = boundaryX;
        final dotCenterY = blackKeyHeight * 0.70;
        final dotRadius = (blackKeyWidth * 0.25).clamp(2.2, 4.0);

        canvas.drawCircle(Offset(dotCenterX, dotCenterY), dotRadius, blackKeyDotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PianoKeyboardPainter oldDelegate) {
    return oldDelegate.voicing.chordName != voicing.chordName ||
        oldDelegate.isCurrent != isCurrent ||
        oldDelegate.accentColor != accentColor;
  }
}

class _BlackKeyDef {
  final int semitone;
  final int whiteKeyIndexBefore;

  const _BlackKeyDef({
    required this.semitone,
    required this.whiteKeyIndexBefore,
  });
}
