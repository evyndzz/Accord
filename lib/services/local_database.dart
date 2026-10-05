import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/playlist.dart';
import '../models/song.dart';
import '../models/song_line.dart';

/// Manages all offline/user-created songs stored in SQLite on device.
/// Compatible across Android, iOS, Linux Desktop, and Windows.
class LocalDatabase {
  static LocalDatabase? _instance;
  static Database? _db;
  static Future<Database>? _initDbFuture;

  LocalDatabase._();

  static LocalDatabase get instance {
    _instance ??= LocalDatabase._();
    return _instance!;
  }

  Future<Database> get database async {
    if (_db != null) return _db!;
    _initDbFuture ??= _initDb();
    _db = await _initDbFuture;
    return _db!;
  }

  Future<Database> _initDb() async {
    // Initialize FFI for Linux / Windows / macOS desktop
    if (!kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'accord_local.db');
    final db = await openDatabase(
      path,
      version: 5,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );

    // Hapus semua data mock/dummy lagu lama agar tidak muncul di aplikasi
    try {
      await db.delete('local_songs', where: "id LIKE 'mock_%'");
    } catch (_) {}

    // Pastikan tabel playlists tersedia
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS playlists (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          song_ids TEXT NOT NULL DEFAULT '',
          created_at INTEGER NOT NULL,
          logo_id TEXT DEFAULT 'saturn_orbit'
        )
      ''');
      await db.execute('ALTER TABLE playlists ADD COLUMN logo_id TEXT DEFAULT \'saturn_orbit\'');
    } catch (_) {}

    // Bersihkan placeholder artist lama ('Google Drive', 'Unknown Artist', 'Local Audio') menjadi 'Tidak Diketahui'
    try {
      await db.execute(
        "UPDATE local_songs SET artist = 'Tidak Diketahui' WHERE artist = 'Google Drive' OR artist = 'Unknown Artist' OR artist = 'Local Audio' OR TRIM(artist) = ''",
      );
    } catch (_) {}

    return db;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS playlists (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        song_ids TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL,
        logo_id TEXT DEFAULT 'saturn_orbit'
      )
    ''');
    await db.execute('''
      CREATE TABLE local_songs (
        id TEXT PRIMARY KEY,
        cloud_id TEXT,
        title TEXT NOT NULL,
        artist TEXT NOT NULL,
        album_art_url TEXT,
        duration_ms INTEGER NOT NULL DEFAULT 0,
        original_key TEXT,
        gradient_colors TEXT,
        file_path TEXT,
        stream_url TEXT,
        source_type TEXT,
        bpm REAL DEFAULT 120.0,
        time_signature TEXT DEFAULT '4/4',
        start_beat INTEGER DEFAULT 1,
        start_beat_offset_ms INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE local_song_lines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        song_id TEXT NOT NULL,
        line_index INTEGER NOT NULL,
        start_time_ms INTEGER NOT NULL,
        raw_line TEXT NOT NULL,
        FOREIGN KEY (song_id) REFERENCES local_songs(id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute('ALTER TABLE local_songs ADD COLUMN file_path TEXT;');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE local_songs ADD COLUMN stream_url TEXT;');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE local_songs ADD COLUMN source_type TEXT;');
      } catch (_) {}
    }

    if (oldVersion < 3) {
      try {
        await db.execute('ALTER TABLE local_songs ADD COLUMN cloud_id TEXT;');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE local_songs ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0;');
      } catch (_) {}
    }

    if (oldVersion < 4) {
      try {
        await db.execute('ALTER TABLE local_songs ADD COLUMN bpm REAL DEFAULT 120.0;');
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE local_songs ADD COLUMN time_signature TEXT DEFAULT '4/4';");
      } catch (_) {}
    }

    if (oldVersion < 5) {
      try {
        await db.execute('ALTER TABLE local_songs ADD COLUMN start_beat INTEGER DEFAULT 1;');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE local_songs ADD COLUMN start_beat_offset_ms INTEGER DEFAULT 0;');
      } catch (_) {}
    }
  }

  // ── CRUD Songs ────────────────────────────────────────────────────────────

  Future<void> insertSong(Song song, {String? sourceType}) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.insert(
      'local_songs',
      {
        'id': song.id,
        'cloud_id': song.id.startsWith('drive_') ? song.id.replaceFirst('drive_', '') : null,
        'title': song.title,
        'artist': song.artist,
        'album_art_url': song.albumArtUrl,
        'duration_ms': song.durationMs,
        'original_key': song.originalKey,
        'gradient_colors': song.gradientColors != null
            ? jsonEncode(song.gradientColors!.map((c) => c.toARGB32()).toList())
            : null,
        'file_path': song.filePath,
        'stream_url': song.streamUrl,
        'source_type': sourceType ?? (song.id.startsWith('drive_') ? 'drive' : 'local'),
        'bpm': song.effectiveBpm,
        'time_signature': song.effectiveTimeSignature,
        'start_beat': song.effectiveStartBeat,
        'start_beat_offset_ms': song.effectiveStartBeatOffsetMs,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Clear old lines if updating
    await db.delete('local_song_lines', where: 'song_id = ?', whereArgs: [song.id]);

    // Insert lines
    if (song.lines.isNotEmpty) {
      final batch = db.batch();
      for (final line in song.lines) {
        batch.insert(
          'local_song_lines',
          {
            'song_id': song.id,
            'line_index': line.lineIndex,
            'start_time_ms': line.startTimeMs,
            'raw_line': line.rawLine,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    }
  }

  Future<void> updateSongDuration(String id, int durationMs) async {
    final db = await database;
    await db.update(
      'local_songs',
      {
        'duration_ms': durationMs,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateSongBeatSettings(
    String id, {
    required double bpm,
    required String timeSignature,
    required int startBeat,
    required int startBeatOffsetMs,
  }) async {
    final db = await database;
    await db.update(
      'local_songs',
      {
        'bpm': bpm,
        'time_signature': timeSignature,
        'start_beat': startBeat,
        'start_beat_offset_ms': startBeatOffsetMs,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateSongCloudMetadata(
    String id, {
    String? artist,
    String? originalKey,
    double? bpm,
    String? timeSignature,
    int? startBeat,
    int? startBeatOffsetMs,
  }) async {
    final db = await database;
    final values = <String, dynamic>{
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    };
    if (artist != null) {
      final a = artist.trim();
      if (a.isNotEmpty &&
          a != 'Google Drive' &&
          a != 'Unknown Artist' &&
          a != 'Local Audio' &&
          a != 'Tidak Diketahui') {
        values['artist'] = a;
      }
    }
    if (originalKey != null && originalKey.trim().isNotEmpty) {
      values['original_key'] = originalKey.trim();
    }
    if (bpm != null && bpm > 0) {
      values['bpm'] = bpm;
    }
    if (timeSignature != null && timeSignature.trim().isNotEmpty) {
      values['time_signature'] = timeSignature.trim();
    }
    if (startBeat != null && startBeat >= 1) {
      values['start_beat'] = startBeat;
    }
    if (startBeatOffsetMs != null && startBeatOffsetMs >= 0) {
      values['start_beat_offset_ms'] = startBeatOffsetMs;
    }
    await db.update(
      'local_songs',
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateSongTempo(String id, double bpm, String timeSignature) async {
    final db = await database;
    await db.update(
      'local_songs',
      {
        'bpm': bpm,
        'time_signature': timeSignature,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateSongArtist(String id, String artist) async {
    final db = await database;
    await db.update(
      'local_songs',
      {
        'artist': artist.trim().isNotEmpty ? artist.trim() : 'Tidak Diketahui',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateSongFilePath(String id, String filePath) async {
    final db = await database;
    await db.update(
      'local_songs',
      {
        'file_path': filePath,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Song>> getAllSongs() async {
    final db = await database;
    final maps = await db.query('local_songs', orderBy: 'updated_at DESC, created_at DESC');
    final songs = <Song>[];
    for (final map in maps) {
      final lines = await _getLinesForSong(map['id'] as String);
      songs.add(_songFromMap(map, lines));
    }
    return songs;
  }

  Future<List<Song>> getGoogleDriveSongs() async {
    final db = await database;
    final maps = await db.query(
      'local_songs',
      where: "source_type = 'drive' OR id LIKE 'drive_%'",
      orderBy: 'updated_at DESC, created_at DESC',
    );
    final songs = <Song>[];
    for (final map in maps) {
      final lines = await _getLinesForSong(map['id'] as String);
      songs.add(_songFromMap(map, lines));
    }
    return songs;
  }

  Future<List<Song>> getLocalDeviceSongs() async {
    final db = await database;
    final maps = await db.query(
      'local_songs',
      where: "file_path IS NOT NULL AND file_path != '' AND (source_type = 'local_device' OR source_type = 'local' OR source_type IS NULL)",
      orderBy: 'created_at DESC',
    );
    final songs = <Song>[];
    for (final map in maps) {
      final lines = await _getLinesForSong(map['id'] as String);
      songs.add(_songFromMap(map, lines));
    }
    return songs;
  }

  /// Import one or more audio files from local phone storage
  Future<List<Song>> importAudioFiles(List<String> filePaths) async {
    final imported = <Song>[];
    final db = await database;

    for (int i = 0; i < filePaths.length; i++) {
      final filePath = filePaths[i];
      if (filePath.isEmpty) continue;

      // Check if file already exists in database
      final existing = await db.query(
        'local_songs',
        where: 'file_path = ?',
        whereArgs: [filePath],
        limit: 1,
      );

      if (existing.isNotEmpty) {
        final lines = await _getLinesForSong(existing.first['id'] as String);
        imported.add(_songFromMap(existing.first, lines));
        continue;
      }

      // Pertahankan judul lengkap file agar tidak terpotong (misal: "Di Badai Topan Dunia - Pop Rohani KK 497 (Live)")
      final fileName = p.basenameWithoutExtension(filePath).trim();
      const String artist = 'Tidak Diketahui';
      final String title = fileName;

      final songId = 'local_${DateTime.now().millisecondsSinceEpoch}_$i';

      final song = Song(
        id: songId,
        title: title,
        artist: artist,
        durationMs: 0,
        originalKey: 'C',
        filePath: filePath,
        sourceType: 'local_device',
        lines: const [],
        gradientColors: const [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
      );

      await insertSong(song, sourceType: 'local_device');
      imported.add(song);
    }

    return imported;
  }

  Future<Song?> getSong(String id) async {
    final db = await database;
    final maps = await db.query(
      'local_songs',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    final lines = await _getLinesForSong(id);
    return _songFromMap(maps.first, lines);
  }

  Future<void> deleteSong(String id) async {
    final db = await database;
    await db.delete('local_songs', where: 'id = ?', whereArgs: [id]);
    await db.delete('local_song_lines', where: 'song_id = ?', whereArgs: [id]);
  }

  /// Prunes any local songs originating from Google Drive that are no longer
  /// present in the active Drive vault (e.g. deleted on another device or web).
  /// This prevents deleted songs from reappearing as "zombie songs".
  Future<int> pruneOrphanedDriveSongs(Set<String> activeDriveSongIds) async {
    final db = await database;
    final driveSongs = await db.query(
      'local_songs',
      columns: ['id'],
      where: "source_type = 'drive' OR id LIKE 'drive_%'",
    );

    int prunedCount = 0;
    await db.transaction((txn) async {
      for (final row in driveSongs) {
        final id = row['id'] as String;
        if (!activeDriveSongIds.contains(id)) {
          await txn.delete('local_songs', where: 'id = ?', whereArgs: [id]);
          await txn.delete('local_song_lines', where: 'song_id = ?', whereArgs: [id]);
          prunedCount++;
        }
      }
    });

    return prunedCount;
  }

  Future<void> updateSongLines(String songId, List<SongLine> lines) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.update(
      'local_songs',
      {'updated_at': now},
      where: 'id = ?',
      whereArgs: [songId],
    );

    await db.delete('local_song_lines', where: 'song_id = ?', whereArgs: [songId]);
    final batch = db.batch();
    for (final line in lines) {
      batch.insert('local_song_lines', {
        'song_id': songId,
        'line_index': line.lineIndex,
        'start_time_ms': line.startTimeMs,
        'raw_line': line.rawLine,
      });
    }
    await batch.commit(noResult: true);
  }

  // ── Multi-Platform Cross-Device Sync (Export & Safe Merge) ─────────────────

  /// Export database as a portable JSON structure for cross-device sync
  /// Does NOT leak device-specific local paths; uses cloud IDs and metadata.
  Future<Map<String, dynamic>> exportFullDatabaseJson({String? deviceName}) async {
    final db = await database;
    final songsList = await db.query('local_songs', orderBy: 'created_at ASC');

    final exportedSongs = <Map<String, dynamic>>[];
    for (final sMap in songsList) {
      final songId = sMap['id'] as String;
      final linesList = await db.query(
        'local_song_lines',
        where: 'song_id = ?',
        whereArgs: [songId],
        orderBy: 'line_index ASC',
      );

      exportedSongs.add({
        'id': songId,
        'cloud_id': sMap['cloud_id'],
        'title': sMap['title'],
        'artist': sMap['artist'],
        'album_art_url': sMap['album_art_url'],
        'duration_ms': sMap['duration_ms'],
        'original_key': sMap['original_key'],
        'gradient_colors': sMap['gradient_colors'],
        'stream_url': sMap['stream_url'],
        'source_type': sMap['source_type'],
        'created_at': sMap['created_at'],
        'updated_at': sMap['updated_at'] ?? sMap['created_at'],
        'lines': linesList.map((l) => {
          'line_index': l['line_index'],
          'start_time_ms': l['start_time_ms'],
          'raw_line': l['raw_line'],
        }).toList(),
      });
    }

    return {
      'version': 1,
      'exported_at': DateTime.now().millisecondsSinceEpoch,
      'device_name': deviceName ?? (!kIsWeb && Platform.isAndroid ? 'Android Phone' : 'Laptop Desktop'),
      'songs_count': exportedSongs.length,
      'songs': exportedSongs,
    };
  }

  /// Safely import and merge JSON database received from another device
  /// Wrapped in an atomic transaction to guarantee 0 data corruption.
  Future<int> importAndMergeDatabaseJson(Map<String, dynamic> data) async {
    final songsData = data['songs'] as List?;
    if (songsData == null || songsData.isEmpty) return 0;

    final db = await database;
    int mergedCount = 0;

    await db.transaction((txn) async {
      for (final item in songsData) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final id = map['id'] as String?;
        if (id == null || id.isEmpty) continue;

        final incomingUpdatedAt = (map['updated_at'] as int?) ?? (map['created_at'] as int?) ?? 0;

        // Check if song already exists locally
        final existing = await txn.query(
          'local_songs',
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );

        String? preservedFilePath;
        if (existing.isNotEmpty) {
          final existingUpdatedAt = (existing.first['updated_at'] as int?) ??
              (existing.first['created_at'] as int?) ?? 0;
          preservedFilePath = existing.first['file_path'] as String?;

          // If local is strictly newer, skip overwriting
          if (existingUpdatedAt > incomingUpdatedAt) {
            continue;
          }
        }

        // Upsert song
        await txn.insert(
          'local_songs',
          {
            'id': id,
            'cloud_id': map['cloud_id'],
            'title': map['title'] ?? 'Unknown Title',
            'artist': map['artist'] ?? 'Unknown Artist',
            'album_art_url': map['album_art_url'],
            'duration_ms': (map['duration_ms'] as int?) ?? 0,
            'original_key': map['original_key'] ?? 'C',
            'gradient_colors': map['gradient_colors'],
            'file_path': preservedFilePath, // Keep local file path if present on this device
            'stream_url': map['stream_url'],
            'source_type': map['source_type'] ?? 'local',
            'created_at': (map['created_at'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
            'updated_at': incomingUpdatedAt,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        // Replace lines
        await txn.delete('local_song_lines', where: 'song_id = ?', whereArgs: [id]);
        final lines = map['lines'] as List?;
        if (lines != null && lines.isNotEmpty) {
          final batch = txn.batch();
          for (final lineData in lines) {
            if (lineData is! Map) continue;
            batch.insert(
              'local_song_lines',
              {
                'song_id': id,
                'line_index': lineData['line_index'] as int,
                'start_time_ms': lineData['start_time_ms'] as int,
                'raw_line': lineData['raw_line'] as String,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          await batch.commit(noResult: true);
        }

        mergedCount++;
      }
    });

    return mergedCount;
  }

  Future<List<SongLine>> _getLinesForSong(String songId) async {
    final db = await database;
    final maps = await db.query(
      'local_song_lines',
      where: 'song_id = ?',
      whereArgs: [songId],
      orderBy: 'line_index ASC',
    );
    return maps.map((m) => SongLine(
      lineIndex: m['line_index'] as int,
      startTimeMs: m['start_time_ms'] as int,
      rawLine: m['raw_line'] as String,
    )).toList();
  }

  Song _songFromMap(Map<String, dynamic> map, List<SongLine> lines) {
    List<Color>? colors;
    if (map['gradient_colors'] != null) {
      final colorValues = jsonDecode(map['gradient_colors'] as String) as List;
      colors = colorValues.map((v) => Color(v as int)).toList();
    }

    final rawArtist = (map['artist'] as String?)?.trim() ?? '';
    final resolvedArtist = (rawArtist.isEmpty ||
            rawArtist == 'Google Drive' ||
            rawArtist == 'Unknown Artist' ||
            rawArtist == 'Local Audio')
        ? 'Tidak Diketahui'
        : rawArtist;

    return Song(
      id: map['id'] as String,
      title: map['title'] as String,
      artist: resolvedArtist,
      albumArtUrl: map['album_art_url'] as String?,
      durationMs: map['duration_ms'] as int,
      originalKey: map['original_key'] as String?,
      gradientColors: colors,
      lines: lines,
      filePath: map['file_path'] as String?,
      streamUrl: map['stream_url'] as String?,
      bpm: (map['bpm'] as num?)?.toDouble() ?? 120.0,
      timeSignature: map['time_signature'] as String? ?? '4/4',
      startBeat: (map['start_beat'] as int?) ?? 1,
      startBeatOffsetMs: (map['start_beat_offset_ms'] as int?) ?? 0,
    );
  }

  // --- Playlist Operations ---
  Future<List<Playlist>> getAllPlaylists() async {
    final db = await database;
    final maps = await db.query('playlists', orderBy: 'created_at DESC');
    return maps.map((m) => Playlist.fromMap(m)).toList();
  }

  Future<void> insertPlaylist(Playlist playlist) async {
    final db = await database;
    await db.insert(
      'playlists',
      playlist.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updatePlaylist(Playlist playlist) async {
    final db = await database;
    await db.update(
      'playlists',
      playlist.toMap(),
      where: 'id = ?',
      whereArgs: [playlist.id],
    );
  }

  Future<void> deletePlaylist(String id) async {
    final db = await database;
    await db.delete(
      'playlists',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}

