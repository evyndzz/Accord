import 'package:accord/models/playlist.dart';
import 'package:accord/providers/library_provider.dart';
import 'package:accord/services/local_database.dart';
import 'package:accord/widgets/aurora_background.dart';
import 'package:accord/widgets/liquid_glass_container.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Playlist Model & Logic Tests', () {
    test('Playlist model serializes toMap and deserializes fromMap accurately', () {
      final now = DateTime.now();
      final pl = Playlist(
        id: 'pl_123',
        name: 'Chill Vibes',
        songIds: ['song_1', 'song_2'],
        createdAt: now,
      );

      final map = pl.toMap();
      expect(map['id'], equals('pl_123'));
      expect(map['name'], equals('Chill Vibes'));
      expect(map['song_ids'], equals('song_1,song_2'));
      expect(map['created_at'], equals(now.millisecondsSinceEpoch));

      final restored = Playlist.fromMap(map);
      expect(restored.id, equals('pl_123'));
      expect(restored.name, equals('Chill Vibes'));
      expect(restored.songIds, equals(['song_1', 'song_2']));

      final copied = restored.copyWith(name: 'Acoustic Vibes', songIds: ['song_3']);
      expect(copied.name, equals('Acoustic Vibes'));
      expect(copied.songIds, equals(['song_3']));
    });

    test('Playlist fromMap handles empty song_ids string cleanly', () {
      final map = {
        'id': 'pl_empty',
        'name': 'Empty PL',
        'song_ids': '',
        'created_at': 1000000,
      };
      final pl = Playlist.fromMap(map);
      expect(pl.songIds, isEmpty);
    });
  });

  group('Liquid Glass Depth & Aurora Theme Tests', () {
    testWidgets('LiquidGlassContainer renders with depth shadow and backdrop filter', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LiquidGlassContainer(
              borderRadius: 36,
              blur: 24,
              shadows: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.55),
                  blurRadius: 26,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: const Color(0xFFD9F99D).withValues(alpha: 0.15),
                  blurRadius: 20,
                  spreadRadius: -2,
                ),
              ],
              child: const Text('Capsule Player Control'),
            ),
          ),
        ),
      );

      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(find.text('Capsule Player Control'), findsOneWidget);
    });

    testWidgets('AuroraBackgroundWidget wraps child smoothly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AuroraBackgroundWidget(
              child: Text('Aurora Content'),
            ),
          ),
        ),
      );

      expect(find.text('Aurora Content'), findsOneWidget);
    });
  });

  group('Playlist Seeder & Deletion Persistence Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      const MethodChannel channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (MethodCall methodCall) async {
          return '.';
        },
      );
    });

    test('Deleted seeder playlists stay deleted and never reappear', () async {
      final library = LibraryProvider(localDb: LocalDatabase.instance);
      await library.refreshPlaylists();

      expect(library.playlists.length, equals(2));
      expect(library.playlists.any((p) => p.id == 'pl_cosmic_vibes'), isTrue);
      expect(library.playlists.any((p) => p.id == 'pl_nebula_acoustic'), isTrue);

      // Delete first seeder playlist
      await library.deletePlaylist('pl_cosmic_vibes');
      expect(library.playlists.length, equals(1));
      expect(library.playlists.first.id, equals('pl_nebula_acoustic'));

      // Delete second seeder playlist (playlists now empty)
      await library.deletePlaylist('pl_nebula_acoustic');
      expect(library.playlists, isEmpty);

      // Refresh / reload playlists — should NOT respawn default playlists!
      await library.refreshPlaylists();
      expect(library.playlists, isEmpty);

      // Create a brand new library instance with same DB / prefs state
      final freshLibrary = LibraryProvider(localDb: LocalDatabase.instance);
      await freshLibrary.refreshPlaylists();
      expect(freshLibrary.playlists, isEmpty);
    });
  });
}
