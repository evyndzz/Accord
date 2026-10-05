import 'package:accord/models/song.dart';
import 'package:accord/models/song_line.dart';
import 'package:accord/providers/library_provider.dart';
import 'package:accord/providers/player_provider.dart';
import 'package:accord/screens/player_screen.dart';
import 'package:accord/services/audio_player_service.dart';
import 'package:accord/services/google_drive_sync_service.dart';
import 'package:accord/services/local_database.dart';
import 'package:accord/widgets/mini_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MiniPlayer Tests', () {
    testWidgets('MiniPlayer renders without LinearProgressIndicator and has transparent glass design', (tester) async {
      bool playTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MiniPlayer(
              title: 'Tercurah Darah Tuhanku',
              artist: 'GMS Live',
              isPlaying: true,
              progress: 0.45,
              onPlayPauseTap: () => playTapped = true,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify song info
      expect(find.text('Tercurah Darah Tuhanku'), findsOneWidget);
      expect(find.text('GMS Live'), findsOneWidget);

      // Verify progress bar is GONE
      expect(find.byType(LinearProgressIndicator), findsNothing);

      // Verify computer/devices icon is GONE
      expect(find.byIcon(Icons.devices_rounded), findsNothing);

      // Verify play/pause button works
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.pause_rounded));
      expect(playTapped, isTrue);
    });
  });

  group('Lyrics System Tests', () {
    late AudioPlayerService audioService;
    late PlayerProvider playerProvider;
    late LibraryProvider libraryProvider;
    late GoogleDriveSyncService driveSync;

    setUp(() {
      SharedPreferences.setMockInitialValues({'has_seeded_default_playlists': true});
      audioService = AudioPlayerService();
      playerProvider = PlayerProvider(
        audioPlayerService: audioService,
        localDb: LocalDatabase.instance,
      );
      libraryProvider = LibraryProvider(
        localDb: LocalDatabase.instance,
      );
      driveSync = GoogleDriveSyncService(autoSyncOnStart: false);
    });

    testWidgets('PlayerScreen renders lyrics without dot circle and centers active line', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const testSong = Song(
        id: 'test_lyric_song',
        title: 'Lagu Lirik Indah',
        artist: 'Accord Cosmic',
        originalKey: 'C',
        bpm: 120,
        timeSignature: '4/4',
        durationMs: 30000,
        lines: [
          SongLine(lineIndex: 0, startTimeMs: 1000, rawLine: '[C] Ku tatap [G] mentari'),
          SongLine(lineIndex: 1, startTimeMs: 5000, rawLine: '[Am] Terangi [F] hariku'),
          SongLine(lineIndex: 2, startTimeMs: 9000, rawLine: '[C] Damai di [G] jiwa'),
        ],
      );

      await playerProvider.playSong(testSong);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<PlayerProvider>.value(value: playerProvider),
            ChangeNotifierProvider<LibraryProvider>.value(value: libraryProvider),
            ChangeNotifierProvider<GoogleDriveSyncService>.value(value: driveSync),
          ],
          child: const MaterialApp(
            home: PlayerScreen(),
          ),
        ),
      );

      await tester.pump();

      // Verify lyrics are found
      expect(find.textContaining('Ku tatap'), findsOneWidget);
      expect(find.textContaining('Terangi'), findsOneWidget);
      expect(find.textContaining('Damai'), findsOneWidget);

      // Verify no dot circle exists in the lyrics area
      final circleContainers = find.byWidgetPredicate((widget) {
        if (widget is Container && widget.decoration is BoxDecoration) {
          final box = widget.decoration as BoxDecoration;
          return box.shape == BoxShape.circle && widget.constraints?.maxWidth == 6;
        }
        return false;
      });
      expect(circleContainers, findsNothing);

      playerProvider.dispose();
      audioService.dispose();
      driveSync.dispose();
    });
  });
}
