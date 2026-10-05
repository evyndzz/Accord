import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/playlist.dart';
import '../models/song.dart';
import '../services/local_database.dart';

class LibraryProvider extends ChangeNotifier {
  static const String _prefKeySeededPlaylists = 'has_seeded_default_playlists';

  final LocalDatabase _localDb;

  LibraryProvider({required this._localDb}) {
    _loadLocalSongs();
    _loadPlaylists();
  }

  final Set<String> _favorites = {};
  String _searchQuery = '';
  List<Song> _localSongs = [];
  List<Song> _localDeviceSongs = [];
  List<Playlist> _playlists = [];
  bool _isLoadingLocal = false;

  List<Song> get mockSongList => const [];
  List<Song> get localSongs => _localSongs;
  List<Song> get localDeviceSongs => _localDeviceSongs;
  List<Song> get allSongs => _localSongs;
  List<Playlist> get playlists => _playlists;
  Set<String> get favorites => _favorites;
  bool get isLoadingLocal => _isLoadingLocal;

  List<Song> get favoriteSongs =>
      allSongs.where((s) => _favorites.contains(s.id)).toList();

  List<Song> get searchResults {
    if (_searchQuery.isEmpty) return allSongs;
    final q = _searchQuery.toLowerCase();
    return allSongs.where(
      (s) =>
          s.title.toLowerCase().contains(q) ||
          s.artist.toLowerCase().contains(q),
    ).toList();
  }

  bool isFavorite(String songId) => _favorites.contains(songId);

  void toggleFavorite(String songId) {
    if (_favorites.contains(songId)) {
      _favorites.remove(songId);
    } else {
      _favorites.add(songId);
    }
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void clearSearch() {
    _searchQuery = '';
    notifyListeners();
  }

  // ── Local Songs ─────────────────────────────────────────────────────────

  Future<void> _loadLocalSongs() async {
    _isLoadingLocal = true;
    notifyListeners();
    _localSongs = await _localDb.getAllSongs();
    _localDeviceSongs = await _localDb.getLocalDeviceSongs();
    _isLoadingLocal = false;
    notifyListeners();
  }

  void updateSongDurationInMemory(String songId, int durationMs) {
    bool changed = false;
    final idx = _localSongs.indexWhere((s) => s.id == songId);
    if (idx != -1) {
      _localSongs[idx] = _localSongs[idx].copyWith(durationMs: durationMs);
      changed = true;
    }
    final idxDev = _localDeviceSongs.indexWhere((s) => s.id == songId);
    if (idxDev != -1) {
      _localDeviceSongs[idxDev] = _localDeviceSongs[idxDev].copyWith(durationMs: durationMs);
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// Import audio files from phone storage via native file picker
  Future<int> importAudioFilesFromPicker() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.audio,
      );

      if (result.isEmpty) {
        return 0;
      }

      final validPaths = result
          .map((f) => f.path)
          .where((p) => p != null && p.isNotEmpty)
          .cast<String>()
          .toList();

      if (validPaths.isEmpty) return 0;

      final imported = await _localDb.importAudioFiles(validPaths);
      await _loadLocalSongs();
      return imported.length;
    } catch (e) {
      debugPrint('Error picking audio files: $e');
      return 0;
    }
  }

  Future<void> saveLocalSong(Song song) async {
    await _localDb.insertSong(song);
    await _loadLocalSongs();
  }

  Future<void> updateSongTempo(String id, double bpm, String timeSignature) async {
    await _localDb.updateSongTempo(id, bpm, timeSignature);
    await _loadLocalSongs();
  }

  Future<void> deleteLocalSong(String id) async {
    await _localDb.deleteSong(id);
    _favorites.remove(id);
    await _loadLocalSongs();
  }

  Future<void> refreshLocalSongs() => _loadLocalSongs();

  // ── Playlists ────────────────────────────────────────────────────────────

  Future<void> _loadPlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeeded = prefs.getBool(_prefKeySeededPlaylists) ?? false;
    _playlists = await _localDb.getAllPlaylists();

    if (_playlists.isNotEmpty && !hasSeeded) {
      // Mark as already seeded so we never re-seed if the user deletes them all
      await prefs.setBool(_prefKeySeededPlaylists, true);
    } else if (!hasSeeded && _playlists.isEmpty) {
      // First run on a fresh install: seed once
      await prefs.setBool(_prefKeySeededPlaylists, true);
      final defaultPlaylists = [
        Playlist(
          id: 'pl_cosmic_vibes',
          name: 'Cosmic Vibes',
          songIds: const [],
          createdAt: DateTime.now(),
        ),
        Playlist(
          id: 'pl_nebula_acoustic',
          name: 'Nebula Acoustic',
          songIds: const [],
          createdAt: DateTime.now(),
        ),
      ];
      for (final pl in defaultPlaylists) {
        await _localDb.insertPlaylist(pl);
      }
      _playlists = await _localDb.getAllPlaylists();
    }
    notifyListeners();
  }

  Future<Playlist> createPlaylist(String name, {String logoId = 'saturn_orbit'}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeySeededPlaylists, true);
    final playlist = Playlist(
      id: 'pl_${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim().isEmpty ? 'My Playlist' : name.trim(),
      songIds: const [],
      createdAt: DateTime.now(),
      logoId: logoId,
    );
    await _localDb.insertPlaylist(playlist);
    _playlists = await _localDb.getAllPlaylists();
    notifyListeners();
    return playlist;
  }

  Future<void> updatePlaylistLogo(String playlistId, String logoId) async {
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx == -1) return;
    final pl = _playlists[idx];
    final updated = pl.copyWith(logoId: logoId);
    await _localDb.updatePlaylist(updated);
    _playlists = await _localDb.getAllPlaylists();
    notifyListeners();
  }

  Future<void> deletePlaylist(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeySeededPlaylists, true);
    await _localDb.deletePlaylist(id);
    _playlists = await _localDb.getAllPlaylists();
    notifyListeners();
  }

  Future<void> addSongToPlaylist(String playlistId, String songId) async {
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx == -1) return;
    final pl = _playlists[idx];
    if (pl.songIds.contains(songId)) return;
    final updated = pl.copyWith(songIds: [...pl.songIds, songId]);
    await _localDb.updatePlaylist(updated);
    await _loadPlaylists();
  }

  Future<void> removeSongFromPlaylist(String playlistId, String songId) async {
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx == -1) return;
    final pl = _playlists[idx];
    final updated = pl.copyWith(
      songIds: pl.songIds.where((id) => id != songId).toList(),
    );
    await _localDb.updatePlaylist(updated);
    await _loadPlaylists();
  }

  List<Song> getSongsForPlaylist(Playlist playlist) {
    final songMap = {for (var s in _localSongs) s.id: s};
    return playlist.songIds
        .map((id) => songMap[id])
        .whereType<Song>()
        .toList();
  }

  Future<void> refreshPlaylists() => _loadPlaylists();
}

