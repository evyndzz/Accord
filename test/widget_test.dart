import 'dart:io';
import 'package:accord/models/song.dart';
import 'package:accord/services/audio_cache_service.dart';
import 'package:accord/services/audio_player_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    AudioCacheService.cacheDirectoryForTesting = Directory.systemTemp;
  });

  group('AudioPlayerService Tests', () {
    late AudioPlayerService audioService;

    setUp(() {
      audioService = AudioPlayerService();
    });

    tearDown(() {
      audioService.dispose();
    });

    test('AudioPlayerService initializes with player stopped', () {
      expect(audioService.isPlaying, isFalse);
      expect(audioService.currentPosition, equals(Duration.zero));
      expect(audioService.player, isNotNull);
    });

    test('playSong rejects empty song gracefully', () async {
      const song = Song(
        id: 'empty_test',
        title: 'Empty Song',
        artist: 'Unknown',
        durationMs: 180000,
        lines: [],
      );
      final result = await audioService.playSong(song);
      expect(result, isFalse);
    });

    test('playSong handles nonexistent filePath gracefully', () async {
      const song = Song(
        id: 'missing_file',
        title: 'Missing Song',
        artist: 'Unknown',
        durationMs: 180000,
        filePath: '/invalid/path/to/missing_audio.mp3',
        lines: [],
      );
      final result = await audioService.playSong(song);
      expect(result, isFalse);
    });
  });

  group('AudioCacheService Tests', () {
    test('getCacheFilePath sanitizes special characters cleanly', () async {
      final cacheService = AudioCacheService.instance;
      final path = await cacheService.getCacheFilePath('cloud_vault:track:4cOdK2wGLETKBW3PvgPWqT');
      expect(path, isNotEmpty);
      expect(path.endsWith('.m4a'), isTrue);
      expect(path.contains(':'), isFalse);
    });

    test('getCachedPathIfExists returns null for non-cached track', () async {
      final cacheService = AudioCacheService.instance;
      final cached = await cacheService.getCachedPathIfExists('non_existent_track_9999');
      expect(cached, isNull);
    });
  });
}

