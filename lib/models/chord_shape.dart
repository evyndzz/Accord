class ChordShape {
  final String name;
  final List<int> frets;
  final List<int> fingers;
  final int baseFret;

  const ChordShape({
    required this.name,
    required this.frets,
    required this.fingers,
    this.baseFret = 1,
  });
}

class ChordDictionary {
  static const Map<String, ChordShape> shapes = {
    // Major chords
    'C': ChordShape(name: 'C', frets: [-1, 3, 2, 0, 1, 0], fingers: [0, 3, 2, 0, 1, 0]),
    'D': ChordShape(name: 'D', frets: [-1, -1, 0, 2, 3, 2], fingers: [0, 0, 0, 1, 3, 2]),
    'E': ChordShape(name: 'E', frets: [0, 2, 2, 1, 0, 0], fingers: [0, 2, 3, 1, 0, 0]),
    'F': ChordShape(name: 'F', frets: [1, 3, 3, 2, 1, 1], fingers: [1, 3, 4, 2, 1, 1]),
    'G': ChordShape(name: 'G', frets: [3, 2, 0, 0, 0, 3], fingers: [2, 1, 0, 0, 0, 3]),
    'A': ChordShape(name: 'A', frets: [-1, 0, 2, 2, 2, 0], fingers: [0, 0, 1, 2, 3, 0]),
    'B': ChordShape(name: 'B', frets: [-1, 2, 4, 4, 4, 2], fingers: [0, 1, 2, 3, 4, 1], baseFret: 2),

    // Minor chords
    'Cm': ChordShape(name: 'Cm', frets: [-1, 3, 5, 5, 4, 3], fingers: [0, 1, 3, 4, 2, 1], baseFret: 3),
    'Dm': ChordShape(name: 'Dm', frets: [-1, -1, 0, 2, 3, 1], fingers: [0, 0, 0, 2, 3, 1]),
    'Em': ChordShape(name: 'Em', frets: [0, 2, 2, 0, 0, 0], fingers: [0, 2, 1, 0, 0, 0]),
    'Fm': ChordShape(name: 'Fm', frets: [1, 3, 3, 1, 1, 1], fingers: [1, 3, 4, 1, 1, 1]),
    'Gm': ChordShape(name: 'Gm', frets: [3, 5, 5, 3, 3, 3], fingers: [1, 3, 4, 1, 1, 1], baseFret: 3),
    'Am': ChordShape(name: 'Am', frets: [-1, 0, 2, 2, 1, 0], fingers: [0, 0, 2, 3, 1, 0]),
    'Bm': ChordShape(name: 'Bm', frets: [-1, 2, 4, 4, 3, 2], fingers: [0, 1, 3, 4, 2, 1], baseFret: 2),

    // 7th chords
    'C7': ChordShape(name: 'C7', frets: [-1, 3, 2, 3, 1, 0], fingers: [0, 3, 2, 4, 1, 0]),
    'D7': ChordShape(name: 'D7', frets: [-1, -1, 0, 2, 1, 2], fingers: [0, 0, 0, 2, 1, 3]),
    'E7': ChordShape(name: 'E7', frets: [0, 2, 0, 1, 0, 0], fingers: [0, 2, 0, 1, 0, 0]),
    'F7': ChordShape(name: 'F7', frets: [1, 3, 1, 2, 1, 1], fingers: [1, 3, 1, 2, 1, 1]),
    'G7': ChordShape(name: 'G7', frets: [3, 2, 0, 0, 0, 1], fingers: [3, 2, 0, 0, 0, 1]),
    'A7': ChordShape(name: 'A7', frets: [-1, 0, 2, 0, 2, 0], fingers: [0, 0, 1, 0, 2, 0]),
    'B7': ChordShape(name: 'B7', frets: [-1, 2, 1, 2, 0, 2], fingers: [0, 2, 1, 3, 0, 4]),

    // Minor 7th
    'Am7': ChordShape(name: 'Am7', frets: [-1, 0, 2, 0, 1, 0], fingers: [0, 0, 2, 0, 1, 0]),
    'Em7': ChordShape(name: 'Em7', frets: [0, 2, 0, 0, 0, 0], fingers: [0, 1, 0, 0, 0, 0]),
    'Dm7': ChordShape(name: 'Dm7', frets: [-1, -1, 0, 2, 1, 1], fingers: [0, 0, 0, 2, 1, 1]),

    // Sharp/Flat chords
    'C#m': ChordShape(name: 'C#m', frets: [-1, 4, 6, 6, 5, 4], fingers: [0, 1, 3, 4, 2, 1], baseFret: 4),
    'F#m': ChordShape(name: 'F#m', frets: [2, 4, 4, 2, 2, 2], fingers: [1, 3, 4, 1, 1, 1], baseFret: 2),
    'G#m': ChordShape(name: 'G#m', frets: [4, 6, 6, 4, 4, 4], fingers: [1, 3, 4, 1, 1, 1], baseFret: 4),
    'Bb': ChordShape(name: 'Bb', frets: [-1, 1, 3, 3, 3, 1], fingers: [0, 1, 2, 3, 4, 1]),
    'Eb': ChordShape(name: 'Eb', frets: [-1, -1, 1, 3, 4, 3], fingers: [0, 0, 1, 2, 4, 3]),
    'Ab': ChordShape(name: 'Ab', frets: [4, 6, 6, 5, 4, 4], fingers: [1, 3, 4, 2, 1, 1], baseFret: 4),
    'Db': ChordShape(name: 'Db', frets: [-1, 4, 6, 6, 6, 4], fingers: [0, 1, 2, 3, 4, 1], baseFret: 4),

    // Sus chords
    'Dsus2': ChordShape(name: 'Dsus2', frets: [-1, -1, 0, 2, 3, 0], fingers: [0, 0, 0, 1, 2, 0]),
    'Dsus4': ChordShape(name: 'Dsus4', frets: [-1, -1, 0, 2, 3, 3], fingers: [0, 0, 0, 1, 2, 3]),
    'Asus2': ChordShape(name: 'Asus2', frets: [-1, 0, 2, 2, 0, 0], fingers: [0, 0, 1, 2, 0, 0]),
    'Asus4': ChordShape(name: 'Asus4', frets: [-1, 0, 2, 2, 3, 0], fingers: [0, 0, 1, 2, 3, 0]),

    // Major 7th
    'Cmaj7': ChordShape(name: 'Cmaj7', frets: [-1, 3, 2, 0, 0, 0], fingers: [0, 3, 2, 0, 0, 0]),
    'Dmaj7': ChordShape(name: 'Dmaj7', frets: [-1, -1, 0, 2, 2, 2], fingers: [0, 0, 0, 1, 2, 3]),
    'Emaj7': ChordShape(name: 'Emaj7', frets: [0, 2, 1, 1, 0, 0], fingers: [0, 2, 1, 1, 0, 0]),
    'Fmaj7': ChordShape(name: 'Fmaj7', frets: [-1, -1, 3, 2, 1, 0], fingers: [0, 0, 3, 2, 1, 0]),
    'Gmaj7': ChordShape(name: 'Gmaj7', frets: [3, 2, 0, 0, 0, 2], fingers: [2, 1, 0, 0, 0, 3]),
    'Amaj7': ChordShape(name: 'Amaj7', frets: [-1, 0, 2, 1, 2, 0], fingers: [0, 0, 2, 1, 3, 0]),
    'Bmaj7': ChordShape(name: 'Bmaj7', frets: [-1, 2, 4, 3, 4, 2], fingers: [0, 1, 3, 2, 4, 1], baseFret: 2),

    // Diminished & Half-Diminished (m7b5)
    'Bdim': ChordShape(name: 'Bdim', frets: [-1, 2, 3, 4, 3, -1], fingers: [0, 1, 2, 4, 3, 0], baseFret: 2),
    'Bm7b5': ChordShape(name: 'Bm7b5', frets: [-1, 2, 3, 2, 3, -1], fingers: [0, 1, 3, 2, 4, 0], baseFret: 2),
    'Em7b5': ChordShape(name: 'Em7b5', frets: [0, 1, 2, 0, 3, 0], fingers: [0, 1, 2, 0, 3, 0]),
    'Am7b5': ChordShape(name: 'Am7b5', frets: [-1, 0, 1, 2, 1, -1], fingers: [0, 0, 1, 3, 2, 0]),
    'F#m7b5': ChordShape(name: 'F#m7b5', frets: [2, -1, 2, 2, 1, -1], fingers: [2, 0, 3, 4, 1, 0], baseFret: 2),
    'C#m7b5': ChordShape(name: 'C#m7b5', frets: [-1, 4, 5, 4, 5, -1], fingers: [0, 1, 3, 2, 4, 0], baseFret: 4),

    // 9th, Maj9, m9, Add9
    'Cadd9': ChordShape(name: 'Cadd9', frets: [-1, 3, 2, 0, 3, 0], fingers: [0, 2, 1, 0, 3, 0]),
    'Dadd9': ChordShape(name: 'Dadd9', frets: [-1, -1, 0, 2, 3, 0], fingers: [0, 0, 0, 1, 2, 0]),
    'Gadd9': ChordShape(name: 'Gadd9', frets: [3, 0, 0, 0, 0, 5], fingers: [1, 0, 0, 0, 0, 4]),
    'C9': ChordShape(name: 'C9', frets: [-1, 3, 2, 3, 3, -1], fingers: [0, 2, 1, 3, 3, 0]),
    'D9': ChordShape(name: 'D9', frets: [-1, 5, 4, 5, 5, -1], fingers: [0, 2, 1, 3, 3, 0], baseFret: 4),
    'E9': ChordShape(name: 'E9', frets: [0, 2, 0, 1, 0, 2], fingers: [0, 2, 0, 1, 0, 3]),
    'A9': ChordShape(name: 'A9', frets: [-1, 0, 2, 0, 0, 0], fingers: [0, 0, 1, 0, 0, 0]),
    'Am9': ChordShape(name: 'Am9', frets: [-1, 0, 2, 4, 1, 0], fingers: [0, 0, 2, 4, 1, 0]),
    'Em9': ChordShape(name: 'Em9', frets: [0, 2, 0, 0, 0, 2], fingers: [0, 1, 0, 0, 0, 2]),
    'Cmaj9': ChordShape(name: 'Cmaj9', frets: [-1, 3, 0, 0, 0, 0], fingers: [0, 2, 0, 0, 0, 0]),

    // 7sus4 & Hendrix 7#9
    'A7sus4': ChordShape(name: 'A7sus4', frets: [-1, 0, 2, 0, 3, 0], fingers: [0, 0, 1, 0, 3, 0]),
    'D7sus4': ChordShape(name: 'D7sus4', frets: [-1, -1, 0, 2, 1, 3], fingers: [0, 0, 0, 2, 1, 3]),
    'E7sus4': ChordShape(name: 'E7sus4', frets: [0, 2, 0, 2, 0, 0], fingers: [0, 1, 0, 2, 0, 0]),
    'E7#9': ChordShape(name: 'E7#9', frets: [0, 7, 6, 7, 8, -1], fingers: [0, 2, 1, 3, 4, 0], baseFret: 6),

    // Augmented & 6th
    'Caug': ChordShape(name: 'Caug', frets: [-1, 3, 2, 1, 1, 0], fingers: [0, 4, 3, 1, 2, 0]),
    'Gaug': ChordShape(name: 'Gaug', frets: [3, 2, 1, 0, 0, 3], fingers: [3, 2, 1, 0, 0, 4]),
    'C6': ChordShape(name: 'C6', frets: [-1, 3, 2, 2, 1, 0], fingers: [0, 3, 2, 2, 1, 0]),
    'G6': ChordShape(name: 'G6', frets: [3, 2, 0, 0, 0, 0], fingers: [2, 1, 0, 0, 0, 0]),
  };

  static ChordShape get(String name) {
    // 1. Direct match
    if (shapes.containsKey(name)) {
      return shapes[name]!;
    }

    // 2. Normalisasi accidental misal C# -> Db atau sebaliknya
    final enharmonics = {
      'C#': 'Db', 'Db': 'C#',
      'D#': 'Eb', 'Eb': 'D#',
      'F#': 'Gb', 'Gb': 'F#',
      'G#': 'Ab', 'Ab': 'G#',
      'A#': 'Bb', 'Bb': 'A#',
    };

    for (final entry in enharmonics.entries) {
      if (name.startsWith(entry.key)) {
        final altName = name.replaceFirst(entry.key, entry.value);
        if (shapes.containsKey(altName)) {
          return shapes[altName]!;
        }
      }
    }

    // 3. Fallback jika slash chord misal D/F# -> ambil bentuk root D
    if (name.contains('/')) {
      final base = name.split('/')[0];
      if (shapes.containsKey(base)) {
        return shapes[base]!;
      }
    }

    // 4. Default dummy shape
    return ChordShape(
      name: name,
      frets: [0, 0, 0, 0, 0, 0],
      fingers: [0, 0, 0, 0, 0, 0],
    );
  }
}
