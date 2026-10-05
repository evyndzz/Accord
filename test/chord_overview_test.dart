import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accord/models/song_line.dart';
import 'package:accord/widgets/chord_overview_grid.dart';

void main() {
  testWidgets('ChordOverviewGridWidget renders rows, bars, and handles seeks', (tester) async {
    final lines = [
      const SongLine(
        lineIndex: 0,
        startTimeMs: 0,
        rawLine: '[C] [G] [Am] [F]',
      ),
      const SongLine(
        lineIndex: 1,
        startTimeMs: 4000,
        rawLine: '[Dm] [Em] [F] [G]',
      ),
    ];

    int seekTarget = -1;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            width: 400,
            child: ChordOverviewGridWidget(
              lines: lines,
              positionMs: 1000,
              totalDurationMs: 8000,
              bpm: 120.0,
              timeSignature: '4/4',
              transposeOffset: 0,
              onSeek: (ms) => seekTarget = ms,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify presence of chord text in the overview
    expect(find.text('C'), findsWidgets);
    expect(find.text('G'), findsWidgets);

    // Verify sub-header with total bars and BPM
    expect(find.textContaining('BAR'), findsWidgets);
    expect(find.textContaining('4/4 • 120 BPM'), findsOneWidget);

    // Verify pill toggles for 4 Bar and 2 Bar
    expect(find.text('4 Bar'), findsOneWidget);
    expect(find.text('2 Bar'), findsOneWidget);

    // Tap 2 Bar pill
    await tester.tap(find.text('2 Bar'));
    await tester.pumpAndSettle();

    // Tap on cell to test seek
    await tester.tap(find.text('C').first);
    expect(seekTarget, greaterThanOrEqualTo(0));
  });
}
