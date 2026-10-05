import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../models/song.dart';
import 'google_drive_sync_service.dart';
import 'local_database.dart';

class GoogleDriveAudioService extends ChangeNotifier {
  final LocalDatabase _localDb = LocalDatabase.instance;
  List<Song> _driveSongs = [];
  bool _isLoading = false;
  bool _isProbing = false;
  bool _isDisposed = false;
  final Map<String, double> _downloadProgress = {};

  List<Song> get driveSongs => _driveSongs;
  bool get isLoading => _isLoading;
  Map<String, double> get downloadProgress => _downloadProgress;

  GoogleDriveAudioService() {
    loadDriveSongs();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  /// Extract the Google Drive file ID from various link formats
  static String? extractFileId(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    // Pattern 1: /file/d/<id>/
    final matchD = RegExp(r'/file/d/([a-zA-Z0-9_-]+)').firstMatch(trimmed);
    if (matchD != null && matchD.groupCount >= 1) {
      return matchD.group(1);
    }

    // Pattern 2: /folders/<id>
    final matchFolder = RegExp(r'/folders/([a-zA-Z0-9_-]+)').firstMatch(trimmed);
    if (matchFolder != null && matchFolder.groupCount >= 1) {
      return matchFolder.group(1);
    }

    // Pattern 3: ?id=<id> or &id=<id>
    final matchId = RegExp(r'[?&]id=([a-zA-Z0-9_-]+)').firstMatch(trimmed);
    if (matchId != null && matchId.groupCount >= 1) {
      return matchId.group(1);
    }

    // Pattern 4: direct ID string (usually 20 to 50 alphanumeric characters)
    if (RegExp(r'^[a-zA-Z0-9_-]{20,50}$').hasMatch(trimmed)) {
      return trimmed;
    }

    return null;
  }

  /// Get direct streaming URL for a Google Drive file
  static String getDirectStreamUrl(String fileId) {
    return 'https://drive.usercontent.google.com/download?id=$fileId&export=download';
  }

  /// Alias to loadDriveSongs
  Future<List<Song>> loadSongs() => loadDriveSongs();

  /// Load all Google Drive songs from local SQLite database
  Future<List<Song>> loadDriveSongs() async {
    _isLoading = true;
    notifyListeners();
    try {
      _driveSongs = await _localDb.getGoogleDriveSongs();
    } catch (e) {
      debugPrint('Error loading Google Drive songs: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }

    // Deteksi durasi asli lagu yang masih 00:00 di latar belakang tanpa menghambat UI
    _probeMissingDurations();
    return _driveSongs;
  }

  /// Update durasi lagu langsung di memori tampilan
  void updateSongDurationInMemory(String songId, int durationMs) {
    final idx = _driveSongs.indexWhere((s) => s.id == songId);
    if (idx != -1) {
      _driveSongs[idx] = _driveSongs[idx].copyWith(durationMs: durationMs);
      notifyListeners();
    }
  }

  /// Deteksi durasi audio stream Google Drive secara asynchronous
  Future<void> _probeMissingDurations() async {
    if (_isProbing) return;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    _isProbing = true;

    final missing = _driveSongs.where((s) => s.durationMs <= 0 && s.streamUrl != null && s.streamUrl!.isNotEmpty).toList();
    if (missing.isEmpty) {
      _isProbing = false;
      return;
    }

    for (final song in missing) {
      AudioPlayer? probePlayer;
      try {
        probePlayer = AudioPlayer();
        final dur = await probePlayer.setUrl(song.streamUrl!).timeout(const Duration(seconds: 6));
        if (dur != null && dur.inMilliseconds > 0) {
          updateSongDurationInMemory(song.id, dur.inMilliseconds);
          await _localDb.updateSongDuration(song.id, dur.inMilliseconds);
        }
      } catch (_) {
        // Lewati jika kendala jaringan sesaat
      } finally {
        try {
          await probePlayer?.dispose();
        } catch (_) {}
      }
    }
    _isProbing = false;
  }

  /// Add a new song from Google Drive link
  Future<Song?> addDriveSong({
    required String driveLink,
    required String title,
    required String artist,
    String? originalKey,
  }) async {
    final fileId = extractFileId(driveLink);
    if (fileId == null) {
      throw Exception('Format link Google Drive tidak valid.');
    }

    final streamUrl = getDirectStreamUrl(fileId);
    final songId = 'drive_$fileId';

    final song = Song(
      id: songId,
      title: title.trim().isNotEmpty ? title.trim() : 'Drive Audio $fileId',
      artist: artist.trim().isNotEmpty ? artist.trim() : 'Tidak Diketahui',
      originalKey: originalKey ?? 'C',
      durationMs: 0, // Will auto-detect on first playback
      streamUrl: streamUrl,
      lines: const [],
      gradientColors: const [Color(0xFF4285F4), Color(0xFF34A853)],
    );

    await _localDb.insertSong(song, sourceType: 'drive');
    await loadDriveSongs();
    return song;
  }

  /// Download Google Drive song to local app storage for offline playback
  Future<bool> downloadForOffline(Song song) async {
    final fileId = extractFileId(song.id.replaceAll('drive_', '')) ??
        extractFileId(song.streamUrl ?? '');
    if (fileId == null) return false;

    _downloadProgress[song.id] = 0.05;
    notifyListeners();

    try {
      final streamUrl = song.streamUrl ?? getDirectStreamUrl(fileId);
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(streamUrl));
      final response = await client.send(request);

      if (response.statusCode == 200 || response.statusCode == 206) {
        final dir = await getApplicationDocumentsDirectory();
        final saveDir = Directory('${dir.path}/drive_music');
        if (!await saveDir.exists()) {
          await saveDir.create(recursive: true);
        }

        final filePath = '${saveDir.path}/${song.id}.mp3';
        final file = File(filePath);
        final sink = file.openWrite();

        final totalBytes = response.contentLength ?? 1;
        var receivedBytes = 0;

        await response.stream.forEach((chunk) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          if (totalBytes > 1) {
            _downloadProgress[song.id] = (receivedBytes / totalBytes).clamp(0.05, 0.99);
            notifyListeners();
          }
        });

        await sink.close();

        // Update local database with offline file path without overwriting lines or bpm
        await _localDb.updateSongFilePath(song.id, filePath);
        _downloadProgress.remove(song.id);
        await loadDriveSongs();
        return true;
      }
    } catch (e) {
      debugPrint('Download Google Drive song error: $e');
    } finally {
      _downloadProgress.remove(song.id);
      notifyListeners();
    }
    return false;
  }

  /// Delete a Google Drive song from database, disk, and cloud vault
  Future<void> deleteDriveSong(String songId, {GoogleDriveSyncService? syncService}) async {
    try {
      final song = await _localDb.getSong(songId);
      if (song != null && song.filePath != null && song.filePath!.isNotEmpty) {
        final f = File(song.filePath!);
        if (await f.exists()) {
          await f.delete();
        }
      }
      if (syncService != null && syncService.isConfigured) {
        await syncService.deleteSongFromCloud(songId);
      } else {
        await _localDb.deleteSong(songId);
      }
      await loadDriveSongs();
    } catch (e) {
      debugPrint('Error deleting drive song: $e');
    }
  }
}
