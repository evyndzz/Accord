import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/local_database.dart';

/// Manages offline & persistent disk caching of audio streams.
/// Once cached, songs play with 0ms buffering latency directly from local disk.
class AudioCacheService {
  static AudioCacheService? _instance;
  static Directory? _cacheDir;

  AudioCacheService._();

  static AudioCacheService get instance {
    _instance ??= AudioCacheService._();
    return _instance!;
  }

  @visibleForTesting
  static set cacheDirectoryForTesting(Directory? dir) => _cacheDir = dir;

  /// Ensure and return the dedicated song cache directory
  Future<Directory> get cacheDirectory async {
    if (_cacheDir != null && await _cacheDir!.exists()) {
      return _cacheDir!;
    }
    final baseDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(baseDir.path, 'songs_cache'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cacheDir = dir;
    return dir;
  }

  /// Get the expected file path for a track ID
  Future<String> getCacheFilePath(String trackId) async {
    final cleanId = trackId.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final dir = await cacheDirectory;
    return p.join(dir.path, '$cleanId.m4a');
  }

  /// Check if a track is already cached locally on disk
  Future<String?> getCachedPathIfExists(String trackId) async {
    try {
      final path = await getCacheFilePath(trackId);
      final file = File(path);
      if (await file.exists()) {
        final length = await file.length();
        if (length > 50000) { // Valid file at least ~50KB
          return path;
        }
      }
    } catch (e) {
      debugPrint('Error checking cache for track $trackId: $e');
    }
    return null;
  }

  /// Download and cache audio in the background without blocking the UI
  Future<String?> cacheStreamInBackground({
    required String trackId,
    required String streamUrl,
    required String title,
    required String artist,
    String? artworkUrl,
    int durationMs = 0,
    LocalDatabase? localDb,
  }) async {
    try {
      final targetPath = await getCacheFilePath(trackId);
      final targetFile = File(targetPath);
      if (await targetFile.exists() && await targetFile.length() > 50000) {
        return targetPath;
      }

      final tempPath = '$targetPath.part';
      final tempFile = File(tempPath);
      if (await tempFile.exists()) {
        try { await tempFile.delete(); } catch (_) {}
      }

      debugPrint('Starting background cache for: $title');
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(streamUrl)).timeout(const Duration(seconds: 8));
      req.headers.set('User-Agent', 'Mozilla/5.0 (Linux; Android 14) Chrome/120.0.0.0 Mobile Safari/537.36');
      final response = await req.close().timeout(const Duration(seconds: 35));

      if (response.statusCode == 200 || response.statusCode == 206) {
        final sink = tempFile.openWrite();
        await response.pipe(sink);
        client.close(force: true);

        if (await tempFile.exists() && await tempFile.length() > 50000) {
          await tempFile.rename(targetPath);
          debugPrint('Successfully cached audio to: $targetPath (${await targetFile.length()} bytes)');

          // Update local database cached file path without overwriting lines or bpm
          if (localDb != null) {
            await localDb.updateSongFilePath(trackId, targetPath);
          }

          return targetPath;
        }
      } else {
        client.close(force: true);
        debugPrint('Background cache HTTP error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Background caching failed for "$title": $e');
    }
    return null;
  }
}
