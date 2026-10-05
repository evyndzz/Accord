import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Representasi akord hasil parsing dari file MIDI Chordify
class ChordifyMidiChordItem {
  final String chord;
  final int startTimeMs;
  final int tick;

  const ChordifyMidiChordItem({
    required this.chord,
    required this.startTimeMs,
    required this.tick,
  });

  @override
  String toString() => '[$chord] at ${startTimeMs}ms';
}

/// Hasil lengkap dari proses ekstraksi file MIDI Chordify
class ChordifyMidiResult {
  final String title;
  final double bpm;
  final String timeSignature;
  final int startBeatOffsetMs;
  final List<ChordifyMidiChordItem> chords;

  const ChordifyMidiResult({
    required this.title,
    required this.bpm,
    required this.timeSignature,
    required this.startBeatOffsetMs,
    required this.chords,
  });
}

/// Parser mandiri dan ringan untuk membaca file MIDI hasil unduhan Chordify
class ChordifyMidiParser {
  static const List<String> _pitchNamesFlat = [
    'C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B'
  ];

  static const List<String> _pitchNamesSharp = [
    'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'
  ];

  /// Parse dari file langsung di filesystem
  static Future<ChordifyMidiResult> parseFile(File file) async {
    final bytes = await file.readAsBytes();
    final filename = file.uri.pathSegments.isNotEmpty ? file.uri.pathSegments.last : 'Lagu Chordify';
    return parseBytes(bytes, fallbackTitle: filename);
  }

  /// Parse dari byte array (misal dari FilePicker Result)
  static ChordifyMidiResult parseBytes(Uint8List bytes, {String fallbackTitle = 'Lagu Chordify'}) {
    if (bytes.length < 14) {
      throw FormatException('Ukuran file terlalu kecil untuk format MIDI.');
    }

    // Periksa Header MThd
    final headerTag = String.fromCharCodes(bytes.sublist(0, 4));
    if (headerTag != 'MThd') {
      throw FormatException('Format file bukan Standard MIDI File ($headerTag).');
    }

    final byteData = ByteData.sublistView(bytes);
    final timeDivision = byteData.getUint16(12, Endian.big);

    if (timeDivision & 0x8000 != 0) {
      throw FormatException('Format time division SMPTE belum didukung.');
    }

    // Ekstraksi track chunks
    final tracks = <Uint8List>[];
    int pos = 14;
    while (pos + 8 <= bytes.length) {
      final chunkTag = String.fromCharCodes(bytes.sublist(pos, pos + 4));
      final chunkLen = byteData.getUint32(pos + 4, Endian.big);
      pos += 8;
      if (chunkTag == 'MTrk') {
        final end = math.min(pos + chunkLen, bytes.length);
        tracks.add(bytes.sublist(pos, end));
      }
      pos += chunkLen;
    }

    if (tracks.isEmpty) {
      throw FormatException('Tidak ada track MIDI yang ditemukan.');
    }

    // 1. Ekstraksi Tempo, Time Signature, dan Nama Track dari Track 0 (atau track lain)
    double detectedBpm = 120.0;
    String detectedTimeSignature = '4/4';
    String? detectedTitle;

    for (final trackData in tracks) {
      _scanMetaEvents(trackData, (metaType, data) {
        if (metaType == 0x51 && data.length >= 3) {
          // Set Tempo: microseconds per quarter note
          final uspqn = (data[0] << 16) | (data[1] << 8) | data[2];
          if (uspqn > 0) {
            detectedBpm = (60000000.0 / uspqn);
          }
        } else if (metaType == 0x58 && data.isNotEmpty) {
          // Time Signature
          final num = data[0];
          final den = data.length > 1 ? math.pow(2, data[1]).toInt() : 4;
          if (num > 1) { // abaikan 1/4 lead-in jika ada
            detectedTimeSignature = '$num/$den';
          }
        } else if ((metaType == 0x01 || metaType == 0x03) && detectedTitle == null) {
          final text = String.fromCharCodes(data).trim();
          if (text.isNotEmpty && !text.toLowerCase().contains('chordify') && !text.toLowerCase().contains('track')) {
            detectedTitle = text;
          }
        }
      });
    }

    // 2. Baca event notasi akord (Track 1 untuk nada akord, Track 2 untuk nada bass)
    // Jika track >= 2, gunakan Track 1 untuk akord dan Track 2 untuk bass
    final chordTrack = tracks.length > 1 ? tracks[1] : tracks[0];
    final bassTrack = tracks.length > 2 ? tracks[2] : null;

    final chordEvents = _parseNoteEvents(chordTrack);
    final bassEvents = bassTrack != null ? _parseNoteEvents(bassTrack) : <_NoteEvent>[];

    // Kelompokkan nada akord yang menyala di tick yang sama
    final chordGroups = <int, List<int>>{};
    for (final ev in chordEvents) {
      if (ev.isOn) {
        chordGroups.putIfAbsent(ev.tick, () => []).add(ev.note);
      }
    }

    // Petakan nada bass berdasarkan tick
    final bassMap = <int, int>{};
    for (final ev in bassEvents) {
      if (ev.isOn) {
        bassMap[ev.tick] = ev.note;
      }
    }

    // Tentukan referensi accidental (b atau #) berdasarkan nada yang dominan
    final useFlats = _preferFlats(chordGroups.values);

    // Hitung konversi tick ke milidetik
    final msPerTick = (60000.0 / detectedBpm) / timeDivision;

    final sortedTicks = chordGroups.keys.toList()..sort();
    final resultChords = <ChordifyMidiChordItem>[];
    int startOffsetMs = 0;

    for (final tick in sortedTicks) {
      final notes = chordGroups[tick]!;
      if (notes.isEmpty) continue;

      // Cari bass note yang paling cocok di tick yang sama atau terdekat (toleransi ±20 tick)
      int? bassNote = bassMap[tick];
      if (bassNote == null && bassMap.isNotEmpty) {
        for (final bTick in bassMap.keys) {
          if ((bTick - tick).abs() <= 24) {
            bassNote = bassMap[bTick];
            break;
          }
        }
      }

      final chordName = identifyChord(notes, bassNote: bassNote, useFlats: useFlats);
      final ms = (tick * msPerTick).round();

      if (resultChords.isEmpty) {
        startOffsetMs = ms;
      }

      resultChords.add(ChordifyMidiChordItem(
        chord: chordName,
        startTimeMs: ms,
        tick: tick,
      ));
    }

    // Bersihkan judul lagu dari nama file fallback jika detectedTitle masih kosong
    String cleanTitle = detectedTitle ?? fallbackTitle;
    cleanTitle = cleanTitle
        .replaceAll(RegExp(r'\.mid$', caseSensitive: false), '')
        .replaceAll(RegExp(r'^Chordify_', caseSensitive: false), '')
        .replaceAll(RegExp(r'_Time_Aligned.*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'_Quantized.*$', caseSensitive: false), '')
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return ChordifyMidiResult(
      title: cleanTitle.isNotEmpty ? cleanTitle : 'Lagu Chordify',
      bpm: detectedBpm,
      timeSignature: detectedTimeSignature,
      startBeatOffsetMs: startOffsetMs,
      chords: resultChords,
    );
  }

  /// Memindai Meta Event dalam track MIDI
  static void _scanMetaEvents(Uint8List trackData, void Function(int metaType, Uint8List data) onMeta) {
    int p = 0;
    while (p < trackData.length) {
      // Baca var-len delta time
      while (p < trackData.length && (trackData[p] & 0x80) != 0) {
        p++;
      }
      p++; // byte terakhir delta
      if (p >= trackData.length) break;

      final status = trackData[p];
      if (status == 0xFF) {
        p++; // status 0xFF
        if (p >= trackData.length) break;
        final metaType = trackData[p];
        p++; // meta type
        if (p >= trackData.length) break;

        // Baca var-len panjang data
        int len = 0;
        while (p < trackData.length) {
          final b = trackData[p++];
          len = (len << 7) | (b & 0x7F);
          if ((b & 0x80) == 0) break;
        }

        final end = math.min(p + len, trackData.length);
        final metaData = trackData.sublist(p, end);
        onMeta(metaType, metaData);
        p = end;
      } else if (status == 0xF0 || status == 0xF7) {
        p++;
        int len = 0;
        while (p < trackData.length) {
          final b = trackData[p++];
          len = (len << 7) | (b & 0x7F);
          if ((b & 0x80) == 0) break;
        }
        p = math.min(p + len, trackData.length);
      } else {
        // Voice event
        int prev = status;
        if ((status & 0x80) != 0) {
          p++;
        } else {
          prev = status; // running status
        }
        final cmd = prev & 0xF0;
        if (cmd == 0x80 || cmd == 0x90 || cmd == 0xA0 || cmd == 0xB0 || cmd == 0xE0) {
          p += 2;
        } else if (cmd == 0xC0 || cmd == 0xD0) {
          p += 1;
        }
      }
    }
  }

  /// Membaca urutan Note On / Note Off beserta tick posisinya
  static List<_NoteEvent> _parseNoteEvents(Uint8List trackData) {
    final events = <_NoteEvent>[];
    int p = 0;
    int curTick = 0;
    int prevStatus = 0;

    while (p < trackData.length) {
      // Baca var-len delta
      int delta = 0;
      while (p < trackData.length) {
        final b = trackData[p++];
        delta = (delta << 7) | (b & 0x7F);
        if ((b & 0x80) == 0) break;
      }
      curTick += delta;
      if (p >= trackData.length) break;

      int status = trackData[p];
      if (status == 0xFF) {
        p++;
        if (p >= trackData.length) break;
        p++; // skip meta type
        int len = 0;
        while (p < trackData.length) {
          final b = trackData[p++];
          len = (len << 7) | (b & 0x7F);
          if ((b & 0x80) == 0) break;
        }
        p = math.min(p + len, trackData.length);
      } else if (status == 0xF0 || status == 0xF7) {
        p++;
        int len = 0;
        while (p < trackData.length) {
          final b = trackData[p++];
          len = (len << 7) | (b & 0x7F);
          if ((b & 0x80) == 0) break;
        }
        p = math.min(p + len, trackData.length);
      } else {
        if ((status & 0x80) != 0) {
          p++;
          prevStatus = status;
        } else {
          status = prevStatus;
        }

        final cmd = status & 0xF0;
        if (cmd == 0x80 || cmd == 0x90) {
          if (p + 1 < trackData.length) {
            final note = trackData[p++];
            final vel = trackData[p++];
            final isOn = (cmd == 0x90 && vel > 0);
            events.add(_NoteEvent(tick: curTick, note: note, vel: vel, isOn: isOn));
          }
        } else if (cmd == 0xA0 || cmd == 0xB0 || cmd == 0xE0) {
          p += 2;
        } else if (cmd == 0xC0 || cmd == 0xD0) {
          p += 1;
        }
      }
    }
    return events;
  }

  /// Algoritma pendeteksi akord dari kumpulan nada MIDI dan bass
  static String identifyChord(List<int> notes, {int? bassNote, bool useFlats = true}) {
    final pitchNames = useFlats ? _pitchNamesFlat : _pitchNamesSharp;
    final pitches = notes.map((n) => n % 12).toSet().toList()..sort();
    if (pitches.isEmpty) return 'N.C.';

    final bassPitch = bassNote != null ? (bassNote % 12) : pitches.first;

    // Cek kemungkinan root dari kumpulan nada
    String? bestChord;
    int bestScore = -1;

    for (final root in pitches) {
      final intervals = pitches.map((p) => (p - root) % 12).toSet();
      final rootName = pitchNames[root];

      String? match;
      int score = 0;

      // ── Pass 1: Triads + Extended chords (semua dalam satu loop) ──

      if (intervals.contains(4) && intervals.contains(7)) {
        // Major base family
        final has10 = intervals.contains(10);
        final has11 = intervals.contains(11);
        final has9 = intervals.contains(9);
        final has2 = intervals.contains(2);
        final has5 = intervals.contains(5);
        final has1 = intervals.contains(1);
        final has3 = intervals.contains(3);

        if (has10 && has2 && has5) {
          match = '${rootName}11'; score = 9;
        } else if (has10 && has9) {
          match = '${rootName}13'; score = 9;
        } else if (has11 && has9 && has2) {
          match = '${rootName}maj9'; score = 9;
        } else if (has10 && has2) {
          match = '${rootName}9'; score = 8;
        } else if (has11 && has2) {
          match = '${rootName}maj9'; score = 8;
        } else if (has10 && has1) {
          match = '${rootName}7b9'; score = 8;
        } else if (has10 && has3) {
          match = '${rootName}7#9'; score = 8;
        } else if (has10) {
          match = '${rootName}7'; score = 6;
        } else if (has11) {
          match = '${rootName}maj7'; score = 6;
        } else if (has9 && has2) {
          match = '${rootName}6/9'; score = 7;
        } else if (has9) {
          match = '${rootName}6'; score = 6;
        } else if (has2) {
          match = '${rootName}add9'; score = 6;
        } else {
          match = rootName; score = 5;
        }
      } else if (intervals.contains(3) && intervals.contains(7)) {
        // Minor base family
        final has10 = intervals.contains(10);
        final has11 = intervals.contains(11);
        final has9 = intervals.contains(9);
        final has2 = intervals.contains(2);
        final has5 = intervals.contains(5);

        if (has10 && has2 && has5) {
          match = '${rootName}m11'; score = 9;
        } else if (has10 && has9) {
          match = '${rootName}m13'; score = 9;
        } else if (has10 && has2) {
          match = '${rootName}m9'; score = 8;
        } else if (has11 && has2) {
          match = '${rootName}mmaj9'; score = 8;
        } else if (has10) {
          match = '${rootName}m7'; score = 6;
        } else if (has11) {
          match = '${rootName}mmaj7'; score = 6;
        } else if (has9 && has2) {
          match = '${rootName}m6/9'; score = 7;
        } else if (has9) {
          match = '${rootName}m6'; score = 6;
        } else if (has2) {
          match = '${rootName}madd9'; score = 6;
        } else {
          match = '${rootName}m'; score = 5;
        }
      } else if (intervals.contains(3) && intervals.contains(6)) {
        // Diminished family
        if (intervals.contains(9)) {
          match = '${rootName}dim7'; score = 6;
        } else if (intervals.contains(10)) {
          match = '${rootName}m7b5'; score = 6;
        } else {
          match = '${rootName}dim'; score = 5;
        }
      } else if (intervals.contains(4) && intervals.contains(8)) {
        // Augmented family
        if (intervals.contains(10)) {
          match = '${rootName}aug7'; score = 6;
        } else {
          match = '${rootName}aug'; score = 5;
        }
      } else if (intervals.contains(4) && intervals.contains(6)) {
        // 7b5 (no 5th)
        if (intervals.contains(10)) {
          match = '${rootName}7b5'; score = 7;
        }
      } else if (intervals.contains(5) && intervals.contains(7)) {
        // Sus4 family
        if (intervals.contains(10) && intervals.contains(2)) {
          match = '${rootName}9sus4'; score = 7;
        } else if (intervals.contains(10)) {
          match = '${rootName}7sus4'; score = 6;
        } else {
          match = '${rootName}sus4'; score = 4;
        }
      } else if (intervals.contains(2) && intervals.contains(7)) {
        // Sus2
        match = '${rootName}sus2'; score = 4;
      }

      // Bonus prioritas jika root sama dengan bass note
      if (match != null) {
        if (root == bassPitch) score += 2;
        if (score > bestScore) {
          bestScore = score;
          bestChord = match;
          // Periksa slash chord jika bass berbeda dengan root
          if (bassPitch != root) {
            final bassName = pitchNames[bassPitch];
            bestChord = '$match/$bassName';
          }
        }
      }
    }

    if (bestChord != null) return bestChord;

    // Final fallback: gabungan nama nada
    final chordName = pitchNames[pitches.first];
    if (bassPitch != pitches.first) {
      return '$chordName/${pitchNames[bassPitch]}';
    }
    return chordName;
  }

  static bool _preferFlats(Iterable<List<int>> chordGroups) {
    int flatCount = 0;
    int sharpCount = 0;
    for (final group in chordGroups) {
      for (final n in group) {
        final p = n % 12;
        // Pitch 1(Db/C#), 3(Eb/D#), 8(Ab/G#), 10(Bb/A#)
        if (p == 1 || p == 3 || p == 8 || p == 10) flatCount++;
        if (p == 6) sharpCount++; // F#
      }
    }
    return flatCount >= sharpCount;
  }
}

class _NoteEvent {
  final int tick;
  final int note;
  final int vel;
  final bool isOn;

  const _NoteEvent({
    required this.tick,
    required this.note,
    required this.vel,
    required this.isOn,
  });
}
