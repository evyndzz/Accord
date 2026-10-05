import 'package:accord/models/song.dart';
import 'package:accord/models/song_line.dart';
import 'package:accord/providers/library_provider.dart';
import 'package:accord/providers/player_provider.dart';
import 'package:accord/screens/player_screen.dart';
import 'package:accord/services/audio_player_service.dart';
import 'package:accord/services/google_drive_sync_service.dart';
import 'package:accord/services/local_database.dart';
import 'package:accord/widgets/chordify_beat_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    const MethodChannel channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        return '.';
      },
    );
  });

  group('Start Beat and Offset Math Tests', () {
    test('Song model defaults and copyWith', () {
      const song = Song(
        id: 'test_1',
        title: 'Lagu Uji',
        artist: 'Artis Uji',
        durationMs: 60000,
        lines: [],
      );

      expect(song.effectiveStartBeat, 1);
      expect(song.effectiveStartBeatOffsetMs, 0);

      final updated = song.copyWith(
        startBeat: 3,
        startBeatOffsetMs: 1500,
      );

      expect(updated.effectiveStartBeat, 3);
      expect(updated.effectiveStartBeatOffsetMs, 1500);
    });

    test('generateBeats with startBeat = 1 and startBeatOffsetMs = 1500ms', () {
      final lines = [
        const SongLine(lineIndex: 0, startTimeMs: 1500, rawLine: '[C]'),
        const SongLine(lineIndex: 1, startTimeMs: 3500, rawLine: '[G]'),
      ];

      final beats = ChordifyBeatGridWidget.generateBeats(
        lines: lines,
        totalDurationMs: 4000,
        bpm: 120.0,
        timeSignature: '4/4',
        startBeat: 1,
        startBeatOffsetMs: 1500,
      );

      expect(beats.isNotEmpty, isTrue);
      // Beat 0 starts at 1500ms with chord C
      expect(beats[0].startTimeMs, 1500);
      expect(beats[0].chords, ['C']);
      expect(beats[0].beatInBar, 0);
      expect(beats[0].barIndex, 0);

      // Beat 1 (2000ms), Beat 2 (2500ms), Beat 3 (3000ms)
      expect(beats[1].startTimeMs, 2000);
      expect(beats[1].isContinuation, isTrue);

      // Beat 4 starts at 3500ms with chord G
      expect(beats[4].startTimeMs, 3500);
      expect(beats[4].chords, ['G']);
    });

    test('generateBeats with startBeat = 3 (pickup) and startBeatOffsetMs = 1500ms', () {
      final lines = [
        const SongLine(lineIndex: 0, startTimeMs: 1500, rawLine: '[Am]'),
      ];

      final beats = ChordifyBeatGridWidget.generateBeats(
        lines: lines,
        totalDurationMs: 4000,
        bpm: 120.0,
        timeSignature: '4/4',
        startBeat: 3,
        startBeatOffsetMs: 1500,
      );

      // In Bar 0, beats 0 and 1 are intro rests before the start beat (beatInBar 2)
      expect(beats[0].beatInBar, 0);
      expect(beats[0].isRest, isTrue);

      expect(beats[1].beatInBar, 1);
      expect(beats[1].isRest, isTrue);

      // Beat 2 is beatInBar 2 (Beat 3) and starts at 1500ms with Am
      expect(beats[2].beatInBar, 2);
      expect(beats[2].startTimeMs, 1500);
      expect(beats[2].chords, ['Am']);
    });
  });

  group('LocalDatabase Start Beat Persistence Tests', () {
    test('LocalDatabase saves and loads startBeat and startBeatOffsetMs', () async {
      final db = LocalDatabase.instance;
      const song = Song(
        id: 'beat_persist_test',
        title: 'Beat Persist Song',
        artist: 'Band Test',
        durationMs: 120000,
        lines: [],
        bpm: 110.0,
        timeSignature: '3/4',
        startBeat: 2,
        startBeatOffsetMs: 850,
      );

      await db.insertSong(song);

      final retrieved = await db.getSong('beat_persist_test');
      expect(retrieved, isNotNull);
      expect(retrieved!.bpm, 110.0);
      expect(retrieved.timeSignature, '3/4');
      expect(retrieved.startBeat, 2);
      expect(retrieved.startBeatOffsetMs, 850);

      // Update beat settings
      await db.updateSongBeatSettings(
        'beat_persist_test',
        bpm: 130.0,
        timeSignature: '4/4',
        startBeat: 4,
        startBeatOffsetMs: 2200,
      );

      final updated = await db.getSong('beat_persist_test');
      expect(updated, isNotNull);
      expect(updated!.bpm, 130.0);
      expect(updated.timeSignature, '4/4');
      expect(updated.startBeat, 4);
      // Update via updateSongCloudMetadata (simulating cloud sync retrieval)
      await db.updateSongCloudMetadata(
        'beat_persist_test',
        artist: 'Symphony Worship.',
        originalKey: 'D',
        bpm: 75.0,
        timeSignature: '4/4',
        startBeat: 4,
        startBeatOffsetMs: 1421,
      );

      final cloudUpdated = await db.getSong('beat_persist_test');
      expect(cloudUpdated, isNotNull);
      expect(cloudUpdated!.artist, 'Symphony Worship.');
      expect(cloudUpdated.originalKey, 'D');
      expect(cloudUpdated.bpm, 75.0);
      expect(cloudUpdated.timeSignature, '4/4');
      expect(cloudUpdated.startBeat, 4);
      expect(cloudUpdated.startBeatOffsetMs, 1421);

      await db.deleteSong('beat_persist_test');
    });
  });

  group('PlayerScreen Tempo & Start Beat UI Tests', () {
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
      playerProvider.dispose();
      audioService.dispose();
      driveSync.dispose();
    });

    testWidgets('PlayerScreen opens tempo sheet and displays Start Beat and Offset controls', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;

      const testSong = Song(
        id: 'tempo_ui_song',
        title: 'Ui Beat Song',
        artist: 'Ui Artist',
        durationMs: 180000,
        bpm: 120.0,
        timeSignature: '4/4',
        startBeat: 1,
        startBeatOffsetMs: 1000,
        lines: [
          SongLine(lineIndex: 0, startTimeMs: 1000, rawLine: '[C] Hello'),
        ],
      );

      await playerProvider.playSong(testSong);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: playerProvider),
            ChangeNotifierProvider.value(value: libraryProvider),
            ChangeNotifierProvider.value(value: driveSync),
          ],
          child: const MaterialApp(
            home: PlayerScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap speed/tempo button
      final tempoBtn = find.byTooltip('Atur Birama & Tempo');
      expect(tempoBtn, findsOneWidget);
      await tester.tap(tempoBtn);
      await tester.pumpAndSettle();

      // Verify Birama & Tempo modal content
      expect(find.text('Atur Birama & Tempo'), findsOneWidget);
      expect(find.text('Birama (Time Signature)'), findsOneWidget);
      expect(find.text('Mulai Di Beat Ke- (Start Beat)'), findsOneWidget);
      expect(find.text('Offset Awal / Hening (Delay)'), findsOneWidget);
      expect(find.text('Tempo (BPM)'), findsOneWidget);

      // Verify Beat chips exist
      expect(find.text('Beat 1'), findsNWidgets(2)); // One in badge, one in chip
      expect(find.text('Beat 2'), findsOneWidget);
      expect(find.text('Beat 3'), findsOneWidget);
      expect(find.text('Beat 4'), findsOneWidget);

      // Tap Beat 3
      await tester.tap(find.text('Beat 3'));
      await tester.pumpAndSettle();

      // Verify offset steppers
      expect(find.text('-0.5s'), findsOneWidget);
      expect(find.text('+0.5s'), findsOneWidget);
      expect(find.text('Reset (0s)'), findsOneWidget);

      // Tap +0.5s
      await tester.tap(find.text('+0.5s'));
      await tester.pumpAndSettle();

      // Tap Selesai
      final selesaiBtn = find.text('SELESAI');
      expect(selesaiBtn, findsOneWidget);
      await tester.tap(selesaiBtn);
      await tester.pump(const Duration(milliseconds: 300));

      await playerProvider.pause();
      // Flush sqflite lock timer
      await tester.pump(const Duration(seconds: 15));

      addTearDown(() => tester.view.resetPhysicalSize());
    });
  });
}
