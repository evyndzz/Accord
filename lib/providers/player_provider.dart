// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';

import '../models/piano_chord.dart';
import '../models/song.dart';
import '../services/audio_player_service.dart';
import '../services/google_drive_sync_service.dart';
import '../services/local_database.dart';
import '../utils/chord_parser.dart';
import '../utils/transposer.dart';

enum PlayerSource { local, cloudDrive }

class PlayerProvider extends ChangeNotifier {
  final AudioPlayerService _audioPlayerService;
  final LocalDatabase _localDb;
  final GoogleDriveSyncService? _driveSyncService;

  PlayerProvider({
    required AudioPlayerService audioPlayerService,
    required LocalDatabase localDb,
    GoogleDriveSyncService? driveSyncService,
  })  : _audioPlayerService = audioPlayerService,
        _localDb = localDb,
        _driveSyncService = driveSyncService {
    _subscribeToInAppAudio();
  }

  Song? _currentSong;
  bool _isPlaying = false;
  int _positionMs = 0;
  int _transposeOffset = 0;
  PlayerSource _source = PlayerSource.local;

  // Audio Loading / Buffering State
  final bool _isLoadingAudio = false;
  String? _loadingTrackId;
  String? _loadingStatusMessage;

  // Queue playlist
  List<Song> _playlist = [];
  int _currentIndex = 0;

  // Timer fallback for chord practice songs without physical audio file
  Timer? _timer;
  Timer? _seekDebounceTimer;

  // Subscriptions
  StreamSubscription? _audioPosSub;
  StreamSubscription? _audioDurSub;
  StreamSubscription? _audioPlayingSub;

  final List<Song> _playHistory = [];

  // ── Getters ────────────────────────────────────────────────────────────────

  Song? get currentSong => _currentSong;
  bool get isPlaying => _isPlaying;
  int get positionMs => _positionMs;
  int get transposeOffset => _transposeOffset;
  PlayerSource get source => _source;
  bool get isLoadingAudio => _isLoadingAudio;
  String? get loadingTrackId => _loadingTrackId;
  String? get loadingStatusMessage => _loadingStatusMessage;
  List<Song> get playlist => _playlist;
  List<Song> get playHistory => List.unmodifiable(_playHistory);
  int get currentIndex => _currentIndex;

  int get durationMs {
    if (_audioPlayerService.hasLoadedAudio && _audioPlayerService.duration.inMilliseconds > 0) {
      return _audioPlayerService.duration.inMilliseconds;
    }
    return _currentSong?.durationMs ?? 0;
  }

  double get progress {
    final dur = durationMs;
    if (dur <= 0) return 0.0;
    return (_positionMs / dur).clamp(0.0, 1.0);
  }

  int get activeLyricIndex {
    if (_currentSong == null || _currentSong!.lines.isEmpty) return -1;
    final lines = _currentSong!.lines;

    // Check if song has any valid timestamps > 0
    final timedLines = lines.where((l) => l.startTimeMs > 0).toList();
    if (timedLines.isEmpty) {
      return 0;
    }

    // If audio position is before the first timed line (e.g. Intro)
    if (_positionMs < timedLines.first.startTimeMs) {
      return -1;
    }

    // Find the latest line whose startTimeMs <= _positionMs
    int matchedIndex = -1;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].startTimeMs > 0 && _positionMs >= lines[i].startTimeMs) {
        matchedIndex = i;
      }
    }
    return matchedIndex;
  }

  /// Indeks baris chord terakhir yang sedang aktif berbunyi (tidak hilang saat baris lirik dimulai)
  int get activeChordLineIndex {
    if (_currentSong == null || _currentSong!.lines.isEmpty) return -1;
    final lines = _currentSong!.lines;

    int matched = -1;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].startTimeMs > 0 && _positionMs >= lines[i].startTimeMs) {
        final parsed = ChordParser.parse(lines[i].rawLine);
        if (parsed.chords.isNotEmpty) {
          matched = i;
        }
      }
    }

    // Jika belum ada baris chord ber-timestamp sebelum _positionMs, cari baris chord pertama
    if (matched == -1) {
      for (int i = 0; i < lines.length; i++) {
        final parsed = ChordParser.parse(lines[i].rawLine);
        if (parsed.chords.isNotEmpty) {
          if (lines[i].startTimeMs <= 0 || _positionMs >= lines[i].startTimeMs) {
            matched = i;
            break;
          }
        }
      }
    }
    return matched;
  }

  /// Indeks baris lirik vokal terakhir yang sedang dinyanyikan (tidak tergeser oleh baris chord)
  int get activeLyricLineIndex {
    if (_currentSong == null || _currentSong!.lines.isEmpty) return -1;
    final lines = _currentSong!.lines;

    int matched = -1;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].startTimeMs > 0 && _positionMs >= lines[i].startTimeMs) {
        final parsed = ChordParser.parse(lines[i].rawLine);
        final text = parsed.plainText.trim();
        // Hanya baris yang memiliki kata vokal (bukan hanya chord atau header bait kosong)
        if (text.isNotEmpty &&
            !RegExp(r'^(intro|verse|chorus|bridge|outro|interlude)\s*\d*$', caseSensitive: false).hasMatch(text)) {
          matched = i;
        }
      }
    }
    return matched;
  }

  /// Teks lirik vokal yang sedang dinyanyikan pada detik ini
  String get activeLyricText {
    final idx = activeLyricLineIndex;
    if (_currentSong == null || idx < 0 || idx >= _currentSong!.lines.length) {
      return '';
    }
    final line = _currentSong!.lines[idx];
    final parsed = ChordParser.parse(line.rawLine);
    return parsed.plainText.trim();
  }

  /// Indeks token chord mana di baris chord aktif yang sedang berbunyi saat ini
  int? get activeChordTokenIndex {
    final idx = activeChordLineIndex;
    if (_currentSong == null || idx < 0 || idx >= _currentSong!.lines.length) {
      return null;
    }
    final lines = _currentSong!.lines;
    final line = lines[idx];
    final transposed = TransposeEngine.transposeLine(line.rawLine, _transposeOffset);
    final parsed = ChordParser.parse(transposed);
    if (parsed.chords.isEmpty) return null;
    if (parsed.chords.length == 1) return 0;

    final tStart = line.startTimeMs;
    // Cari baris chord berikutnya untuk menghitung durasi birama chord ini
    int tEnd = tStart + 6000;
    for (int j = idx + 1; j < lines.length; j++) {
      if (lines[j].startTimeMs > tStart) {
        final nextParsed = ChordParser.parse(lines[j].rawLine);
        if (nextParsed.chords.isNotEmpty) {
          tEnd = lines[j].startTimeMs;
          break;
        }
      }
    }
    if (durationMs > tStart && tEnd > durationMs) {
      tEnd = durationMs;
    }
    if (tEnd <= tStart) {
      tEnd = tStart + 4000;
    }

    final duration = tEnd - tStart;
    final posInLine = (_positionMs - tStart).clamp(0, duration);

    // Kasus 1: Baris instrumen / chord saja tanpa teks lirik
    if (parsed.plainText.trim().isEmpty) {
      final slotWidth = duration / parsed.chords.length;
      final k = (posInLine / slotWidth).floor().clamp(0, parsed.chords.length - 1);
      return k;
    }

    // Kasus 2: Baris lirik dengan chord tertanam di kata tertentu
    final totalChars = parsed.plainText.length;
    if (totalChars <= 0) return 0;

    int activeK = 0;
    for (int k = 0; k < parsed.chords.length; k++) {
      final charIdx = parsed.chords[k].charIndex;
      final chordTimeOffset = (charIdx / totalChars) * duration;
      if (posInLine >= chordTimeOffset) {
        activeK = k;
      }
    }
    return activeK;
  }

  /// Chord spesifik yang sedang aktif berbunyi pada detik ini
  String get currentChord {
    final idx = activeChordLineIndex;
    if (_currentSong == null || idx < 0 || idx >= _currentSong!.lines.length) {
      return '';
    }
    final line = _currentSong!.lines[idx];
    final transposed = TransposeEngine.transposeLine(line.rawLine, _transposeOffset);
    final parsed = ChordParser.parse(transposed);
    if (parsed.chords.isEmpty) return '';

    final tokenIdx = activeChordTokenIndex;
    if (tokenIdx != null && tokenIdx >= 0 && tokenIdx < parsed.chords.length) {
      return parsed.chords[tokenIdx].chord;
    }
    return parsed.chords.first.chord;
  }

  /// Daftar chord baris aktif dengan chord yang sedang berbunyi di urutan paling awal
  List<String> get activeChords {
    final idx = activeChordLineIndex;
    if (_currentSong == null || idx < 0 || idx >= _currentSong!.lines.length) {
      return [];
    }
    final line = _currentSong!.lines[idx];
    final transposed = TransposeEngine.transposeLine(line.rawLine, _transposeOffset);
    final parsed = ChordParser.parse(transposed);
    if (parsed.chords.isEmpty) return [];

    final activeName = currentChord;
    final lineChords = parsed.chords.map((c) => c.chord).toSet();
    final result = <String>[];
    if (activeName.isNotEmpty && lineChords.contains(activeName)) {
      result.add(activeName);
      lineChords.remove(activeName);
    }
    result.addAll(lineChords);
    return result;
  }

  /// Urutan linimasa semua event chord dalam lagu secara berurutan
  List<TimedChordEvent> get chordTimeline {
    if (_currentSong == null || _currentSong!.lines.isEmpty) return const [];
    return ChordTimelineExtractor.extract(
      lines: _currentSong!.lines,
      transposeOffset: _transposeOffset,
      bpm: _currentSong!.effectiveBpm,
    );
  }

  /// Chord berikutnya yang akan datang dalam lagu (berbeda dari chord saat ini)
  String? get nextChord {
    final timeline = chordTimeline;
    if (timeline.isEmpty) return null;

    final curr = currentChord;

    // Jika audio berada sebelum event chord pertama
    if (timeline.isNotEmpty && _positionMs < timeline.first.startTimeMs) {
      if (curr.isEmpty) {
        return timeline.first.chord;
      }
    }

    for (final ev in timeline) {
      if (ev.startTimeMs > _positionMs) {
        if (curr.isEmpty || ev.chord != curr) {
          return ev.chord;
        }
      }
    }
    return null;
  }

  /// Chord langkah kedua setelah nextChord untuk antisipasi pemain
  String? get upcomingChord {
    final timeline = chordTimeline;
    if (timeline.isEmpty) return null;

    final next = nextChord;
    if (next == null) return null;

    bool foundNext = false;
    for (final ev in timeline) {
      if (ev.startTimeMs > _positionMs) {
        if (!foundNext) {
          if (ev.chord == next) {
            foundNext = true;
          }
        } else {
          if (ev.chord != next) {
            return ev.chord;
          }
        }
      }
    }
    return null;
  }

  String get positionFormatted => _formatTime(_positionMs);
  String get durationFormatted => _formatTime(durationMs);
  String get currentTimeFormatted => _formatTime(_positionMs);
  String get totalTimeFormatted => _formatTime(durationMs);

  // ── In-App Audio Subscription ──────────────────────────────────────────────

  void _subscribeToInAppAudio() {
    _audioPosSub = _audioPlayerService.positionStream.listen((pos) {
      if (_audioPlayerService.hasLoadedAudio) {
        _positionMs = pos.inMilliseconds;
        notifyListeners();
      }
    });

    _audioDurSub = _audioPlayerService.durationStream.listen((dur) async {
      if (dur != null && dur.inMilliseconds > 0 && _currentSong != null) {
        final newMs = dur.inMilliseconds;
        if (_currentSong!.durationMs != newMs) {
          _currentSong = _currentSong!.copyWith(durationMs: newMs);
          await _localDb.updateSongDuration(_currentSong!.id, newMs);
          notifyListeners();
        }
      }
    });

    _audioPlayingSub = _audioPlayerService.playingStream.listen((playing) {
      if (_audioPlayerService.hasLoadedAudio) {
        _isPlaying = playing;
        notifyListeners();
      }
    });
  }

  // ── Playback Controls ──────────────────────────────────────────────────────

  Future<void> playSong(Song song, {List<Song>? playlist, PlayerSource? source}) async {
    _stopTimer();
    _currentSong = song;
    _positionMs = 0;
    _source = source ?? (song.id.startsWith('drive_') ? PlayerSource.cloudDrive : PlayerSource.local);

    if (playlist != null) {
      _playlist = playlist;
      _currentIndex = playlist.indexWhere((s) => s.id == song.id);
      if (_currentIndex == -1) _currentIndex = 0;
    }

    _playHistory.removeWhere((s) => s.id == song.id);
    _playHistory.insert(0, song);
    if (_playHistory.length > 25) {
      _playHistory.removeLast();
    }

    notifyListeners();

    // Check cloud chords or local DB if empty
    if (_currentSong!.lines.isEmpty) {
      final dbSong = await _localDb.getSong(_currentSong!.id);
      if (dbSong != null && dbSong.lines.isNotEmpty) {
        _currentSong = dbSong;
        notifyListeners();
      } else {
        _checkAndFetchCloudChords(_currentSong!.id, title: _currentSong!.title);
      }
    }

    final hasAudioSource = (_currentSong!.filePath != null && _currentSong!.filePath!.isNotEmpty && File(_currentSong!.filePath!).existsSync()) ||
        (_currentSong!.streamUrl != null && _currentSong!.streamUrl!.isNotEmpty);

    if (hasAudioSource) {
      await _audioPlayerService.playSong(_currentSong!);
    } else {
      // Practice mode fallback timer
      _startTimer();
    }
  }

  Future<void> _checkAndFetchCloudChords(String trackId, {String? title}) async {
    final sync = _driveSyncService;
    if (sync != null && sync.isConfigured) {
      final cloudLines = await sync.fetchChordForTrack(trackId, title: title);
      if (cloudLines != null &&
          _currentSong != null &&
          _currentSong!.id == trackId) {
        final updated = await _localDb.getSong(trackId);
        if (updated != null) {
          _currentSong = updated;
          notifyListeners();
        }
      }
    }
  }

  Future<void> togglePlayPause() async {
    if (_currentSong == null) return;

    final hasAudioSource = (_currentSong!.filePath != null && _currentSong!.filePath!.isNotEmpty) ||
        (_currentSong!.streamUrl != null && _currentSong!.streamUrl!.isNotEmpty);

    if (hasAudioSource) {
      _isPlaying = !_isPlaying;
      notifyListeners();

      await _audioPlayerService.togglePlay();
      _isPlaying = _audioPlayerService.isPlaying;
      notifyListeners();
      return;
    }

    // Timer fallback
    _isPlaying = !_isPlaying;
    if (_isPlaying) {
      _startTimer();
    } else {
      _stopTimer();
    }
    notifyListeners();
  }

  Future<void> pause() async {
    _stopTimer();
    _isPlaying = false;
    await _audioPlayerService.pause();
    if (hasListeners) {
      notifyListeners();
    }
  }

  Future<void> seek(double prog) async {
    final targetMs = (prog * durationMs).round().clamp(0, durationMs);
    _positionMs = targetMs;
    notifyListeners(); // 0ms instant UI slider update

    _seekDebounceTimer?.cancel();
    _seekDebounceTimer = Timer(const Duration(milliseconds: 50), () async {
      final hasAudioSource = (_currentSong?.filePath != null && _currentSong!.filePath!.isNotEmpty) ||
          (_currentSong?.streamUrl != null && _currentSong!.streamUrl!.isNotEmpty);

      if (hasAudioSource) {
        await _audioPlayerService.seek(Duration(milliseconds: targetMs));
      }
    });
  }

  Future<void> seekToMs(int targetMs) async {
    final dur = durationMs;
    if (dur <= 0) {
      _positionMs = targetMs;
      notifyListeners();
      return;
    }
    final prog = (targetMs / dur).clamp(0.0, 1.0);
    await seek(prog);
  }

  void transposeUp() {
    _transposeOffset = (_transposeOffset + 1).clamp(-11, 11);
    notifyListeners();
  }

  void transposeDown() {
    _transposeOffset = (_transposeOffset - 1).clamp(-11, 11);
    notifyListeners();
  }

  void resetTranspose() {
    if (_transposeOffset != 0) {
      _transposeOffset = 0;
      notifyListeners();
    }
  }

  void updateCurrentSong(Song song) {
    if (_currentSong != null && _currentSong!.id == song.id) {
      _currentSong = song;
      notifyListeners();
    }
  }

  Future<void> updateSongBeatSettings({
    double? bpm,
    String? timeSignature,
    int? startBeat,
    int? startBeatOffsetMs,
  }) async {
    if (_currentSong == null) return;
    final updated = _currentSong!.copyWith(
      bpm: bpm ?? _currentSong!.bpm,
      timeSignature: timeSignature ?? _currentSong!.timeSignature,
      startBeat: startBeat ?? _currentSong!.startBeat,
      startBeatOffsetMs: startBeatOffsetMs ?? _currentSong!.startBeatOffsetMs,
    );
    _currentSong = updated;
    notifyListeners();

    await _localDb.updateSongBeatSettings(
      updated.id,
      bpm: updated.effectiveBpm,
      timeSignature: updated.effectiveTimeSignature,
      startBeat: updated.effectiveStartBeat,
      startBeatOffsetMs: updated.effectiveStartBeatOffsetMs,
    );
    final driveSync = _driveSyncService;
    if (driveSync != null && driveSync.isConfigured) {
      unawaited(driveSync.saveChordToCloud(updated));
    }
  }

  Future<void> updateSongTempo(double bpm, String timeSignature) async {
    await updateSongBeatSettings(bpm: bpm, timeSignature: timeSignature);
  }

  Future<void> nextSong() async {
    if (_playlist.isNotEmpty) {
      _currentIndex = (_currentIndex + 1) % _playlist.length;
      await playSong(_playlist[_currentIndex]);
    }
  }

  Future<void> previousSong() async {
    if (_positionMs > 3000) {
      await seek(0.0);
      return;
    }

    if (_playlist.isNotEmpty) {
      _currentIndex = (_currentIndex - 1 + _playlist.length) % _playlist.length;
      await playSong(_playlist[_currentIndex]);
    }
  }

  // ── Timer (Fallback for chord practice without audio) ─────────────────────

  void _startTimer() {
    _stopTimer();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _positionMs += 100;
      if (_positionMs >= durationMs && durationMs > 0) {
        _positionMs = durationMs;
        _isPlaying = false;
        _stopTimer();
      }
      notifyListeners();
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  String _formatTime(int ms) {
    final m = ms ~/ 60000;
    final s = (ms % 60000) ~/ 1000;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _stopTimer();
    _seekDebounceTimer?.cancel();
    _audioPosSub?.cancel();
    _audioDurSub?.cancel();
    _audioPlayingSub?.cancel();
    super.dispose();
  }
}
