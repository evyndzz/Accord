import 'package:flutter/material.dart';

import '../models/chord_shape.dart';

class ChordDiagramWidget extends StatelessWidget {
  final ChordShape shape;

  const ChordDiagramWidget({super.key, required this.shape});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _ChordDiagramPainter(shape));
  }
}

class _ChordDiagramPainter extends CustomPainter {
  final ChordShape shape;

  _ChordDiagramPainter(this.shape);

  @override
  void paint(Canvas canvas, Size size) {
    final stringPaint = Paint()
      ..color = const Color(0xFFB4B4B4)
      ..strokeWidth = 1.5
      ..isAntiAlias = true;

    final fretPaint = Paint()
      ..color = const Color(0xFFB4B4B4)
      ..strokeWidth = 1.5
      ..isAntiAlias = true;

    final nutPaint = Paint()
      ..color = const Color(0xFF333333)
      ..strokeWidth = 4.0
      ..isAntiAlias = true;

    final dotPaint = Paint()
      ..color = const Color(0xFF333333)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final topMargin = 20.0;
    final padding = 16.0;
    final width = size.width - padding * 2;
    final height = size.height - topMargin - padding;
    final stringGap = width / 5;
    final fretGap = height / 4;

    // Draw nut line (thick bar at top) or baseFret indicator
    if (shape.baseFret <= 1) {
      canvas.drawLine(
        Offset(padding, topMargin),
        Offset(padding + width, topMargin),
        nutPaint,
      );
    } else {
      // Draw baseFret number on the left
      final baseFretPainter = TextPainter(
        text: TextSpan(
          text: '${shape.baseFret}',
          style: const TextStyle(
            color: Color(0xFF666666),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      baseFretPainter.paint(
        canvas,
        Offset(padding - baseFretPainter.width - 4, topMargin + 2),
      );
      // Regular top fret line
      canvas.drawLine(
        Offset(padding, topMargin),
        Offset(padding + width, topMargin),
        fretPaint,
      );
    }

    // Draw 6 vertical strings
    for (int i = 0; i < 6; i++) {
      final x = padding + (i * stringGap);
      canvas.drawLine(
        Offset(x, topMargin),
        Offset(x, topMargin + height),
        stringPaint,
      );
    }

    // Draw 4 horizontal fret lines (below the nut)
    for (int i = 1; i <= 4; i++) {
      final y = topMargin + (i * fretGap);
      canvas.drawLine(
        Offset(padding, y),
        Offset(padding + width, y),
        fretPaint,
      );
    }

    // Draw markers
    for (int i = 0; i < shape.frets.length && i < 6; i++) {
      final fret = shape.frets[i];
      final finger = shape.fingers[i];
      final x = padding + (i * stringGap);

      if (fret == -1) {
        // Muted string - draw X
        final xPaint = Paint()
          ..color = const Color(0xFF888888)
          ..strokeWidth = 1.5
          ..isAntiAlias = true;
        const s = 5.0;
        final cy = topMargin - 10;
        canvas.drawLine(Offset(x - s, cy - s), Offset(x + s, cy + s), xPaint);
        canvas.drawLine(Offset(x + s, cy - s), Offset(x - s, cy + s), xPaint);
      } else if (fret == 0) {
        // Open string - draw O
        canvas.drawCircle(
          Offset(x, topMargin - 10),
          5,
          Paint()
            ..color = const Color(0xFF888888)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..isAntiAlias = true,
        );
      } else {
        // Fingered fret - draw filled circle with finger number
        final relativeFret = shape.baseFret > 1 ? fret - shape.baseFret + 1 : fret;
        final y = topMargin + (relativeFret - 0.5) * fretGap;
        final radius = (fretGap * 0.32).clamp(6.0, 11.0);
        canvas.drawCircle(Offset(x, y), radius, dotPaint);

        if (finger > 0) {
          final labelPainter = TextPainter(
            text: TextSpan(
              text: '$finger',
              style: TextStyle(
                color: Colors.white,
                fontSize: radius * 1.1,
                fontWeight: FontWeight.bold,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          labelPainter.paint(
            canvas,
            Offset(x - labelPainter.width / 2, y - labelPainter.height / 2),
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ChordDiagramPainter oldDelegate) =>
      oldDelegate.shape.name != shape.name;
}
