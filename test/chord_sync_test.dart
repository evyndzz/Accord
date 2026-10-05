import 'package:accord/models/song.dart';
import 'package:accord/models/song_line.dart';
import 'package:accord/providers/player_provider.dart';
import 'package:accord/services/audio_player_service.dart';
import 'package:accord/services/local_database.dart';
import 'package:accord/utils/chord_parser.dart';
import 'package:accord/utils/transposer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChordParser & Transposer Tests', () {
    test('ChordParser extracts chords and character indices properly', () {
      const line = '[C]Di badai topan [G]dunia, Tuhan [Am]perlindunganku';
      final parsed = ChordParser.parse(line);

      expect(parsed.plainText, equals('Di badai topan dunia, Tuhan perlindunganku'));
      expect(parsed.chords.length, equals(3));
      expect(parsed.chords[0].chord, equals('C'));
      expect(parsed.chords[0].charIndex, equals(0));
      expect(parsed.chords[1].chord, equals('G'));
      expect(parsed.chords[1].charIndex, equals(15));
      expect(parsed.chords[2].chord, equals('Am'));
      expect(parsed.chords[2].charIndex, equals(28));
    });

    test('ChordParser handles lines with only chords (Intro/Instrumental)', () {
      const line = '[C] [G] [Am] [F]';
      final parsed = ChordParser.parse(line);
      expect(parsed.plainText.trim(), isEmpty);
      expect(parsed.chords.length, equals(4));
      expect(parsed.chords.map((c) => c.chord).toList(), equals(['C', 'G', 'Am', 'F']));
    });

    test('Transposer transposes chords correctly', () {
      expect(TransposeEngine.transposeChord('C', 2), equals('D'));
      expect(TransposeEngine.transposeChord('Am', 2), equals('Bm'));
      expect(TransposeEngine.transposeLine('[C]Hello [G]World', 2), equals('[D]Hello [A]World'));
    });
  });

  group('PlayerProvider Timestamp & Chord Sync Tests', () {
    late AudioPlayerService audioService;
    late PlayerProvider player;

    setUp(() {
      audioService = AudioPlayerService();
      player = PlayerProvider(
        audioPlayerService: audioService,
        localDb: LocalDatabase.instance,
      );
    });

    tearDown(() {
      audioService.dispose();
    });

    test('activeLyricIndex respects line timestamps and intro', () async {
      const song = Song(
        id: 'test_song',
        title: 'Test Song',
        artist: 'Test Artist',
        durationMs: 60000,
        lines: [
          SongLine(lineIndex: 0, startTimeMs: 5000, rawLine: '[C] [G] [Am] [F]'),
          SongLine(lineIndex: 1, startTimeMs: 15000, rawLine: '[C]Di badai topan [G]dunia'),
          SongLine(lineIndex: 2, startTimeMs: 25000, rawLine: '[Am]Tuhan tetap perlindungan[F]ku'),
        ],
      );

      await player.playSong(song);

      // 1. Position 2000 ms (Intro, before 5000 ms) -> index should be -1
      await player.seekToMs(2000);
      expect(player.activeLyricIndex, equals(-1));
      expect(player.currentChord, equals(''));

      // 2. Position 5000 ms -> line 0 starts
      await player.seekToMs(5000);
      expect(player.activeLyricIndex, equals(0));
      // Line 0 is 5000 to 15000 (10s duration) with 4 chords: C, G, Am, F (2.5s each)
      expect(player.currentChord, equals('C'));

      // Position 8000 ms (3s into line 0) -> chord should advance to G
      await player.seekToMs(8000);
      expect(player.currentChord, equals('G'));

      // Position 11000 ms (6s into line 0) -> chord should advance to Am
      await player.seekToMs(11000);
      expect(player.currentChord, equals('Am'));

      // Position 13500 ms (8.5s into line 0) -> chord should advance to F
      await player.seekToMs(13500);
      expect(player.currentChord, equals('F'));

      // 3. Position 15000 ms -> line 1 starts [C]Di badai topan [G]dunia
      await player.seekToMs(15000);
      expect(player.activeLyricIndex, equals(1));
      expect(player.currentChord, equals('C'));

      // Position 20000 ms (before "dunia") -> still C
      await player.seekToMs(20000);
      expect(player.currentChord, equals('C'));

      // Position 23000 ms (80% into line 1, where [G] is) -> chord should be G
      await player.seekToMs(23000);
      expect(player.currentChord, equals('G'));

      // 4. Position 25000 ms -> line 2 starts [Am]Tuhan tetap perlindungan[F]ku
      await player.seekToMs(25000);
      expect(player.activeLyricIndex, equals(2));
      expect(player.currentChord, equals('Am'));
    });

    test('activeChordLineIndex and activeLyricLineIndex track separated chord and lyric lines independently', () async {
      const song = Song(
        id: 'separated_song',
        title: 'Separated Song',
        artist: 'Separated Artist',
        durationMs: 60000,
        lines: [
          SongLine(lineIndex: 0, startTimeMs: 2000, rawLine: 'Intro'),
          SongLine(lineIndex: 1, startTimeMs: 5000, rawLine: '[D] [G] [D] [G]'),
          SongLine(lineIndex: 2, startTimeMs: 15000, rawLine: 'Verse 1'),
          SongLine(lineIndex: 3, startTimeMs: 18000, rawLine: '[D] [D/F#] [G] [D]'),
          SongLine(lineIndex: 4, startTimeMs: 22000, rawLine: 'Tercurah darah Tuhanku'),
          SongLine(lineIndex: 5, startTimeMs: 28000, rawLine: '[D] [Em] [A] [A7]'),
          SongLine(lineIndex: 6, startTimeMs: 32000, rawLine: 'Di bukit Golgota'),
        ],
      );

      await player.playSong(song);

      // At 24000ms: During vocal "Tercurah darah Tuhanku" (line 4)
      await player.seekToMs(24000);
      expect(player.activeLyricIndex, equals(4));
      expect(player.activeLyricLineIndex, equals(4));
      expect(player.activeLyricText, equals('Tercurah darah Tuhanku'));
      // activeChordLineIndex stays at 3 ('[D] [D/F#] [G] [D]')!
      expect(player.activeChordLineIndex, equals(3));
      // currentChord does NOT become empty; it stays active as the held chord!
      expect(player.currentChord.isNotEmpty, isTrue);

      // At 29000ms: During next chord change '[D] [Em] [A] [A7]' (line 5)
      await player.seekToMs(29000);
      expect(player.activeChordLineIndex, equals(5));
      expect(player.activeLyricLineIndex, equals(4));
      expect(player.activeLyricText, equals('Tercurah darah Tuhanku'));

      // At 33000ms: During next vocal line "Di bukit Golgota" (line 6)
      await player.seekToMs(33000);
      expect(player.activeLyricLineIndex, equals(6));
      expect(player.activeLyricText, equals('Di bukit Golgota'));
      expect(player.activeChordLineIndex, equals(5));
    });

    test('single chord-by-chord tracking updates currentChord precisely at each timestamp', () async {
      const song = Song(
        id: 'one_by_one_chords',
        title: 'One by One Chords',
        artist: 'Chordify Artist',
        durationMs: 30000,
        lines: [
          SongLine(lineIndex: 0, startTimeMs: 2000, rawLine: '[Bb]'),
          SongLine(lineIndex: 1, startTimeMs: 5000, rawLine: '[Bbm]'),
          SongLine(lineIndex: 2, startTimeMs: 8000, rawLine: '[A/C#]'),
          SongLine(lineIndex: 3, startTimeMs: 11000, rawLine: '[D]'),
          SongLine(lineIndex: 4, startTimeMs: 3000, rawLine: 'Ku bersyukur pada-Mu'),
        ],
      );

      await player.playSong(song);

      await player.seekToMs(2500);
      expect(player.currentChord, equals('Bb'));

      await player.seekToMs(5500);
      expect(player.currentChord, equals('Bbm'));

      await player.seekToMs(8500);
      expect(player.currentChord, equals('A/C#'));

      await player.seekToMs(11500);
      expect(player.currentChord, equals('D'));
    });
  });
}
