import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accord/models/piano_chord.dart';
import 'package:accord/models/song_line.dart';
import 'package:accord/widgets/chordify_beat_grid.dart';
import 'package:accord/widgets/piano_chord_diagram.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PianoChordEngine Tests', () {
    test('Calculates C Major voicing correctly', () {
      final voicing = PianoChordEngine.getVoicing('C');
      expect(voicing.chordName, 'C');
      expect(voicing.pressedKeys, containsAll([0, 4, 7]));
    });

    test('Calculates Bb Major voicing matching Chordify screenshot', () {
      final voicing = PianoChordEngine.getVoicing('Bb');
      expect(voicing.chordName, 'Bb');
      expect(voicing.pressedKeys, containsAll([10, 14, 17]));
    });

    test('Calculates Bbm voicing matching Chordify screenshot', () {
      final voicing = PianoChordEngine.getVoicing('Bbm');
      expect(voicing.chordName, 'Bbm');
      expect(voicing.pressedKeys, containsAll([10, 13, 17]));
    });

    test('Calculates A/C# Slash Chord voicing matching Chordify screenshot', () {
      final voicing = PianoChordEngine.getVoicing('A/C#');
      expect(voicing.chordName, 'A/C#');
      expect(voicing.pressedKeys, contains(1)); // Bass C#
      expect(voicing.pressedKeys, contains(9)); // A
    });

    test('Handles Rest and Empty Chords', () {
      final rest = PianoChordEngine.getVoicing('𝄽');
      expect(rest.pressedKeys, isEmpty);

      final blank = PianoChordEngine.getVoicing('');
      expect(blank.pressedKeys, isEmpty);
    });

    testWidgets('PianoChordDiagramWidget renders correctly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PianoChordDiagramWidget(chordName: 'Bb', isCurrent: true),
          ),
        ),
      );
      expect(find.text('Bb'), findsOneWidget);
    });

    test('generateBeats maps chords into 4-beat bars correctly', () {
      final lines = [
        const SongLine(lineIndex: 0, startTimeMs: 0, rawLine: '[Bb] [Bbm]'),
        const SongLine(lineIndex: 1, startTimeMs: 4000, rawLine: '[A/C#]'),
      ];
      final beats = ChordifyBeatGridWidget.generateBeats(
        lines: lines,
        totalDurationMs: 8000,
      );
      expect(beats.length, greaterThanOrEqualTo(8)); // 2 bars * 4 beats = 8
      expect(beats[0].primaryChord, 'Bb');
      expect(beats[0].hasChord, isTrue);
    });

    testWidgets('ChordifyBeatGridWidget renders beat cells', (tester) async {
      final lines = [
        const SongLine(lineIndex: 0, startTimeMs: 0, rawLine: '[Bb] [Bbm]'),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChordifyBeatGridWidget(
              lines: lines,
              positionMs: 500,
              totalDurationMs: 4000,
              onSeek: (_) {},
            ),
          ),
        ),
      );
      expect(find.text('Bb'), findsOneWidget);
      expect(find.text('Bbm'), findsOneWidget);
    });

    test('ChordTimelineExtractor extracts chronological chord sequence accurately', () {
      final lines = [
        const SongLine(lineIndex: 0, startTimeMs: 0, rawLine: '[D]'),
        const SongLine(lineIndex: 1, startTimeMs: 4000, rawLine: '[G]'),
        const SongLine(lineIndex: 2, startTimeMs: 4200, rawLine: 'Tercurah darah Tuhanku'), // Pure lyric, no chords
        const SongLine(lineIndex: 3, startTimeMs: 8000, rawLine: '[D]'),
        const SongLine(lineIndex: 4, startTimeMs: 12000, rawLine: '[Em]'),
        const SongLine(lineIndex: 5, startTimeMs: 16000, rawLine: '[A]'),
      ];

      final timeline = ChordTimelineExtractor.extract(lines: lines);
      expect(timeline.length, equals(5));
      expect(timeline[0].chord, equals('D'));
      expect(timeline[0].startTimeMs, equals(0));
      expect(timeline[1].chord, equals('G'));
      expect(timeline[1].startTimeMs, equals(4000));
      expect(timeline[2].chord, equals('D'));
      expect(timeline[2].startTimeMs, equals(8000));
      expect(timeline[3].chord, equals('Em'));
      expect(timeline[3].startTimeMs, equals(12000));
      expect(timeline[4].chord, equals('A'));
      expect(timeline[4].startTimeMs, equals(16000));
    });

    testWidgets('PianoChordDiagramWidget renders badgeText correctly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PianoChordDiagramWidget(
              chordName: 'Em',
              badgeText: '➔ BERIKUTNYA',
              isCurrent: false,
            ),
          ),
        ),
      );
      expect(find.text('Em'), findsOneWidget);
      expect(find.text('➔ BERIKUTNYA'), findsOneWidget);
    });
  });
}
