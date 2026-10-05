import 'package:flutter_test/flutter_test.dart';
import 'package:accord/models/piano_chord.dart';
import 'package:accord/models/chord_shape.dart';
import 'package:accord/services/accidental_preference.dart';
import 'package:accord/utils/transposer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PianoChordEngine Advance Chords Voicing', () {
    test('Half-diminished (m7b5) has correct pitch classes', () {
      // C root = 0. m7b5 intervals: [0, 3, 6, 10] -> C, Eb, Gb, Bb (0, 3, 6, 10)
      final voicing = PianoChordEngine.getVoicing('Cm7b5');
      final pitchClasses = voicing.pressedKeys.map((k) => k % 12).toSet();
      expect(pitchClasses, containsAll([0, 3, 6, 10]));
    });

    test('Dominant 9th has correct pitch classes', () {
      // C9 intervals: [0, 4, 7, 10, 14] -> C, E, G, Bb, D (0, 4, 7, 10, 2)
      final voicing = PianoChordEngine.getVoicing('C9');
      final pitchClasses = voicing.pressedKeys.map((k) => k % 12).toSet();
      expect(pitchClasses, containsAll([0, 4, 7, 10, 2]));
    });

    test('Major 9th (maj9) has correct pitch classes', () {
      // Cmaj9 intervals: [0, 4, 7, 11, 14] -> C, E, G, B, D (0, 4, 7, 11, 2)
      final voicing = PianoChordEngine.getVoicing('Cmaj9');
      final pitchClasses = voicing.pressedKeys.map((k) => k % 12).toSet();
      expect(pitchClasses, containsAll([0, 4, 7, 11, 2]));
    });

    test('Minor 9th (m9) has correct pitch classes', () {
      // Am9: A=9. [9, 0, 4, 7, 11] -> A, C, E, G, B
      final voicing = PianoChordEngine.getVoicing('Am9');
      final pitchClasses = voicing.pressedKeys.map((k) => k % 12).toSet();
      expect(pitchClasses, containsAll([9, 0, 4, 7, 11]));
    });

    test('7sus4 has correct pitch classes', () {
      // D7sus4: D=2. [0, 5, 7, 10] -> D, G, A, C (2, 7, 9, 0)
      final voicing = PianoChordEngine.getVoicing('D7sus4');
      final pitchClasses = voicing.pressedKeys.map((k) => k % 12).toSet();
      expect(pitchClasses, containsAll([2, 7, 9, 0]));
    });

    test('Hendrix 7#9 has correct pitch classes', () {
      // E7#9: E=4. [0, 4, 7, 10, 15] -> E, G#, B, D, G (4, 8, 11, 2, 7)
      final voicing = PianoChordEngine.getVoicing('E7#9');
      final pitchClasses = voicing.pressedKeys.map((k) => k % 12).toSet();
      expect(pitchClasses, containsAll([4, 8, 11, 2, 7]));
    });

    test('6/9 has correct pitch classes', () {
      // C6/9: C=0. [0, 4, 7, 9, 14] -> C, E, G, A, D (0, 4, 7, 9, 2)
      final voicing = PianoChordEngine.getVoicing('C6/9');
      final pitchClasses = voicing.pressedKeys.map((k) => k % 12).toSet();
      expect(pitchClasses, containsAll([0, 4, 7, 9, 2]));
    });

    test('Minor Major 7th (mmaj7) has correct pitch classes', () {
      // Cmmaj7: C=0. [0, 3, 7, 11] -> C, Eb, G, B (0, 3, 7, 11)
      final voicing = PianoChordEngine.getVoicing('Cmmaj7');
      final pitchClasses = voicing.pressedKeys.map((k) => k % 12).toSet();
      expect(pitchClasses, containsAll([0, 3, 7, 11]));
    });
  });

  group('ChordDictionary Advance Shapes', () {
    test('finds registered advance chords', () {
      final bdim = ChordDictionary.get('Bm7b5');
      expect(bdim.name, 'Bm7b5');
      expect(bdim.frets.length, 6);

      final cadd9 = ChordDictionary.get('Cadd9');
      expect(cadd9.name, 'Cadd9');
    });

    test('enharmonic fallback works properly', () {
      // C#m should match C#m or fallback
      final cSharpM = ChordDictionary.get('C#m');
      expect(cSharpM.name, 'C#m');

      // Db should match Db or C#
      final db = ChordDictionary.get('Db');
      expect(db.frets.length, 6);
    });
  });

  group('Accidental Preference & Formatting', () {
    test('formatWithNotation converts sharp to flat when flat selected', () {
      expect(
        AccidentalPreferenceService.formatWithNotation('C#', AccidentalNotation.flat),
        'Db',
      );
      expect(
        AccidentalPreferenceService.formatWithNotation('F#m7b5', AccidentalNotation.flat),
        'Gbm7b5',
      );
      expect(
        AccidentalPreferenceService.formatWithNotation('D/F#', AccidentalNotation.flat),
        'D/Gb',
      );
    });

    test('formatWithNotation converts flat to sharp when sharp selected', () {
      expect(
        AccidentalPreferenceService.formatWithNotation('Db', AccidentalNotation.sharp),
        'C#',
      );
      expect(
        AccidentalPreferenceService.formatWithNotation('Bbm', AccidentalNotation.sharp),
        'A#m',
      );
      expect(
        AccidentalPreferenceService.formatWithNotation('Eb/G', AccidentalNotation.sharp),
        'D#/G',
      );
    });

    test('TransposeEngine.formatAccidental works with preferFlats', () {
      expect(TransposeEngine.formatAccidental('C#m', preferFlats: true), 'Dbm');
      expect(TransposeEngine.formatAccidental('Dbm', preferFlats: false), 'C#m');
    });
  });
}

