import 'package:accord/models/song.dart';
import 'package:accord/models/song_line.dart';
import 'package:accord/providers/library_provider.dart';
import 'package:accord/providers/player_provider.dart';
import 'package:accord/screens/settings_screen.dart';
import 'package:accord/screens/song_editor_screen.dart';
import 'package:accord/services/audio_player_service.dart';
import 'package:accord/services/google_drive_sync_service.dart';
import 'package:accord/services/local_database.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('SettingsScreen Theme Tests', () {
    testWidgets('SettingsScreen renders title and cards without astronomy logo selector', (tester) async {
      final driveSync = GoogleDriveSyncService(autoSyncOnStart: false);
      addTearDown(driveSync.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: driveSync),
          ],
          child: const MaterialApp(
            home: SettingsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify title & uppercase section headers
      expect(find.text('Pengaturan'), findsOneWidget);
      expect(find.text('CLOUD SYNC'), findsOneWidget);
      expect(find.text('PEMUTARAN & TAMPILAN'), findsOneWidget);
      expect(find.text('TENTANG ACCORD'), findsOneWidget);

      // Verify Astronomy section is removed from settings
      expect(find.text('TEMA & LAMBANG ASTRONOMI'), findsNothing);
      expect(find.text('Pilih Lambang Kosmik'), findsNothing);
    });
  });

  group('SongEditorScreen Theme & Layout Tests', () {
    late AudioPlayerService audioService;
    late PlayerProvider playerProvider;
    late LibraryProvider libraryProvider;
    late GoogleDriveSyncService driveSync;

    setUp(() {
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

    tearDown(() {
      audioService.dispose();
      driveSync.dispose();
    });

    testWidgets('SongEditorScreen Tab 1 renders birama & tempo cleanly without overflow', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: playerProvider),
            ChangeNotifierProvider.value(value: libraryProvider),
            ChangeNotifierProvider.value(value: driveSync),
          ],
          child: const MaterialApp(
            home: SongEditorScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tab headers
      expect(find.text('Info & Input Terpisah'), findsOneWidget);
      expect(find.text('Sinkronisasi Waktu'), findsOneWidget);

      // Form labels
      expect(find.text('Judul Lagu *'), findsOneWidget);
      expect(find.text('Artis / Penyanyi'), findsOneWidget);
      expect(find.text('Kunci'), findsOneWidget);
      expect(find.text('Birama:'), findsOneWidget);
      expect(find.text('Tempo (BPM):'), findsOneWidget);

      // Birama options
      expect(find.text('4/4'), findsOneWidget);
      expect(find.text('3/4'), findsOneWidget);

      // Scroll to save button in first scrollable
      final saveFinder = find.text('Simpan ke Google Drive & Accord');
      await tester.scrollUntilVisible(saveFinder, 500, scrollable: find.byType(Scrollable).first);
      expect(saveFinder, findsOneWidget);

      addTearDown(() => tester.view.resetPhysicalSize());
    });

    testWidgets('SongEditorScreen Tab 2 renders audio controller and sync mode toggle', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;

      const sampleSong = Song(
        id: 'test_song_1',
        title: 'Cosmic Melody',
        artist: 'Accord Band',
        durationMs: 180000,
        originalKey: 'C',
        lines: [
          SongLine(
            lineIndex: 0,
            startTimeMs: 1000,
            rawLine: '[C]Di badai topan [G]dunia',
          ),
        ],
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: playerProvider),
            ChangeNotifierProvider.value(value: libraryProvider),
            ChangeNotifierProvider.value(value: driveSync),
          ],
          child: const MaterialApp(
            home: SongEditorScreen(existingSong: sampleSong),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Switch to Tab 2
      await tester.tap(find.text('Sinkronisasi Waktu'));
      await tester.pumpAndSettle();

      // Verify sync submode toggles
      expect(find.text('🎸 Sync Tiap Chord'), findsOneWidget);
      expect(find.text('🎤 Sync Baris Lirik'), findsOneWidget);

      // Verify timing actions exist
      expect(find.text('Sync Chord Satu per Satu'), findsOneWidget);
      expect(find.text('Reset'), findsOneWidget);

      // Verify chord diagram preview exists and shows TERPILIH (#1)
      expect(find.textContaining('TERPILIH (#1)'), findsOneWidget);

      // Tap on chord #2 row to select G
      await tester.tap(find.text('#2'));
      await tester.pumpAndSettle();

      // Verify chord diagram preview updates to TERPILIH (#2)
      expect(find.textContaining('TERPILIH (#2)'), findsOneWidget);

      // Test hover effect with mouse pointer
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      await gesture.moveTo(tester.getCenter(find.text('#1')));
      await tester.pump();

      // Verify hover indicator appears
      expect(find.textContaining('DI-HOVER (#1)'), findsOneWidget);
      await gesture.removePointer();

      addTearDown(() => tester.view.resetPhysicalSize());
    });
  });
}
