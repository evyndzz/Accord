import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';
import '../models/song_line.dart';
import 'local_database.dart';
import 'notification_service.dart';

class GoogleDriveSyncService extends ChangeNotifier {
  static const String _prefKeyBridgeUrl = 'gdrive_bridge_url';
  static const String _prefKeyLastSync = 'gdrive_last_sync';

  /// URL default Google Drive Apps Script Web App Bridge
  static const String defaultBridgeUrl =
      'https://script.google.com/macros/s/AKfycbyI26ZoDj7R_CxJ8lZID4UPKVYtkeWM5wk4oBf6AaSlh_zu4LX_e5AW53NeGG3o2p_t/exec';

  final LocalDatabase _localDb = LocalDatabase.instance;

  String? _bridgeUrl;
  bool _isSyncing = false;
  int _cloudSongCount = 0;
  int _cloudChordCount = 0;
  String? _lastSyncTime;
  String? _error;
  Timer? _autoSyncTimer;

  /// Callback yang dipanggil setiap kali syncVault berhasil memperbarui lagu
  VoidCallback? onSyncSuccess;

  bool _isDisposed = false;
  final bool autoSyncOnStart;

  bool get isDisposed => _isDisposed;
  String? get bridgeUrl => _bridgeUrl;
  bool get isConfigured => _bridgeUrl != null && _bridgeUrl!.trim().isNotEmpty;
  bool get isSyncing => _isSyncing;
  int get cloudSongCount => _cloudSongCount;
  int get cloudChordCount => _cloudChordCount;
  String? get lastSyncTime => _lastSyncTime;
  String? get error => _error;

  GoogleDriveSyncService({this.autoSyncOnStart = true}) {
    init();
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _bridgeUrl = prefs.getString(_prefKeyBridgeUrl);
    // Jika belum disetel (misal di desktop Linux atau install baru), gunakan defaultBridgeUrl
    if (_bridgeUrl == null || _bridgeUrl!.trim().isEmpty) {
      _bridgeUrl = defaultBridgeUrl;
      await prefs.setString(_prefKeyBridgeUrl, defaultBridgeUrl);
    }
    _lastSyncTime = prefs.getString(_prefKeyLastSync);
    notifyListeners();

    if (isConfigured && autoSyncOnStart && !Platform.environment.containsKey('FLUTTER_TEST')) {
      startPeriodicAutoSync();
      // Langsung sinkronisasi di background saat inisialisasi agar lagu langsung tersedia
      syncVault(silent: true);
    }
  }

  /// Configure Google Apps Script Web App URL and test connection
  Future<bool> setBridgeUrl(String url) async {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) {
      await disconnect();
      return true;
    }

    _isSyncing = true;
    _error = null;
    notifyListeners();

    try {
      final pingUri = Uri.parse(cleanUrl).replace(queryParameters: {'action': 'ping'});
      final response = await http.get(pingUri).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200 || response.statusCode == 302) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefKeyBridgeUrl, cleanUrl);
        _bridgeUrl = cleanUrl;

        // Perform initial sync immediately and start periodic background auto-sync
        await syncVault();
        startPeriodicAutoSync();
        return true;
      } else {
        _error = 'Respon server Google Apps Script: ${response.statusCode}';
      }
    } catch (e) {
      _error = 'Gagal terhubung ke Google Drive Bridge: $e';
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
    return false;
  }

  Future<void> disconnect() async {
    stopPeriodicAutoSync();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKeyBridgeUrl);
    await prefs.remove(_prefKeyLastSync);
    _bridgeUrl = null;
    _cloudSongCount = 0;
    _cloudChordCount = 0;
    _lastSyncTime = null;
    _error = null;
    notifyListeners();
  }

  Future<void> clearConfiguration() => disconnect();

  /// Starts a periodic background polling sync (e.g. every 30 seconds)
  void startPeriodicAutoSync({Duration interval = const Duration(seconds: 30)}) {
    _autoSyncTimer?.cancel();
    if (!isConfigured) return;

    _autoSyncTimer = Timer.periodic(interval, (_) {
      if (isConfigured && !_isSyncing) {
        syncVault(silent: true);
      }
    });
  }

  /// Stops the background auto-sync timer
  void stopPeriodicAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
  }

  @override
  void dispose() {
    _isDisposed = true;
    stopPeriodicAutoSync();
    super.dispose();
  }

  /// Sync all audio files and chords from Google Drive vault to local database
  /// Includes full reconciliation (pruning deleted songs so they don't reappear)
  Future<bool> syncVault({bool silent = false}) async {
    if (!isConfigured) return false;

    if (!silent) {
      _isSyncing = true;
      _error = null;
      notifyListeners();
    }

    try {
      final syncUri = Uri.parse(_bridgeUrl!).replace(queryParameters: {'action': 'sync'});
      final response = await http.get(syncUri).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final songsList = data['songs'] as List? ?? [];
        final chordsList = data['availableChords'] as List? ?? [];

        _cloudSongCount = songsList.length;
        _cloudChordCount = chordsList.length;

        final activeDriveSongIds = <String>{};
        final newlyDiscoveredSongs = <Song>[];

        // Save active songs to SQLite database
        for (final item in songsList) {
          final id = item['id'] as String;
          final title = item['title'] as String? ?? 'Tanpa Judul';
          activeDriveSongIds.add(id);
          final rawCloudArtist = (item['artist'] as String?)?.trim() ?? '';
          final cloudArtist = (rawCloudArtist.isNotEmpty && rawCloudArtist != 'Google Drive')
              ? rawCloudArtist
              : '';
          final streamUrl = item['streamUrl'] as String?;
          final cloudAlbumArt = item['albumArtUrl'] as String?;

          final existing = await _localDb.getSong(id);
          final lines = existing?.lines ?? const [];

          // Resolusi artis:
          // Jika artis sudah ada di SQLite lokal (hasil editan pengguna) dan bukan placeholder,
          // pertahankan artis tersebut secara persisten!
          String resolvedArtist;
          if (existing != null &&
              existing.artist.trim().isNotEmpty &&
              existing.artist != 'Google Drive' &&
              existing.artist != 'Unknown Artist' &&
              existing.artist != 'Local Audio' &&
              existing.artist != 'Tidak Diketahui') {
            resolvedArtist = existing.artist.trim();
          } else if (cloudArtist.isNotEmpty) {
            resolvedArtist = cloudArtist;
          } else {
            resolvedArtist = 'Tidak Diketahui';
          }

          final song = Song(
            id: id,
            title: title, // Selalu gunakan judul lengkap resmi dari Google Drive
            artist: resolvedArtist,
            albumArtUrl: cloudAlbumArt ?? existing?.albumArtUrl,
            durationMs: existing?.durationMs ?? 0,
            originalKey: existing?.originalKey ?? 'C',
            lines: lines,
            streamUrl: streamUrl,
            sourceType: 'drive',
            bpm: existing?.bpm,
            timeSignature: existing?.timeSignature,
            startBeat: existing?.startBeat,
            startBeatOffsetMs: existing?.startBeatOffsetMs,
            gradientColors: const [Color(0xFF4285F4), Color(0xFF34A853)],
          );

          await _localDb.insertSong(song, sourceType: 'drive');

          // If this song was NOT in SQLite before, it's newly added from Google Drive!
          if (existing == null) {
            newlyDiscoveredSongs.add(song);
          }
        }

        // Two-Way Pruning: Remove local drive songs no longer in cloud vault
        // This permanently eliminates "zombie songs" across all devices!
        await _localDb.pruneOrphanedDriveSongs(activeDriveSongIds);

        // Auto pre-fetch chords and synced metadata for songs that have chord files in cloud vault
        if (chordsList.isNotEmpty) {
          final chordSet = chordsList.map((c) => c.toString().trim().toLowerCase()).toSet();
          for (final item in songsList) {
            final id = item['id'] as String;
            final title = (item['title'] as String? ?? '').trim();
            final hasChord = chordSet.contains(id.toLowerCase()) ||
                (title.isNotEmpty && chordSet.contains(title.toLowerCase()));
            if (hasChord) {
              await fetchChordForTrack(id, title: title);
            }
          }
        }

        // Notify user about newly discovered songs so they can add chords/lyrics
        if (newlyDiscoveredSongs.isNotEmpty) {
          for (final newSong in newlyDiscoveredSongs) {
            NotificationService.instance.showNewSongNotification(newSong);
          }
        }

        final now = DateTime.now();
        _lastSyncTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefKeyLastSync, _lastSyncTime!);

        _error = null;
        try {
          onSyncSuccess?.call();
        } catch (_) {}
        return true;
      } else {
        _error = 'Sync gagal dengan kode: ${response.statusCode}';
      }
    } catch (e) {
      _error = 'Kendala sinkronisasi Google Drive: $e';
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
    return false;
  }

  /// Delete song (audio and chord) from Google Drive vault and local SQLite
  Future<bool> deleteSongFromCloud(String songId) async {
    // 1. Delete from local SQLite immediately for 0ms instant UI response
    await _localDb.deleteSong(songId);
    notifyListeners();

    if (!isConfigured) return true;

    // 2. Delete / trash on Google Drive
    try {
      final uri = Uri.parse(_bridgeUrl!).replace(queryParameters: {
        'action': 'delete_song',
        'id': songId,
      });

      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        if (data['status'] == 'success') {
          // Re-sync vault metadata in background
          syncVault(silent: true);
          return true;
        }
      }
    } catch (e) {
      debugPrint('Error deleting song from cloud: $e');
    }
    return false;
  }

  /// Delete chord file from Google Drive cloud vault
  Future<bool> deleteChordFromCloud(String trackId) async {
    if (!isConfigured) return false;

    try {
      final uri = Uri.parse(_bridgeUrl!).replace(queryParameters: {
        'action': 'delete_chord',
        'id': trackId,
      });

      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error deleting chord from cloud: $e');
    }
    return false;
  }

  /// Fetch chord and synchronized lyric lines from Google Drive vault by song ID or title
  Future<List<SongLine>?> fetchChordForTrack(String trackId, {String? title}) async {
    if (!isConfigured) return null;

    try {
      final queryParams = <String, String>{
        'action': 'get_chord',
        'id': trackId,
      };
      if (title != null && title.isNotEmpty) {
        queryParams['title'] = title;
      }

      final uri = Uri.parse(_bridgeUrl!).replace(queryParameters: queryParams);

      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        if (data['found'] == true && data['chordData'] != null) {
          final chordData = data['chordData'] as Map<String, dynamic>;
          final rawLines = chordData['lines'] as List? ?? [];

          final lines = rawLines.map((l) => SongLine(
            lineIndex: l['lineIndex'] as int? ?? 0,
            startTimeMs: l['startTimeMs'] as int? ?? 0,
            rawLine: l['rawLine'] as String? ?? '',
          )).toList();

          if (lines.isNotEmpty) {
            // Save to local database for offline fast loading
            await _localDb.updateSongLines(trackId, lines);
          }

          // Perbarui BPM, Birama, Start Beat, Offset, Original Key, dan Artist dari data Cloud
          final cloudBpm = (chordData['bpm'] as num?)?.toDouble();
          final cloudTimeSignature = chordData['timeSignature'] as String?;
          final cloudStartBeat = chordData['startBeat'] as int?;
          final cloudStartBeatOffsetMs = chordData['startBeatOffsetMs'] as int?;
          final cloudKey = chordData['originalKey'] as String?;
          final cloudArtist = chordData['artist']?.toString();

          await _localDb.updateSongCloudMetadata(
            trackId,
            artist: cloudArtist,
            originalKey: cloudKey,
            bpm: cloudBpm,
            timeSignature: cloudTimeSignature,
            startBeat: cloudStartBeat,
            startBeatOffsetMs: cloudStartBeatOffsetMs,
          );
          return lines;
        }
      }
    } catch (e) {
      debugPrint('Cloud chord fetch notice for $trackId: $e');
    }
    return null;
  }

  /// Save chord & lyrics to Google Drive cloud vault
  Future<bool> saveChordToCloud(Song song) async {
    if (!isConfigured) return false;

    try {
      final payload = {
        'action': 'save_chord',
        'id': song.id,
        'source': song.id.startsWith('drive_') ? 'drive' : 'local',
        'title': song.title,
        'artist': song.artist,
        'originalKey': song.originalKey ?? 'C',
        'durationMs': song.durationMs,
        'bpm': song.effectiveBpm,
        'timeSignature': song.effectiveTimeSignature,
        'startBeat': song.effectiveStartBeat,
        'startBeatOffsetMs': song.effectiveStartBeatOffsetMs,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'lines': song.lines.map((l) => {
          'lineIndex': l.lineIndex,
          'startTimeMs': l.startTimeMs,
          'rawLine': l.rawLine,
        }).toList(),
      };

      // Gunakan POST agar payload data (chord + lirik panjang) tidak terpotong
      // oleh batas panjang URL (±2000-8000 karakter) seperti pada GET request.
      final response = await http.post(
        Uri.parse(_bridgeUrl!),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(payload),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        if (data['status'] == 'success') {
          _cloudChordCount++;
          notifyListeners();
          return true;
        }
        debugPrint('saveChordToCloud: server responded non-success: ${response.body}');
      } else {
        debugPrint('saveChordToCloud: HTTP ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('Cloud chord save exception: $e');
    }
    return false;
  }

  /// Upload audio file to Google Drive Accord Music/audio folder
  Future<Map<String, dynamic>?> uploadAudioFile({
    required String filename,
    required List<int> bytes,
    String? mimeType,
  }) async {
    if (!isConfigured) return null;

    try {
      _isSyncing = true;
      notifyListeners();

      final base64Data = base64Encode(bytes);
      final payload = {
        'action': 'upload_audio',
        'filename': filename,
        'mimeType': mimeType ?? 'audio/mpeg',
        'data': base64Data,
      };

      final response = await http.post(
        Uri.parse(_bridgeUrl!),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(payload),
      ).timeout(const Duration(seconds: 45));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        if (data['status'] == 'success') {
          _cloudSongCount++;
          notifyListeners();
          return data;
        }
      }
    } catch (e) {
      debugPrint('Error uploading audio to Google Drive: $e');
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
    return null;
  }

  /// Upload cover photo to Google Drive Accord Music root folder
  Future<String?> uploadCoverImage({
    required String filename,
    required List<int> bytes,
    String? mimeType,
  }) async {
    if (!isConfigured) return null;

    try {
      _isSyncing = true;
      notifyListeners();

      final base64Data = base64Encode(bytes);
      final payload = {
        'action': 'upload_cover',
        'filename': filename,
        'mimeType': mimeType ?? 'image/jpeg',
        'data': base64Data,
      };

      final response = await http.post(
        Uri.parse(_bridgeUrl!),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(payload),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        if (data['status'] == 'success' && data['imageUrl'] != null) {
          notifyListeners();
          return data['imageUrl'] as String;
        }
      }
    } catch (e) {
      debugPrint('Error uploading cover to Google Drive: $e');
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
    return null;
  }
}
