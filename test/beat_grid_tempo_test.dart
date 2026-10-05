import 'package:flutter_test/flutter_test.dart';
import 'package:accord/models/song_line.dart';
import 'package:accord/widgets/chordify_beat_grid.dart';

void main() {
  group('ChordifyBeatGridWidget tempo & meter generation', () {
    test('Calculates 4/4 meter at 120 BPM correctly (500ms per beat)', () {
      final lines = [
        const SongLine(lineIndex: 0, startTimeMs: 0, rawLine: '[C]'),
        const SongLine(lineIndex: 1, startTimeMs: 2000, rawLine: '[G]'),
      ];

      // 4000ms duration at 120 BPM = 8 beats = 2 full bars of 4 beats
      final beats = ChordifyBeatGridWidget.generateBeats(
        lines: lines,
        totalDurationMs: 4000,
        bpm: 120.0,
        timeSignature: '4/4',
      );

      expect(beats.length, 8);
      // Beat 0 (0-500ms) -> C
      expect(beats[0].chords, ['C']);
      expect(beats[0].beatInBar, 0);
      expect(beats[0].barIndex, 0);

      // Beat 1, 2, 3 -> continuation of C
      expect(beats[1].isContinuation, isTrue);
      expect(beats[2].isContinuation, isTrue);
      expect(beats[3].isContinuation, isTrue);

      // Beat 4 (2000ms) -> G in bar 1, beat 0
      expect(beats[4].chords, ['G']);
      expect(beats[4].beatInBar, 0);
      expect(beats[4].barIndex, 1);
    });

    test('Calculates 3/4 meter at 60 BPM correctly (1000ms per beat, 3 beats/bar)', () {
      final lines = [
        const SongLine(lineIndex: 0, startTimeMs: 0, rawLine: '[D]'),
        const SongLine(lineIndex: 1, startTimeMs: 3000, rawLine: '[A]'),
      ];

      // 6000ms duration at 60 BPM = 6 beats = 2 full bars of 3 beats
      final beats = ChordifyBeatGridWidget.generateBeats(
        lines: lines,
        totalDurationMs: 6000,
        bpm: 60.0,
        timeSignature: '3/4',
      );

      expect(beats.length, 6);
      // Bar 0
      expect(beats[0].beatInBar, 0);
      expect(beats[0].barIndex, 0);
      expect(beats[0].chords, ['D']);

      expect(beats[1].beatInBar, 1);
      expect(beats[1].isContinuation, isTrue);

      expect(beats[2].beatInBar, 2);
      expect(beats[2].isContinuation, isTrue);

      // Bar 1 (beat 3 = 3000ms)
      expect(beats[3].beatInBar, 0);
      expect(beats[3].barIndex, 1);
      expect(beats[3].chords, ['A']);
    });

    test('Handles multiple chords within the same beat box', () {
      final lines = [
        const SongLine(lineIndex: 0, startTimeMs: 0, rawLine: '[C] [G]'),
      ];

      final beats = ChordifyBeatGridWidget.generateBeats(
        lines: lines,
        totalDurationMs: 2000,
        bpm: 120.0,
        timeSignature: '4/4',
      );

      expect(beats.isNotEmpty, isTrue);
      expect(beats[0].chords, ['C', 'G']);
    });
  });
}
