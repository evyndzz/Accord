import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:accord/models/song.dart';
import 'package:accord/models/song_line.dart';
import 'package:accord/providers/player_provider.dart';
import 'package:accord/screens/player_screen.dart';
import 'package:accord/services/audio_player_service.dart';
import 'package:accord/services/local_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('PlayerScreen renders Current Chord and Next Chord diagrams', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final audioService = AudioPlayerService();
    final player = PlayerProvider(
      audioPlayerService: audioService,
      localDb: LocalDatabase.instance,
    );

    const song = Song(
      id: 'test_song_1',
      title: 'Anticipation Test Song',
      artist: 'Tester',
      durationMs: 30000,
      bpm: 120,
      timeSignature: '4/4',
      lines: [
        SongLine(lineIndex: 0, startTimeMs: 0, rawLine: '[D]'),
        SongLine(lineIndex: 1, startTimeMs: 2000, rawLine: 'Baris lirik pertama yang aktif'),
        SongLine(lineIndex: 2, startTimeMs: 4000, rawLine: '[Em]'),
        SongLine(lineIndex: 3, startTimeMs: 6000, rawLine: 'Baris lirik kedua yang akan datang'),
        SongLine(lineIndex: 4, startTimeMs: 8000, rawLine: '[A]'),
      ],
    );

    await player.playSong(song);

    await tester.pumpWidget(
      ChangeNotifierProvider<PlayerProvider>.value(
        value: player,
        child: const MaterialApp(
          home: PlayerScreen(),
        ),
      ),
    );

    await tester.pump();

    // Verifikasi kontrol birama & tempo, navigasi track, serta mode switcher di player controller terpisah
    expect(find.byTooltip('Atur Birama & Tempo'), findsOneWidget);
    expect(find.byTooltip('Lagu Sebelumnya'), findsOneWidget);
    expect(find.byTooltip('Lagu Berikutnya'), findsOneWidget);
    expect(find.byIcon(Icons.grid_view_rounded), findsOneWidget);

    // Verifikasi kata SAAT INI dan BERIKUTNYA sudah dihilangkan sesuai permintaan pengguna
    expect(find.text('● SAAT INI'), findsNothing);
    expect(find.text('➔ BERIKUTNYA'), findsNothing);
    expect(find.text('+2 KEMUDIAN'), findsNothing);

    // Verifikasi chord saat ini adalah D dan chord berikutnya adalah Em
    expect(player.currentChord, equals('D'));
    expect(player.nextChord, equals('Em'));
    expect(player.upcomingChord, equals('A'));
    expect(find.text('D'), findsWidgets);
    expect(find.text('Em'), findsWidgets);

    // Verifikasi teks lirik vokal muncul tanpa chord
    expect(find.text('Baris lirik pertama yang aktif'), findsOneWidget);
    expect(find.text('Baris lirik kedua yang akan datang'), findsOneWidget);

    // Beralih ke mode Chord Overview via tombol icon controller sebelah kanan
    await tester.tap(find.byIcon(Icons.grid_view_rounded));
    await tester.pumpAndSettle();

    // Di Chord overview, lirik dan piano disembunyikan untuk fokus maksimal matriks
    expect(find.text('Baris lirik pertama yang aktif'), findsNothing);
    expect(find.text('● SAAT INI'), findsNothing);
    expect(find.textContaining('BAR'), findsWidgets);
    expect(find.byIcon(Icons.piano_rounded), findsOneWidget);

    // Beralih kembali ke Chord Diagrams via tombol piano
    await tester.tap(find.byIcon(Icons.piano_rounded));
    await tester.pumpAndSettle();
    expect(find.text('● SAAT INI'), findsNothing);
    expect(find.byIcon(Icons.grid_view_rounded), findsOneWidget);

    player.dispose();
    audioService.dispose();
  });
}
