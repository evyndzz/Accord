import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:accord/utils/chordify_midi_parser.dart';

void main() {
  group('ChordifyMidiParser Tests', () {
    test('Correctly parses Chordify Time Aligned MIDI file', () async {
      final file = File('contoh/Chordify_IGNITE-GKI-Ku-Mau-Berjalan-dengan-Juruslamatku-Pop-Rohani-KK-455-Live_Time_Aligned_130_BPM.mid');
      expect(file.existsSync(), isTrue);

      final result = await ChordifyMidiParser.parseFile(file);

      // Verify Title & Metadata
      expect(result.title, contains('Ku Mau Berjalan'));
      expect(result.bpm.round(), equals(130));
      expect(result.timeSignature, equals('4/4'));
      expect(result.startBeatOffsetMs, greaterThan(2000));
      expect(result.startBeatOffsetMs, lessThan(2600));

      // Verify Chords extraction (125 chords)
      expect(result.chords.length, equals(125));

      // Verify First 8 chords match the user's PDF sheet:
      // Bar 1: Bb
      // Bar 2: Bbm
      // Bar 3: F/A
      // Bar 4: E/Ab
      // Bar 5: Gm7
      // Bar 6: Db, C
      // Bar 7: F
      expect(result.chords[0].chord, equals('Bb'));
      expect(result.chords[1].chord, equals('Bbm'));
      expect(result.chords[2].chord, equals('F/A'));
      expect(result.chords[3].chord, equals('E/Ab'));
      expect(result.chords[4].chord, equals('Gm7'));
      expect(result.chords[5].chord, equals('Db'));
      expect(result.chords[6].chord, equals('C'));
      expect(result.chords[7].chord, equals('F'));
    });

    test('Correctly parses Chordify Quantized MIDI file', () async {
      final file = File('contoh/Chordify_IGNITE-GKI-Ku-Mau-Berjalan-dengan-Juruslamatku-Pop-Rohani-KK-455-Live_Quantized_at_130_BPM.mid');
      expect(file.existsSync(), isTrue);

      final result = await ChordifyMidiParser.parseFile(file);

      expect(result.bpm.round(), equals(130));
      expect(result.timeSignature, equals('4/4'));
      expect(result.chords.length, equals(125));
      expect(result.chords[0].chord, equals('Bb'));
      expect(result.chords[1].chord, equals('Bbm'));
    });
  });
}

