class TransposeEngine {
  static const List<String> sharpScale = [
    'C',
    'C#',
    'D',
    'D#',
    'E',
    'F',
    'F#',
    'G',
    'G#',
    'A',
    'A#',
    'B',
  ];

  static const List<String> flatScale = [
    'C',
    'Db',
    'D',
    'Eb',
    'E',
    'F',
    'Gb',
    'G',
    'Ab',
    'A',
    'Bb',
    'B',
  ];

  static String transposeChord(String chord, int semitones, {bool? preferFlats}) {
    final match = RegExp(r'^([A-G](?:#|b)?)([^/]*)(?:/([A-G](?:#|b)?))?$')
        .firstMatch(chord.trim());

    if (match == null) {
      return chord;
    }

    final root = match.group(1)!;
    final quality = match.group(2)!;
    final bass = match.group(3) ?? '';
    final useFlats = preferFlats ?? root.endsWith('b');

    final newRoot = _shiftNote(root, semitones, useFlats);
    final newBass = bass.isEmpty ? null : _shiftNote(bass, semitones, useFlats);

    return '$newRoot$quality${newBass != null ? '/$newBass' : ''}';
  }

  static String transposeLine(String line, int semitones, {bool? preferFlats}) {
    if (semitones == 0 && preferFlats == null) {
      return line;
    }

    return line.replaceAllMapped(
      RegExp(r'\[([^\]]+)]'),
      (match) => '[${transposeChord(match.group(1)!, semitones, preferFlats: preferFlats)}]',
    );
  }

  static String formatAccidental(String chord, {required bool preferFlats}) {
    return transposeChord(chord, 0, preferFlats: preferFlats);
  }

  static String _shiftNote(String note, int semitones, bool useFlats) {
    final scale = useFlats ? flatScale : sharpScale;
    final altScale = useFlats ? sharpScale : flatScale;
    final index = scale.indexOf(note);
    final realIndex = index >= 0 ? index : altScale.indexOf(note);

    if (realIndex < 0) {
      return note;
    }

    final newIndex = ((realIndex + semitones) % 12 + 12) % 12;
    return scale[newIndex];
  }
}
