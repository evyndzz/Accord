import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:accord/models/song.dart';
import 'package:accord/models/song_line.dart';
import 'package:accord/providers/cosmic_theme_provider.dart';
import 'package:accord/providers/library_provider.dart';
import 'package:accord/providers/player_provider.dart';
import 'package:accord/providers/profile_provider.dart';
import 'package:accord/screens/dashboard_screen.dart';
import 'package:accord/screens/player_screen.dart';
import 'package:accord/services/audio_player_service.dart';
import 'package:accord/services/google_drive_audio_service.dart';
import 'package:accord/services/google_drive_sync_service.dart';
import 'package:accord/services/local_database.dart';
import 'package:accord/utils/ambiance_color_helper.dart';
import 'package:accord/widgets/apple_music_aura_background.dart';
import 'package:accord/widgets/mini_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    const MethodChannel channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        return Directory.systemTemp.path;
      },
    );
  });

  group('AmbianceColorHelper Tests', () {
    test('extracts primary and secondary colors correctly from song gradient', () {
      const song = Song(
        id: 'test_song',
        title: 'Amber Glow',
        artist: 'Test Artist',
        durationMs: 180000,
        lines: [],
        gradientColors: [Color(0xFFE11D48), Color(0xFFBE123C)],
      );

      final primary = AmbianceColorHelper.getPrimaryColor(song);
      final secondary = AmbianceColorHelper.getSecondaryColor(song);
      expect(primary, equals(const Color(0xFFE11D48)));
      expect(secondary, equals(const Color(0xFFBE123C)));

      final bgGradient = AmbianceColorHelper.getAmbientBackground(song);
      expect(bgGradient.gradient, isA<Gradient>());
      final gradient = bgGradient.gradient as LinearGradient;
      expect(gradient.colors.length, greaterThanOrEqualTo(2));

      final playGradient = AmbianceColorHelper.getPlayButtonGradient(song);
      expect(playGradient.colors.length, equals(2));
    });

    test('falls back safely when song has no gradient colors', () {
      const song = Song(
        id: 'no_color_song',
        title: 'Plain Melody',
        artist: 'Unknown',
        durationMs: 120000,
        lines: [],
      );

      final primary = AmbianceColorHelper.getPrimaryColor(song);
      expect(primary, isNotNull);

      final shadow = AmbianceColorHelper.getArtworkShadowColor(song);
      expect(shadow, isNotNull);
    });
  });

  group('MiniPlayer Favorite & Glass Interaction Tests', () {
    testWidgets('MiniPlayer displays heart icon and fires onFavoriteTap callback', (tester) async {
      bool favTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MiniPlayer(
              title: 'Midnight Reverie',
              artist: 'Luna Eclipse',
              imageUrl: null,
              isPlaying: true,
              progress: 0.6,
              isFavorite: true,
              onFavoriteTap: () => favTapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Midnight Reverie'), findsOneWidget);
      expect(find.text('Luna Eclipse'), findsOneWidget);
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.favorite_rounded));
      expect(favTapped, isTrue);
    });
    test('synchronizes ambiance color with extracted album artwork colors', () {
      const artPath = '/path/to/custom_album_art.jpg';
      const songWithArt = Song(
        id: 'art_song',
        title: 'Synchronized Waves',
        artist: 'Color Artist',
        durationMs: 180000,
        albumArtUrl: artPath,
        lines: [],
      );

      // Initially fallback to palette / gradient before extraction
      final initialColor = AmbianceColorHelper.getPrimaryColor(songWithArt);
      expect(initialColor, isNotNull);

      // Simulate extracted vibrant colors from artwork
      const extractedVibrant = Color(0xFF10B981); // Emerald
      const extractedAccent = Color(0xFF06B6D4); // Cyan
      AmbianceColorHelper.setExtractedColors(artPath, [extractedVibrant, extractedAccent]);

      // Verify colors are now prioritized and synchronized directly from album cover
      final primary = AmbianceColorHelper.getPrimaryColor(songWithArt);
      final secondary = AmbianceColorHelper.getSecondaryColor(songWithArt);
      expect(primary, equals(extractedVibrant));
      expect(secondary, equals(extractedAccent));
    });
  });

  group('PlayerScreen Gambar 1 Unified Redesign Tests', () {
    testWidgets('PlayerScreen renders unified player without Sampul/Antrean tabs and opens queue sheet', (tester) async {
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
        id: 'test_player_song',
        title: 'Dancing till dawn',
        artist: 'Harmonic Artist',
        durationMs: 210000,
        bpm: 128,
        timeSignature: '4/4',
        lines: [
          SongLine(lineIndex: 0, startTimeMs: 0, rawLine: '[G] [D] [Em] [C]'),
          SongLine(lineIndex: 1, startTimeMs: 3000, rawLine: 'Let the rhythm guide your heart'),
        ],
        gradientColors: [Color(0xFF7A1320), Color(0xFF450A12)],
      );

      await player.playSong(song);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<PlayerProvider>.value(value: player),
            ChangeNotifierProvider<LibraryProvider>(
              create: (_) => LibraryProvider(localDb: LocalDatabase.instance),
            ),
          ],
          child: const MaterialApp(
            home: PlayerScreen(),
          ),
        ),
      );

      await tester.pump();

      // Verify header has minimize and edit button, and NOW PLAYING title is removed
      expect(find.text('NOW PLAYING'), findsNothing);
      expect(find.byTooltip('Minimize'), findsOneWidget);
      expect(find.byTooltip('Edit / Add Chords'), findsOneWidget);

      // Verify old tab switchers and removed controls are absent
      expect(find.text('Sampul'), findsNothing);
      expect(find.text('Chord & Lirik'), findsNothing);
      expect(find.text('Antrean'), findsNothing);
      expect(find.byTooltip('Antrean Lagu'), findsNothing);
      expect(find.byTooltip('Opsi Lagu'), findsNothing);

      // Verify unified components are simultaneously visible:
      // 1. Song Title and Artist
      expect(find.text('Dancing till dawn'), findsOneWidget);
      expect(find.text('Harmonic Artist'), findsOneWidget);

      // 2. Transpose Controls in unified view
      expect(find.text('Transpose: '), findsOneWidget);
      // Tap '+' to transpose up
      await tester.tap(find.text('+').first);
      await tester.pumpAndSettle();
      expect(player.transposeOffset, equals(1));

      // Reset transpose via Reset button
      expect(find.text('Reset'), findsOneWidget);
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      expect(player.transposeOffset, equals(0));

      // 3. Switch to Overview Mode via bottom control button
      expect(find.byTooltip('Beralih ke Chord Overview'), findsOneWidget);
      await tester.tap(find.byTooltip('Beralih ke Chord Overview'));
      await tester.pumpAndSettle();

      // Verify Overview mode has Diagram & Lirik toggle
      expect(find.text('Diagram & Lirik'), findsOneWidget);

      // Return to Diagrams & Lyrics
      await tester.tap(find.text('Diagram & Lirik'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Beralih ke Chord Overview'), findsOneWidget);

      await player.pause();
      player.dispose();
      audioService.dispose();
    });
  });

  group('PlayerProvider Play History Tests', () {
    test('records played songs into playHistory in LIFO order and avoids duplicates', () async {
      final audioService = AudioPlayerService();
      final player = PlayerProvider(
        audioPlayerService: audioService,
        localDb: LocalDatabase.instance,
      );

      const song1 = Song(id: 's1', title: 'Song One', artist: 'Artist 1', durationMs: 100000, lines: []);
      const song2 = Song(id: 's2', title: 'Song Two', artist: 'Artist 2', durationMs: 120000, lines: []);
      const song3 = Song(id: 's3', title: 'Song Three', artist: 'Artist 3', durationMs: 140000, lines: []);

      await player.playSong(song1);
      expect(player.playHistory.length, equals(1));
      expect(player.playHistory.first.id, equals('s1'));

      await player.playSong(song2);
      expect(player.playHistory.length, equals(2));
      expect(player.playHistory[0].id, equals('s2'));
      expect(player.playHistory[1].id, equals('s1'));

      await player.playSong(song3);
      expect(player.playHistory.length, equals(3));
      expect(player.playHistory[0].id, equals('s3'));

      // Replay song1 - should move to front without increasing length
      await player.playSong(song1);
      expect(player.playHistory.length, equals(3));
      expect(player.playHistory[0].id, equals('s1'));
      expect(player.playHistory[1].id, equals('s3'));
      expect(player.playHistory[2].id, equals('s2'));

      await player.pause();
      player.dispose();
      audioService.dispose();
    });

    test('caps playHistory at maximum 25 items', () async {
      final audioService = AudioPlayerService();
      final player = PlayerProvider(
        audioPlayerService: audioService,
        localDb: LocalDatabase.instance,
      );

      for (int i = 0; i < 30; i++) {
        final s = Song(id: 'song_$i', title: 'Song $i', artist: 'Artist', durationMs: 60000, lines: []);
        await player.playSong(s);
      }

      expect(player.playHistory.length, equals(25));
      expect(player.playHistory.first.id, equals('song_29'));

      await player.pause();
      player.dispose();
      audioService.dispose();
    });
  });

  group('DashboardScreen History Play & Playlist UI Tests', () {
    testWidgets('DashboardScreen renders History play, Playlist, and dynamic cards', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final audioService = AudioPlayerService();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<AudioPlayerService>.value(value: audioService),
            ChangeNotifierProvider(create: (_) => ProfileProvider()),
            ChangeNotifierProvider(create: (_) => GoogleDriveAudioService()),
            ChangeNotifierProvider(create: (_) => GoogleDriveSyncService(autoSyncOnStart: false)),
            ChangeNotifierProvider(
              create: (ctx) => PlayerProvider(
                audioPlayerService: ctx.read<AudioPlayerService>(),
                localDb: LocalDatabase.instance,
              ),
            ),
            ChangeNotifierProvider(create: (_) => LibraryProvider(localDb: LocalDatabase.instance)),
            ChangeNotifierProvider(create: (_) => CosmicThemeProvider()),
          ],
          child: const MaterialApp(
            home: DashboardScreen(),
          ),
        ),
      );

      await tester.pump();

      // Verify "History play" header exists
      expect(find.text('History play'), findsOneWidget);
      // Verify "Playlist" header exists
      expect(find.text('Playlist'), findsOneWidget);
      // Verify "Daftar Lagu" header exists
      expect(find.text('Daftar Lagu'), findsOneWidget);

      // Verify old static sections are NOT present
      expect(find.text('Trending now'), findsNothing);
      expect(find.text('Mixes for you'), findsNothing);

      // Verify Lagu Disukai playlist card is present
      expect(find.text('Lagu Disukai'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 11));
      audioService.dispose();
    });
  });

  group('AppleMusicAuraBackground Tests', () {
    testWidgets('renders liquid aura mesh with BackdropFilter and child content', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppleMusicAuraBackground(
              primaryColor: Color(0xFFE11D48),
              secondaryColor: Color(0xFF3B82F6),
              child: Center(
                child: Text('Apple Music Aura Foreground'),
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.byType(AppleMusicAuraBackground), findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.text('Apple Music Aura Foreground'), findsOneWidget);
    });

    testWidgets('gracefully updates colors on song palette change', (tester) async {
      Color primary = const Color(0xFF10B981);
      Color secondary = const Color(0xFF06B6D4);

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return MaterialApp(
              home: Scaffold(
                body: AppleMusicAuraBackground(
                  primaryColor: primary,
                  secondaryColor: secondary,
                ),
                floatingActionButton: FloatingActionButton(
                  onPressed: () {
                    setState(() {
                      primary = const Color(0xFF8B5CF6);
                      secondary = const Color(0xFFEC4899);
                    });
                  },
                ),
              ),
            );
          },
        ),
      );

      await tester.pump();
      expect(find.byType(AppleMusicAuraBackground), findsOneWidget);

      // Trigger palette update
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(AppleMusicAuraBackground), findsOneWidget);
    });
  });
}

