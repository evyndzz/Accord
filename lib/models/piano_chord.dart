import 'song_line.dart';
import '../utils/chord_parser.dart';
import '../utils/transposer.dart';

/// Event chord dalam urutan linimasa waktu lagu
class TimedChordEvent {
  final int startTimeMs;
  final String chord;

  const TimedChordEvent({
    required this.startTimeMs,
    required this.chord,
  });
}

/// Helper untuk mengekstrak urutan kronologis chord dalam sebuah lagu
class ChordTimelineExtractor {
  static List<TimedChordEvent> extract({
    required List<SongLine> lines,
    int transposeOffset = 0,
    double bpm = 120.0,
  }) {
    if (lines.isEmpty) return const [];
    final effectiveBpm = bpm > 0 ? bpm : 120.0;
    final beatDurMs = (60000.0 / effectiveBpm).round();

    final events = <TimedChordEvent>[];
    final bool hasAnyTimestamp = lines.any((l) => l.startTimeMs > 0);

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lineTime = hasAnyTimestamp ? line.startTimeMs : (i * 3000);
      final transposed = TransposeEngine.transposeLine(line.rawLine, transposeOffset);
      final parsed = ChordParser.parse(transposed);
      if (parsed.chords.isEmpty) continue;

      if (parsed.chords.length == 1) {
        events.add(TimedChordEvent(
          startTimeMs: lineTime,
          chord: parsed.chords.first.chord,
        ));
      } else {
        final count = parsed.chords.length;
        if (parsed.plainText.trim().isEmpty) {
          // Baris khusus deretan chord (contoh: [D] [G] [Em])
          int nextTime = lineTime + (count * beatDurMs);
          for (int j = i + 1; j < lines.length; j++) {
            final t = hasAnyTimestamp ? lines[j].startTimeMs : (j * 3000);
            if (t > lineTime) {
              final nextParsed = ChordParser.parse(lines[j].rawLine);
              if (nextParsed.chords.isNotEmpty) {
                nextTime = t;
                break;
              }
            }
          }
          final totalDur = (nextTime > lineTime) ? (nextTime - lineTime) : (count * beatDurMs);
          final slotDur = (totalDur / count).round();
          for (int c = 0; c < count; c++) {
            events.add(TimedChordEvent(
              startTimeMs: lineTime + (c * slotDur),
              chord: parsed.chords[c].chord,
            ));
          }
        } else {
          // Baris lirik dengan chord tertanam di kata tertentu
          final totalChars = parsed.plainText.length;
          int nextTime = lineTime + (count * beatDurMs * 2);
          for (int j = i + 1; j < lines.length; j++) {
            final t = hasAnyTimestamp ? lines[j].startTimeMs : (j * 3000);
            if (t > lineTime) {
              nextTime = t;
              break;
            }
          }
          final totalDur = (nextTime > lineTime) ? (nextTime - lineTime) : 4000;
          for (int c = 0; c < count; c++) {
            final charIdx = parsed.chords[c].charIndex;
            final offset = totalChars > 0 ? ((charIdx / totalChars) * totalDur).round() : (c * 500);
            events.add(TimedChordEvent(
              startTimeMs: lineTime + offset,
              chord: parsed.chords[c].chord,
            ));
          }
        }
      }
    }

    events.sort((a, b) => a.startTimeMs.compareTo(b.startTimeMs));
    return events;
  }
}

/// Model dan helper untuk menentukan not dan tuts piano yang ditekan pada sebuah akord.
class PianoKeyNote {
  final int semitone; // 0 = C3, 1 = C#3, ... 11 = B3, 12 = C4, ... 17 = F4
  final bool isBlack;
  final String noteName;

  const PianoKeyNote({
    required this.semitone,
    required this.isBlack,
    required this.noteName,
  });
}

class PianoChordVoicing {
  final String chordName;
  final List<int> pressedKeys; // Daftar indeks semitone (0 .. 17) yang ditekan

  const PianoChordVoicing({
    required this.chordName,
    required this.pressedKeys,
  });

  bool isKeyPressed(int semitone) => pressedKeys.contains(semitone);

  List<String> get notes {
    final uniqueClasses = <int>{};
    final list = <String>[];
    for (final k in pressedKeys) {
      final pc = k % 12;
      if (uniqueClasses.add(pc)) {
        list.add(PianoChordEngine.pitchNames[pc]);
      }
    }
    return list;
  }
}

class PianoChordEngine {
  // Rentang tuts: C3 (0) sampai F4 (17) -> 11 tuts putih, 7 tuts hitam
  static const int totalSemitones = 18;

  // Daftar nama nada 12 pitch class
  static const List<String> pitchNames = [
    'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'
  ];

  static const Set<int> blackKeyClasses = {1, 3, 6, 8, 10};

  static bool isBlackKey(int semitone) {
    return blackKeyClasses.contains(semitone % 12);
  }

  /// Parsing nama akord ke semitone root (0..11)
  static int? getRootPitchClass(String rootStr) {
    final cleaned = rootStr.trim();
    if (cleaned.isEmpty) return null;

    final norm = cleaned
        .replaceAll('♯', '#')
        .replaceAll('♭', 'b');

    // Cek 2 karakter dulu (misal C#, Bb, F#)
    if (norm.length >= 2) {
      final two = norm.substring(0, 2);
      switch (two) {
        case 'C#': case 'Db': return 1;
        case 'D#': case 'Eb': return 3;
        case 'F#': case 'Gb': return 6;
        case 'G#': case 'Ab': return 8;
        case 'A#': case 'Bb': return 10;
      }
    }

    // Cek 1 karakter
    final one = norm.substring(0, 1).toUpperCase();
    switch (one) {
      case 'C': return 0;
      case 'D': return 2;
      case 'E': return 4;
      case 'F': return 5;
      case 'G': return 7;
      case 'A': return 9;
      case 'B': return 11;
    }
    return null;
  }

  /// Menghitung tuts mana saja yang ditekan untuk akord tertentu
  static PianoChordVoicing getVoicing(String rawChordName) {
    final chord = rawChordName.trim();
    if (chord.isEmpty || chord == '--' || chord == '𝄽' || chord.toLowerCase() == 'nc' || chord.toLowerCase() == 'rest') {
      return PianoChordVoicing(chordName: chord.isEmpty ? '--' : chord, pressedKeys: const []);
    }

    // Cek apakah ada slash chord (misal A/C#, G/B, D/F#)
    String mainChord = chord;
    String? bassStr;
    if (chord.contains('/')) {
      final parts = chord.split('/');
      final candidateBass = parts.length > 1 ? parts[1].trim() : '';
      if (candidateBass.isNotEmpty && RegExp(r'^[A-G]').hasMatch(candidateBass)) {
        mainChord = parts[0].trim();
        bassStr = candidateBass;
      } else {
        mainChord = chord;
        bassStr = null;
      }
    }

    // Cari root pitch class
    int rootPitch = 0;
    String qualityPart = '';
    
    // Cek root dengan accidentals
    final normalized = mainChord.replaceAll('♯', '#').replaceAll('♭', 'b');
    if (normalized.length >= 2 && (normalized[1] == '#' || normalized[1] == 'b')) {
      rootPitch = getRootPitchClass(normalized.substring(0, 2)) ?? 0;
      qualityPart = normalized.substring(2);
    } else if (normalized.isNotEmpty) {
      rootPitch = getRootPitchClass(normalized.substring(0, 1)) ?? 0;
      qualityPart = normalized.substring(1);
    }

    // Tentukan interval berdasarkan chord quality
    final q = qualityPart.toLowerCase();
    List<int> intervals;

    if (q == 'm' || q == 'min' || q == '-') {
      intervals = [0, 3, 7]; // Minor
    } else if (q == 'm7' || q == 'min7') {
      intervals = [0, 3, 7, 10]; // Minor 7th
    } else if (q == 'maj7' || q == 'm7+' || q == 'major7') {
      intervals = [0, 4, 7, 11]; // Major 7th
    } else if (q == '7' || q == 'dom7') {
      intervals = [0, 4, 7, 10]; // Dominant 7th
    } else if (q == 'm7b5' || q == 'm7(b5)' || q == 'ø' || q == 'half-dim') {
      intervals = [0, 3, 6, 10]; // Half-diminished
    } else if (q == '7sus4' || q == '7sus') {
      intervals = [0, 5, 7, 10]; // 7sus4
    } else if (q == '9' || q == 'dom9') {
      intervals = [0, 4, 7, 10, 14]; // 9th
    } else if (q == 'maj9' || q == 'm9+' || q == 'major9') {
      intervals = [0, 4, 7, 11, 14]; // Major 9th
    } else if (q == 'm9' || q == 'min9') {
      intervals = [0, 3, 7, 10, 14]; // Minor 9th
    } else if (q == 'madd9') {
      intervals = [0, 3, 7, 14]; // Minor add9
    } else if (q == '11') {
      intervals = [0, 4, 7, 10, 14, 17]; // 11th
    } else if (q == 'm11') {
      intervals = [0, 3, 7, 10, 14, 17]; // Minor 11th
    } else if (q == '13') {
      intervals = [0, 4, 7, 10, 14, 21]; // 13th
    } else if (q == 'maj13') {
      intervals = [0, 4, 7, 11, 14, 21]; // Major 13th
    } else if (q == 'm13') {
      intervals = [0, 3, 7, 10, 14, 21]; // Minor 13th
    } else if (q == '7#9' || q == '7(#9)') {
      intervals = [0, 4, 7, 10, 15]; // Hendrix chord
    } else if (q == '7b9' || q == '7(b9)') {
      intervals = [0, 4, 7, 10, 13]; // 7b9
    } else if (q == '7#5' || q == '7(#5)' || q == 'aug7' || q == '+7' || q == '7aug') {
      intervals = [0, 4, 8, 10]; // 7#5 / aug7
    } else if (q == '7b5' || q == '7(b5)') {
      intervals = [0, 4, 6, 10]; // 7b5
    } else if (q == '6/9' || q == '69') {
      intervals = [0, 4, 7, 9, 14]; // 6/9
    } else if (q == 'm6/9' || q == 'm69') {
      intervals = [0, 3, 7, 9, 14]; // Minor 6/9
    } else if (q == 'mmaj7' || q == 'm(maj7)' || q == 'minmaj7' || q == 'mma7') {
      intervals = [0, 3, 7, 11]; // Minor major 7th
    } else if (q == 'mmaj9' || q == 'm(maj9)' || q == 'minmaj9') {
      intervals = [0, 3, 7, 11, 14]; // Minor major 9th
    } else if (q == '9sus4' || q == '9sus') {
      intervals = [0, 5, 7, 10, 14]; // 9sus4
    } else if (q == 'dim' || q == 'diminished' || q == '°') {
      intervals = [0, 3, 6]; // Diminished
    } else if (q == 'dim7' || q == '°7') {
      intervals = [0, 3, 6, 9]; // Diminished 7th
    } else if (q == 'aug' || q == '+') {
      intervals = [0, 4, 8]; // Augmented
    } else if (q == 'sus2') {
      intervals = [0, 2, 7]; // Sus2
    } else if (q == 'sus4' || q == 'sus') {
      intervals = [0, 5, 7]; // Sus4
    } else if (q == '6') {
      intervals = [0, 4, 7, 9]; // 6th
    } else if (q == 'm6') {
      intervals = [0, 3, 7, 9]; // Minor 6th
    } else if (q == 'add9' || q == 'add2') {
      intervals = [0, 4, 7, 14]; // Add9
    } else if (q == '5') {
      intervals = [0, 7]; // Power chord
    } else if (q == 'maj' || q == 'major' || q == '') {
      intervals = [0, 4, 7]; // Major (explicit 'maj' suffix or bare root)
    } else {
      intervals = [0, 4, 7]; // Default Major
    }

    // Bangun daftar semitone mentah
    final rawSemitones = <int>[];
    for (final interval in intervals) {
      rawSemitones.add(rootPitch + interval);
    }

    // Tambahkan bass note jika slash chord
    int? bassPitch;
    if (bassStr != null) {
      bassPitch = getRootPitchClass(bassStr);
    }

    // Inversi / Penataan oktaf agar muat di rentang tuts C3 (0) s/d F4 (17)
    final resultKeys = <int>{};

    if (bassPitch != null) {
      // Pasang bass note pada oktaf terendah yang tersedia
      int b = bassPitch % 12;
      resultKeys.add(b);
      // Letakkan nada-nada akord lainnya di atas bass
      for (final s in rawSemitones) {
        int pitch = s % 12;
        int note = pitch;
        if (note <= b) {
          note += 12;
        }
        if (note < totalSemitones) {
          resultKeys.add(note);
        } else {
          resultKeys.add(pitch);
        }
      }
    } else {
      for (final s in rawSemitones) {
        int note = s;
        while (note >= totalSemitones) {
          note -= 12;
        }
        while (note < 0) {
          note += 12;
        }
        if (note < totalSemitones) {
          resultKeys.add(note);
        }
      }
    }

    final sorted = resultKeys.toList()..sort();
    return PianoChordVoicing(chordName: chord, pressedKeys: sorted);
  }
}
