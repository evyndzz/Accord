import 'dart:io';
import 'dart:math' as math;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../models/piano_chord.dart';
import '../models/song.dart';
import '../models/song_line.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../services/accidental_preference.dart';
import '../services/google_drive_audio_service.dart';
import '../services/google_drive_sync_service.dart';
import '../utils/ambiance_color_helper.dart';
import '../utils/chord_parser.dart';
import '../utils/chordify_midi_parser.dart';
import '../widgets/apple_music_aura_background.dart';
import '../widgets/chordify_beat_grid.dart';
import '../widgets/piano_chord_diagram.dart';

enum SyncSubMode { chords, lyrics }

class _SyncChordItem {
  String chord;
  int startTimeMs;

  _SyncChordItem({
    required this.chord,
    this.startTimeMs = 0,
  });
}

class _SyncLyricItem {
  String text;
  int startTimeMs;

  _SyncLyricItem({
    required this.text,
    this.startTimeMs = 0,
  });
}

class SongEditorScreen extends StatefulWidget {
  final Song? existingSong;

  const SongEditorScreen({
    super.key,
    this.existingSong,
  });

  @override
  State<SongEditorScreen> createState() => _SongEditorScreenState();
}

class _SongEditorScreenState extends State<SongEditorScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const List<Shadow> _textShadows = [
    Shadow(color: Color(0xD9000000), blurRadius: 6, offset: Offset(0, 1)),
  ];

  final _titleController = TextEditingController();
  final _artistController = TextEditingController();
  final _keyController = TextEditingController();
  final _driveLinkController = TextEditingController();
  final _chordsTextController = TextEditingController();
  final _lyricsTextController = TextEditingController();

  // Cover / Picture Profile
  String? _coverImagePath;
  String? _coverImageUrl;

  // Audio File
  String? _audioFilePath;
  String? _audioFileName;
  int? _audioFileSize;
  String? _existingStreamUrl;

  // Separated Sync Items
  final List<_SyncChordItem> _syncChords = [];
  final List<_SyncLyricItem> _syncLyrics = [];

  SyncSubMode _syncSubMode = SyncSubMode.chords;

  // Tempo & Meter
  double _bpm = 120.0;
  late final TextEditingController _bpmController;
  String _timeSignature = '4/4';
  int _startBeat = 1;
  int _startBeatOffsetMs = 0;

  // Chord Sync State
  bool _isSyncingChords = false;
  int _syncingChordIndex = -1;
  int? _hoveredChordIndex;
  int? _selectedChordIndex;

  // Lyric Sync State
  bool _isSyncingLyrics = false;
  int _syncingLyricIndex = -1;

  bool _isSaving = false;
  String? _saveStatusMessage;

  final List<String> _quickChords = const [
    'C', 'G', 'Am', 'F', 'Em', 'D', 'Dm', 'A', 'E', 'Bm', 'Bb', 'Bbm', 'A/C#', 'F#m', 'C#m', 'Eb'
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    if (widget.existingSong != null) {
      final s = widget.existingSong!;
      _titleController.text = s.title;
      _artistController.text = (s.artist != 'Google Drive' &&
              s.artist != 'Tidak Diketahui' &&
              s.artist != 'Unknown Artist' &&
              s.artist != 'Local Audio')
          ? s.artist
          : '';
      _keyController.text = s.originalKey ?? 'C';
      _bpm = s.effectiveBpm;
      _bpmController = TextEditingController(text: '${_bpm.round()}');
      _timeSignature = s.effectiveTimeSignature;
      _startBeat = s.effectiveStartBeat;
      _startBeatOffsetMs = s.effectiveStartBeatOffsetMs;
      _coverImageUrl = s.albumArtUrl;
      _audioFilePath = s.filePath;
      _existingStreamUrl = s.streamUrl;
      if (s.streamUrl != null && s.streamUrl!.contains('id=')) {
        _driveLinkController.text = s.streamUrl!;
      }

      final chordsBuf = StringBuffer();
      final lyricsBuf = StringBuffer();

      for (final line in s.lines) {
        final parsed = ChordParser.parse(line.rawLine);
        if (parsed.chords.isNotEmpty) {
          for (final c in parsed.chords) {
            chordsBuf.write('${c.chord} ');
            _syncChords.add(_SyncChordItem(
              chord: c.chord,
              startTimeMs: line.startTimeMs,
            ));
          }
          chordsBuf.writeln();
        }
        if (parsed.plainText.trim().isNotEmpty) {
          final txt = parsed.plainText.trim();
          final isHeader = RegExp(r'^(intro|verse|chorus|bridge|outro|interlude)\s*\d*$', caseSensitive: false).hasMatch(txt);
          if (!isHeader) {
            lyricsBuf.writeln(txt);
            _syncLyrics.add(_SyncLyricItem(
              text: txt,
              startTimeMs: line.startTimeMs,
            ));
          }
        }
      }
      _chordsTextController.text = chordsBuf.toString().trim();
      _lyricsTextController.text = lyricsBuf.toString().trim();
    } else {
      _keyController.text = 'C';
      _bpmController = TextEditingController(text: '${_bpm.round()}');
      _chordsTextController.text = '';
      _lyricsTextController.text = '';
      _refreshFromTextControllers(preserveTimestamps: false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _titleController.dispose();
    _artistController.dispose();
    _keyController.dispose();
    _driveLinkController.dispose();
    _chordsTextController.dispose();
    _lyricsTextController.dispose();
    _bpmController.dispose();
    super.dispose();
  }

  // ── Cover Photo Picker ───────────────────────────────────────────────────

  Future<void> _pickCoverFromGallery() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
      );
      if (result.isNotEmpty && result.first.path != null) {
        setState(() {
          _coverImagePath = result.first.path;
          _coverImageUrl = null;
        });
      }
    } catch (e) {
      _showToast('Gagal memilih gambar: $e', isError: true);
    }
  }

  void _showCoverUrlDialog() {
    final urlCtrl = TextEditingController(text: _coverImageUrl);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141522),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
        title: const Text('Masukkan URL Gambar Cover', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: urlCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'https://images.unsplash.com/... atau https://...',
            hintStyle: const TextStyle(color: Colors.white30),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.06),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFD9F99D))),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () {
              final val = urlCtrl.text.trim();
              if (val.isNotEmpty) {
                setState(() {
                  _coverImageUrl = val;
                  _coverImagePath = null;
                });
              }
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD9F99D),
              foregroundColor: const Color(0xFF09090B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Gunakan URL', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ── Audio File Picker ────────────────────────────────────────────────────

  Future<void> _pickAudioFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.audio,
      );
      if (result.isNotEmpty && result.first.path != null) {
        final f = File(result.first.path!);
        final size = await f.length();
        setState(() {
          _audioFilePath = result.first.path;
          _audioFileName = result.first.name;
          _audioFileSize = size;
        });
        _showToast('File audio berhasil dipilih: ${result.first.name}');
      }
    } catch (e) {
      _showToast('Gagal memilih file audio: $e', isError: true);
    }
  }

  // ── Chord & Lyric Extraction from Controllers ─────────────────────────────

  void _insertChord(String chord) {
    final current = _chordsTextController.text;
    final separator = (current.isNotEmpty && !current.endsWith(' ') && !current.endsWith('\n')) ? ' ' : '';
    setState(() {
      _chordsTextController.text = '$current$separator$chord ';
      _chordsTextController.selection = TextSelection.fromPosition(
        TextPosition(offset: _chordsTextController.text.length),
      );
    });
    _refreshFromTextControllers(preserveTimestamps: true);
  }

  void _refreshFromTextControllers({bool preserveTimestamps = true}) {
    // 1. Ekstrak token chord
    final chordRaw = _chordsTextController.text;
    final chordTokens = <String>[];
    final regex = RegExp(r'\[([^\]]+)]|([A-Ga-g][#b♭♯]?(?:m|maj|min|dim|aug|sus|dom)?\d*(?:/[A-Ga-g][#b♭♯]?)?)');
    for (final m in regex.allMatches(chordRaw)) {
      final val = (m.group(1) ?? m.group(2) ?? '').trim();
      if (val.isNotEmpty && val.toLowerCase() != 'intro' && val.toLowerCase() != 'verse') {
        chordTokens.add(val);
      }
    }
    if (chordTokens.isEmpty && chordRaw.trim().isNotEmpty) {
      for (final part in chordRaw.replaceAll('[', ' ').replaceAll(']', ' ').split(RegExp(r'\s+'))) {
        final p = part.trim();
        if (p.isNotEmpty) chordTokens.add(p);
      }
    }

    // 2. Ekstrak lirik
    final lyricLines = _lyricsTextController.text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    setState(() {
      final oldChordTimes = <int, int>{};
      if (preserveTimestamps) {
        for (int i = 0; i < _syncChords.length; i++) {
          oldChordTimes[i] = _syncChords[i].startTimeMs;
        }
      }

      _syncChords.clear();
      for (int i = 0; i < chordTokens.length; i++) {
        final c = chordTokens[i];
        int t = 0;
        if (preserveTimestamps && oldChordTimes.containsKey(i)) {
          t = oldChordTimes[i]!;
        }
        _syncChords.add(_SyncChordItem(chord: c, startTimeMs: t));
      }

      final oldLyricTimes = <int, int>{};
      if (preserveTimestamps) {
        for (int i = 0; i < _syncLyrics.length; i++) {
          oldLyricTimes[i] = _syncLyrics[i].startTimeMs;
        }
      }

      _syncLyrics.clear();
      for (int i = 0; i < lyricLines.length; i++) {
        final l = lyricLines[i];
        int t = 0;
        if (preserveTimestamps && oldLyricTimes.containsKey(i)) {
          t = oldLyricTimes[i]!;
        }
        _syncLyrics.add(_SyncLyricItem(text: l, startTimeMs: t));
      }
    });
  }

  // ── Build Final SongLines for Storage ─────────────────────────────────────

  List<SongLine> _buildSongLines() {
    final result = <SongLine>[];
    int lineIdx = 0;

    // Masukkan setiap akord satu per satu dengan timestamp masing-masing
    for (final c in _syncChords) {
      if (c.chord.trim().isNotEmpty) {
        result.add(SongLine(
          lineIndex: lineIdx++,
          startTimeMs: c.startTimeMs,
          rawLine: '[${c.chord.trim()}]',
        ));
      }
    }

    // Masukkan bait lirik vokal bersih dengan timestamp masing-masing
    for (final l in _syncLyrics) {
      if (l.text.trim().isNotEmpty) {
        result.add(SongLine(
          lineIndex: lineIdx++,
          startTimeMs: l.startTimeMs,
          rawLine: l.text.trim(),
        ));
      }
    }

    // Urutkan secara kronologis
    result.sort((a, b) {
      if (a.startTimeMs == 0 && b.startTimeMs == 0) return 0;
      if (a.startTimeMs == 0) return 1;
      if (b.startTimeMs == 0) return -1;
      return a.startTimeMs.compareTo(b.startTimeMs);
    });

    return result.asMap().entries.map((e) => SongLine(
      lineIndex: e.key,
      startTimeMs: e.value.startTimeMs,
      rawLine: e.value.rawLine,
    )).toList();
  }

  // ── Audio Player Helper ──────────────────────────────────────────────────

  Future<void> _playDraftAudio(PlayerProvider player) async {
    final title = _titleController.text.trim().isNotEmpty ? _titleController.text.trim() : 'Lagu Pratinjau';
    final artist = _artistController.text.trim().isNotEmpty ? _artistController.text.trim() : 'Accord Music';

    final filePath = _audioFilePath;
    String? streamUrl = _existingStreamUrl;
    final driveLink = _driveLinkController.text.trim();
    if (driveLink.isNotEmpty) {
      final fileId = GoogleDriveAudioService.extractFileId(driveLink);
      if (fileId != null) {
        streamUrl = 'https://drive.usercontent.google.com/download?id=$fileId&export=download';
      }
    }

    if ((filePath == null || filePath.isEmpty) && (streamUrl == null || streamUrl.isEmpty)) {
      _showToast('Pilih file audio atau tempel link Google Drive di Tab Info & Lirik terlebih dahulu!', isError: true);
      return;
    }

    final draftSong = Song(
      id: widget.existingSong?.id ?? 'draft_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      artist: artist,
      albumArtUrl: _coverImageUrl,
      durationMs: widget.existingSong?.durationMs ?? 0,
      lines: _buildSongLines(),
      filePath: filePath,
      streamUrl: streamUrl,
      bpm: _bpm,
      timeSignature: _timeSignature,
      startBeat: _startBeat,
      startBeatOffsetMs: _startBeatOffsetMs,
    );

    await player.playSong(draftSong);
  }

  // ── Chord Sync (Satu per Satu) ───────────────────────────────────────────

  void _startSyncingChords() {
    if (_syncChords.isEmpty) _refreshFromTextControllers(preserveTimestamps: true);
    if (_syncChords.isEmpty) {
      _showToast('Belum ada chord yang dimasukkan di Tab Info & Lirik.', isError: true);
      return;
    }
    final player = context.read<PlayerProvider>();
    if (!player.isPlaying) {
      _playDraftAudio(player);
    }
    setState(() {
      _isSyncingChords = true;
      _syncingChordIndex = 0;
    });
  }

  void _tapSyncChord() {
    if (!_isSyncingChords || _syncingChordIndex < 0 || _syncingChordIndex >= _syncChords.length) return;
    final player = context.read<PlayerProvider>();
    setState(() {
      _syncChords[_syncingChordIndex].startTimeMs = player.positionMs;
      _syncingChordIndex++;
      if (_syncingChordIndex >= _syncChords.length) {
        _isSyncingChords = false;
        _showToast('Semua chord telah disinkronkan satu per satu!');
      }
    });
  }

  void _undoSyncChord() {
    if (_syncingChordIndex <= 0 || _syncChords.isEmpty) return;
    final player = context.read<PlayerProvider>();
    setState(() {
      _syncingChordIndex--;
      _syncChords[_syncingChordIndex].startTimeMs = 0;
      final targetMs = math.max(0, player.positionMs - 3000);
      player.seekToMs(targetMs);
    });
  }

  void _stopSyncingChords() {
    setState(() {
      _isSyncingChords = false;
      _syncingChordIndex = -1;
    });
  }

  // ── Import File Chordify MIDI (.mid) ────────────────────────────────────

  Future<void> _importChordifyMidi() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mid', 'midi'],
      );
      if (result.isNotEmpty && result.first.path != null) {
        final file = File(result.first.path!);
        final midiData = await ChordifyMidiParser.parseFile(file);

        setState(() {
          if (_titleController.text.trim().isEmpty || _titleController.text.trim() == 'Lagu Pratinjau') {
            _titleController.text = midiData.title;
          }
          _bpm = midiData.bpm;
          _bpmController.text = '${_bpm.round()}';
          _timeSignature = midiData.timeSignature;
          _startBeatOffsetMs = midiData.startBeatOffsetMs;

          _syncChords.clear();
          for (final item in midiData.chords) {
            _syncChords.add(_SyncChordItem(
              chord: item.chord,
              startTimeMs: item.startTimeMs,
            ));
          }

          // Sinkronkan teks akord di tab 1
          _chordsTextController.text = _syncChords.map((c) => c.chord).join(' ');

          // Jika lirik hanya berisi placeholder dummy lama, bersihkan agar tidak tersimpan secara salah
          if (_lyricsTextController.text.contains('Ku tatap mentari')) {
            _lyricsTextController.text = '';
            _syncLyrics.clear();
          }
        });

        _showToast('Berhasil mengimpor ${midiData.chords.length} akord dari Chordify (${midiData.bpm.round()} BPM, ${midiData.timeSignature})!');
      }
    } catch (e) {
      _showToast('Gagal mengimpor file MIDI: $e', isError: true);
    }
  }

  // ── Editor Akord Individual (Per-Satuan Kunci) ──────────────────────────

  void _showEditChordDialog(int index) {
    if (index < 0 || index >= _syncChords.length) return;
    final item = _syncChords[index];
    final chordController = TextEditingController(text: item.chord);
    final secVal = (item.startTimeMs / 1000.0);
    final secondsController = TextEditingController(
      text: secVal > 0 ? (secVal == secVal.roundToDouble() ? '${secVal.round()}' : secVal.toStringAsFixed(2)) : '0',
    );
    final player = context.read<PlayerProvider>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161826),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            void updateSecondsFromMs(int ms) {
              final s = math.max(0, ms) / 1000.0;
              setSheetState(() {
                secondsController.text = (s == s.roundToDouble()) ? '${s.round()}' : s.toStringAsFixed(2);
              });
            }

            int getParsedMs() {
              final parsed = double.tryParse(secondsController.text.trim().replaceAll(',', '.'));
              if (parsed != null && parsed >= 0) {
                return (parsed * 1000).round();
              }
              return item.startTimeMs;
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Edit Akord #${index + 1}',
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white60),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // 1. Nama Akord
                    const Text('Nama Kunci / Akord:', style: TextStyle(color: Color(0xFFD9F99D), fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: chordController,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF222434),
                        hintText: 'Misal: F, G, Dm7, F/A...',
                        hintStyle: const TextStyle(color: Colors.white30),
                        prefixIcon: const Icon(Icons.music_note_rounded, color: Color(0xFFD9F99D), size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Quick Chords Chips
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: ['C', 'G', 'Am', 'F', 'Em', 'D', 'Dm', 'Bb', 'Bbm', 'F/A', 'Gm7', 'C#', 'Eb'].map((c) {
                        return InkWell(
                          onTap: () {
                            setSheetState(() => chordController.text = c);
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: chordController.text.trim() == c
                                  ? const Color(0xFFD9F99D).withValues(alpha: 0.25)
                                  : Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: chordController.text.trim() == c ? const Color(0xFFD9F99D) : Colors.white12,
                              ),
                            ),
                            child: Text(c, style: TextStyle(color: chordController.text.trim() == c ? const Color(0xFFD9F99D) : Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    // 2. Waktu Tayang (Timestamp dalam Detik)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Waktu Ditampilkan (Detik):', style: TextStyle(color: Color(0xFFD9F99D), fontSize: 12, fontWeight: FontWeight.bold)),
                        Text(
                          _formatMs(getParsedMs()),
                          style: const TextStyle(color: Color(0xFFD9F99D), fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: secondsController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: const Color(0xFF222434),
                              hintText: 'Misal: 23 atau 23.5',
                              hintStyle: const TextStyle(color: Colors.white30),
                              suffixText: 'detik',
                              suffixStyle: const TextStyle(color: Color(0xFFD9F99D), fontSize: 13, fontWeight: FontWeight.bold),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            ),
                            onChanged: (val) => setSheetState(() {}),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          onPressed: () {
                            final curMs = getParsedMs();
                            if (curMs > 0) {
                              player.seekToMs(curMs);
                              if (!player.isPlaying) player.togglePlayPause();
                            }
                          },
                          icon: const Icon(Icons.play_arrow_rounded, color: Color(0xFF38BDF8), size: 24),
                          style: IconButton.styleFrom(backgroundColor: const Color(0xFF222434)),
                          tooltip: 'Dengarkan Posisi Ini',
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Stepper Detik Cepat
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          OutlinedButton(
                            onPressed: () => updateSecondsFromMs(getParsedMs() - 1000),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              foregroundColor: Colors.white70,
                              side: const BorderSide(color: Colors.white24),
                            ),
                            child: const Text('-1s', style: TextStyle(fontSize: 12)),
                          ),
                          const SizedBox(width: 6),
                          OutlinedButton(
                            onPressed: () => updateSecondsFromMs(getParsedMs() - 100),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              foregroundColor: Colors.white70,
                              side: const BorderSide(color: Colors.white24),
                            ),
                            child: const Text('-0.1s', style: TextStyle(fontSize: 12)),
                          ),
                          const SizedBox(width: 6),
                          OutlinedButton(
                            onPressed: () => updateSecondsFromMs(getParsedMs() + 100),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              foregroundColor: Colors.white70,
                              side: const BorderSide(color: Colors.white24),
                            ),
                            child: const Text('+0.1s', style: TextStyle(fontSize: 12)),
                          ),
                          const SizedBox(width: 6),
                          OutlinedButton(
                            onPressed: () => updateSecondsFromMs(getParsedMs() + 1000),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              foregroundColor: Colors.white70,
                              side: const BorderSide(color: Colors.white24),
                            ),
                            child: const Text('+1s', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Tombol Gunakan Posisi Lagu Sekarang
                    OutlinedButton.icon(
                      onPressed: () => updateSecondsFromMs(player.positionMs),
                      icon: const Icon(Icons.timer_outlined, size: 16),
                      label: Text('Gunakan Posisi Lagu Sekarang (${player.currentTimeFormatted})'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFD9F99D),
                        side: BorderSide(color: const Color(0xFFD9F99D).withValues(alpha: 0.6)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Opsi Sisip & Hapus
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _showAddChordDialog(player, defaultMs: getParsedMs() + 2000, insertIndex: index + 1);
                            },
                            icon: const Icon(Icons.add_rounded, size: 16),
                            label: const Text('Sisip Akord Sesudah', style: TextStyle(fontSize: 11)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                              side: const BorderSide(color: Colors.white24),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _deleteChordAt(index);
                          },
                          icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                          label: const Text('Hapus', style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Tombol Simpan Utama
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          final newChord = chordController.text.trim();
                          if (newChord.isEmpty) {
                            _showToast('Nama kunci tidak boleh kosong!', isError: true);
                            return;
                          }
                          final newMs = getParsedMs();
                          setState(() {
                            _syncChords[index].chord = newChord;
                            _syncChords[index].startTimeMs = newMs;
                            _syncChords.sort((a, b) {
                              if (a.startTimeMs == 0 && b.startTimeMs == 0) return 0;
                              if (a.startTimeMs == 0) return 1;
                              if (b.startTimeMs == 0) return -1;
                              return a.startTimeMs.compareTo(b.startTimeMs);
                            });
                            _chordsTextController.text = _syncChords.map((c) => c.chord).join(' ');
                          });
                          Navigator.pop(ctx);
                          _showToast('Akord [$newChord] berhasil diperbarui (${_formatMs(newMs)})!');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD9F99D),
                          foregroundColor: const Color(0xFF09090B),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('SIMPAN PERUBAHAN', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── Dialog Tambah Akord Interaktif (Pilih Kunci & Posisi Waktu) ──────────

  void _showAddChordDialog(PlayerProvider player, {int? defaultMs, int? insertIndex}) {
    final initialMs = defaultMs ?? math.max(0, player.positionMs);
    final secVal = (initialMs / 1000.0);
    final secondsController = TextEditingController(
      text: secVal > 0 ? (secVal == secVal.roundToDouble() ? '${secVal.round()}' : secVal.toStringAsFixed(2)) : '0',
    );
    final chordController = TextEditingController(text: 'C');

    String selectedRoot = 'C';
    String selectedAccidental = ''; // '', '#', 'b'
    String selectedQuality = ''; // '', 'm', '7', 'maj7', 'm7', 'm7b5', '9', 'maj9', 'm9', 'add9', '11', '13', 'sus4', 'sus2', 'dim', 'aug', '7sus4'
    String selectedBass = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161826),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final accidentalPref = AccidentalPreferenceService.of(context, listen: false);

            void updateChordText() {
              final root = '$selectedRoot$selectedAccidental';
              final full = '$root$selectedQuality${selectedBass.isNotEmpty ? '/$selectedBass' : ''}';
              chordController.text = accidentalPref.formatChord(full);
            }

            void updateSecondsFromMs(int ms) {
              final s = math.max(0, ms) / 1000.0;
              setSheetState(() {
                secondsController.text = (s == s.roundToDouble()) ? '${s.round()}' : s.toStringAsFixed(2);
              });
            }

            int getParsedMs() {
              final parsed = double.tryParse(secondsController.text.trim().replaceAll(',', '.'));
              if (parsed != null && parsed >= 0) {
                return (parsed * 1000).round();
              }
              return initialMs;
            }

            final roots = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];
            final qualities = [
              {'label': 'Mayor', 'val': ''},
              {'label': 'Minor (m)', 'val': 'm'},
              {'label': '7', 'val': '7'},
              {'label': 'maj7', 'val': 'maj7'},
              {'label': 'm7', 'val': 'm7'},
              {'label': 'm7b5 (ø)', 'val': 'm7b5'},
              {'label': 'add9', 'val': 'add9'},
              {'label': '9', 'val': '9'},
              {'label': 'maj9', 'val': 'maj9'},
              {'label': 'm9', 'val': 'm9'},
              {'label': '11', 'val': '11'},
              {'label': '13', 'val': '13'},
              {'label': '7sus4', 'val': '7sus4'},
              {'label': 'sus4', 'val': 'sus4'},
              {'label': 'sus2', 'val': 'sus2'},
              {'label': 'dim', 'val': 'dim'},
              {'label': 'aug', 'val': 'aug'},
              {'label': '6', 'val': '6'},
            ];

            final quickChords = ['C', 'G', 'Am', 'F', 'Em', 'D', 'Dm', 'A', 'E', 'Bm', 'Bb', 'F#m', 'C#m', 'Gm7', 'Cadd9', 'F#m7b5']
                .map((c) => accidentalPref.formatChord(c))
                .toList();

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFD9F99D).withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.add_circle_outline_rounded, color: Color(0xFFD9F99D), size: 22),
                            ),
                            const SizedBox(width: 10),
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Tambah Akord Baru',
                                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  'Mau menambah kunci apa?',
                                  style: TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white60),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Input Manual & Hasil Racikan
                    const Text('Kunci Terpilih / Input Bebas:', style: TextStyle(color: Color(0xFFD9F99D), fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: chordController,
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF222434),
                        hintText: 'Misal: F#m7b5, Bbadd9, G/B...',
                        hintStyle: const TextStyle(color: Colors.white30),
                        prefixIcon: const Icon(Icons.music_note_rounded, color: Color(0xFFD9F99D), size: 22),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 1. Pemilih Nada Dasar (Root) & Tanda Nada
                    const Text('1. Pilih Nada Dasar (Root):', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: roots.map((r) {
                                final isSel = selectedRoot == r;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: ChoiceChip(
                                    label: Text(r, style: TextStyle(color: isSel ? const Color(0xFF14151C) : Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                    selected: isSel,
                                    selectedColor: const Color(0xFFD9F99D),
                                    backgroundColor: const Color(0xFF222434),
                                    onSelected: (_) {
                                      setSheetState(() {
                                        selectedRoot = r;
                                        updateChordText();
                                      });
                                    },
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                        // Accidental toggle
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF222434),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildAccidentalButton('♮', '', selectedAccidental, (val) {
                                setSheetState(() {
                                  selectedAccidental = val;
                                  updateChordText();
                                });
                              }),
                              _buildAccidentalButton('♯', '#', selectedAccidental, (val) {
                                setSheetState(() {
                                  selectedAccidental = val;
                                  updateChordText();
                                });
                              }),
                              _buildAccidentalButton('♭', 'b', selectedAccidental, (val) {
                                setSheetState(() {
                                  selectedAccidental = val;
                                  updateChordText();
                                });
                              }),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // 2. Kualitas Nada (Quality / Advance)
                    const Text('2. Kualitas / Varian Akord (Termasuk Advance):', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: qualities.map((q) {
                          final isSel = selectedQuality == q['val'];
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: FilterChip(
                              label: Text(q['label']!, style: TextStyle(color: isSel ? const Color(0xFF14151C) : Colors.white70, fontSize: 11.5, fontWeight: isSel ? FontWeight.bold : FontWeight.normal)),
                              selected: isSel,
                              selectedColor: const Color(0xFF38BDF8),
                              backgroundColor: const Color(0xFF222434),
                              onSelected: (_) {
                                setSheetState(() {
                                  selectedQuality = q['val']!;
                                  updateChordText();
                                });
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Quick Chords Chips
                    const Text('Atau Pilih Kunci Cepat:', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: quickChords.map((c) {
                        return InkWell(
                          onTap: () {
                            setSheetState(() => chordController.text = c);
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: chordController.text.trim() == c
                                  ? const Color(0xFFD9F99D).withValues(alpha: 0.25)
                                  : Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: chordController.text.trim() == c ? const Color(0xFFD9F99D) : Colors.white12,
                              ),
                            ),
                            child: Text(c, style: TextStyle(color: chordController.text.trim() == c ? const Color(0xFFD9F99D) : Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    // 3. Waktu Tayang (Timestamp dalam Detik)
                    const Text('3. Posisi Waktu Tayang Akord (Detik):', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: secondsController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: const Color(0xFF222434),
                              hintText: '0.0',
                              suffixText: 'detik',
                              suffixStyle: const TextStyle(color: Colors.white60, fontSize: 12),
                              prefixIcon: const Icon(Icons.timer_outlined, color: Color(0xFF38BDF8), size: 20),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Stepper cepat -0.5s dan +0.5s
                        IconButton.filledTonal(
                          tooltip: 'Mundurkan 0.5 detik',
                          onPressed: () => updateSecondsFromMs(getParsedMs() - 500),
                          icon: const Text('-0.5s', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          style: IconButton.styleFrom(backgroundColor: const Color(0xFF222434), foregroundColor: Colors.white70),
                        ),
                        const SizedBox(width: 4),
                        IconButton.filledTonal(
                          tooltip: 'Majukan 0.5 detik',
                          onPressed: () => updateSecondsFromMs(getParsedMs() + 500),
                          icon: const Text('+0.5s', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          style: IconButton.styleFrom(backgroundColor: const Color(0xFF222434), foregroundColor: Colors.white70),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Tombol sinkronisasi ke posisi audio saat ini
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => updateSecondsFromMs(player.positionMs),
                        icon: const Icon(Icons.my_location_rounded, size: 16),
                        label: Text(
                          'Ambil Posisi Audio Saat Ini (${(player.positionMs / 1000.0).toStringAsFixed(2)}s)',
                          style: const TextStyle(fontSize: 12),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF38BDF8),
                          side: const BorderSide(color: Color(0xFF38BDF8)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Tombol Aksi Tambah
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD9F99D),
                          foregroundColor: const Color(0xFF14151C),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        onPressed: () {
                          final text = chordController.text.trim();
                          if (text.isEmpty) {
                            _showToast('Nama akord tidak boleh kosong!', isError: true);
                            return;
                          }
                          final targetMs = getParsedMs();
                          Navigator.pop(ctx);
                          _insertChordAt(insertIndex ?? _syncChords.length, text, targetMs);
                        },
                        child: const Text('TAMBAHKAN KE LAGU', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAccidentalButton(String label, String value, String current, ValueChanged<String> onChanged) {
    final isSelected = current == value;
    return InkWell(
      onTap: () => onChanged(value),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF38BDF8) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? const Color(0xFF14151C) : Colors.white70,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  void _insertChordAt(int targetIndex, String initialChord, int initialMs) {
    setState(() {
      final safeIndex = targetIndex.clamp(0, _syncChords.length);
      _syncChords.insert(safeIndex, _SyncChordItem(chord: initialChord, startTimeMs: initialMs));
      _syncChords.sort((a, b) {
        if (a.startTimeMs == 0 && b.startTimeMs == 0) return 0;
        if (a.startTimeMs == 0) return 1;
        if (b.startTimeMs == 0) return -1;
        return a.startTimeMs.compareTo(b.startTimeMs);
      });
      _chordsTextController.text = _syncChords.map((c) => c.chord).join(' ');
    });
    _showToast('Akord baru [$initialChord] berhasil disisipkan.');
  }

  void _deleteChordAt(int index) {
    if (index < 0 || index >= _syncChords.length) return;
    final deleted = _syncChords.removeAt(index);
    setState(() {
      _chordsTextController.text = _syncChords.map((c) => c.chord).join(' ');
      if (_selectedChordIndex != null) {
        if (_selectedChordIndex == index) {
          _selectedChordIndex = _syncChords.isEmpty ? null : math.min(index, _syncChords.length - 1);
        } else if (_selectedChordIndex! > index) {
          _selectedChordIndex = _selectedChordIndex! - 1;
        }
      }
      if (_hoveredChordIndex != null) {
        if (_hoveredChordIndex == index) {
          _hoveredChordIndex = null;
        } else if (_hoveredChordIndex! > index) {
          _hoveredChordIndex = _hoveredChordIndex! - 1;
        }
      }
    });
    _showToast('Akord [${deleted.chord}] dihapus.');
  }

  // ── Fitur Geser Semua Akord (Bulk Shift / Global Offset) ─────────────────

  void _shiftAllChords(int deltaMs) {
    if (deltaMs == 0 || _syncChords.isEmpty) return;
    setState(() {
      for (final c in _syncChords) {
        if (c.startTimeMs > 0) {
          c.startTimeMs = math.max(0, c.startTimeMs + deltaMs);
        }
      }
      _startBeatOffsetMs = math.max(0, _startBeatOffsetMs + deltaMs);
    });
    final sign = deltaMs > 0 ? '+' : '';
    final sec = (deltaMs / 1000.0).toStringAsFixed(2);
    _showToast('Semua akord digeser $sign${sec}s ($sign${deltaMs}ms)');
  }

  void _showShiftAllChordsDialog(PlayerProvider player) {
    if (_syncChords.isEmpty) {
      _showToast('Belum ada akord untuk digeser.', isError: true);
      return;
    }

    final shiftInputController = TextEditingController(text: '0.5');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161826),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final syncedCount = _syncChords.where((c) => c.startTimeMs > 0).length;
            final firstSynced = _syncChords.cast<_SyncChordItem?>().firstWhere(
              (c) => c != null && c.startTimeMs > 0,
              orElse: () => null,
            );

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Geser Timeline Semua Akord',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white60),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Geser semua $syncedCount akord secara bersamaan maju atau mundur jika tidak pas dengan audio.',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
                    ),
                    if (firstSynced != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD9F99D).withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFD9F99D).withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          'Akord pertama: [${firstSynced.chord}] pada ${_formatMs(firstSynced.startTimeMs)} (${(firstSynced.startTimeMs / 1000.0).toStringAsFixed(2)}s)',
                          style: const TextStyle(color: Color(0xFFD9F99D), fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),

                    // ── Opsi 1: Ratakan Akord Pertama ke Posisi Audio Sekarang ──
                    if (firstSynced != null) ...[
                      const Text(
                        '1. Sesuaikan Otomatis ke Audio Saat Ini',
                        style: TextStyle(color: Color(0xFFD9F99D), fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      OutlinedButton.icon(
                        onPressed: () {
                          final diffMs = player.positionMs - firstSynced.startTimeMs;
                          _shiftAllChords(diffMs);
                          setSheetState(() {});
                        },
                        icon: const Icon(Icons.sync_alt_rounded, size: 18),
                        label: Text(
                          'Ratakan Akord Pertama ke Audio (${player.currentTimeFormatted})',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFD9F99D),
                          side: const BorderSide(color: Color(0xFFD9F99D)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ── Opsi 2: Tombol Geser Cepat (+/-) ──
                    const Text(
                      '2. Geser Cepat Bersamaan',
                      style: TextStyle(color: Color(0xFFD9F99D), fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: () {
                            _shiftAllChords(-1000);
                            setSheetState(() {});
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white24),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          child: const Text('⏪ -1.0s', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        OutlinedButton(
                          onPressed: () {
                            _shiftAllChords(-500);
                            setSheetState(() {});
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white24),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          child: const Text('◀ -0.5s', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        OutlinedButton(
                          onPressed: () {
                            _shiftAllChords(-100);
                            setSheetState(() {});
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white24),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          child: const Text('-0.1s', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        OutlinedButton(
                          onPressed: () {
                            _shiftAllChords(100);
                            setSheetState(() {});
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFD9F99D),
                            side: BorderSide(color: const Color(0xFFD9F99D).withValues(alpha: 0.5)),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          child: const Text('+0.1s', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        OutlinedButton(
                          onPressed: () {
                            _shiftAllChords(500);
                            setSheetState(() {});
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFD9F99D),
                            side: BorderSide(color: const Color(0xFFD9F99D).withValues(alpha: 0.5)),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          child: const Text('+0.5s ▶', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        OutlinedButton(
                          onPressed: () {
                            _shiftAllChords(1000);
                            setSheetState(() {});
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFD9F99D),
                            side: BorderSide(color: const Color(0xFFD9F99D).withValues(alpha: 0.5)),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          child: const Text('+1.0s ⏩', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── Opsi 3: Geser Berdasarkan Input Detik Kustom ──
                    const Text(
                      '3. Ketik Jumlah Detik Kustom',
                      style: TextStyle(color: Color(0xFFD9F99D), fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: shiftInputController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: const Color(0xFF222434),
                              hintText: 'Misal: 0.7 atau -1.2',
                              hintStyle: const TextStyle(color: Colors.white30),
                              suffixText: 'detik',
                              suffixStyle: const TextStyle(color: Color(0xFFD9F99D), fontWeight: FontWeight.bold),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            final parsed = double.tryParse(shiftInputController.text.trim().replaceAll(',', '.'));
                            if (parsed != null && parsed != 0) {
                              _shiftAllChords((parsed * 1000).round());
                              setSheetState(() {});
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFD9F99D),
                            foregroundColor: const Color(0xFF09090B),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text('Geser', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white12,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('TUTUP', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── Lyric Sync (Per Baris Vokal) ─────────────────────────────────────────

  void _startSyncingLyrics() {
    if (_syncLyrics.isEmpty) _refreshFromTextControllers(preserveTimestamps: true);
    if (_syncLyrics.isEmpty) {
      _showToast('Belum ada baris lirik yang dimasukkan di Tab Info & Lirik.', isError: true);
      return;
    }
    final player = context.read<PlayerProvider>();
    if (!player.isPlaying) {
      _playDraftAudio(player);
    }
    setState(() {
      _isSyncingLyrics = true;
      _syncingLyricIndex = 0;
    });
  }

  void _tapSyncLyric() {
    if (!_isSyncingLyrics || _syncingLyricIndex < 0 || _syncingLyricIndex >= _syncLyrics.length) return;
    final player = context.read<PlayerProvider>();
    setState(() {
      _syncLyrics[_syncingLyricIndex].startTimeMs = player.positionMs;
      _syncingLyricIndex++;
      if (_syncingLyricIndex >= _syncLyrics.length) {
        _isSyncingLyrics = false;
        _showToast('Semua baris lirik telah disinkronkan!');
      }
    });
  }

  void _undoSyncLyric() {
    if (_syncingLyricIndex <= 0 || _syncLyrics.isEmpty) return;
    final player = context.read<PlayerProvider>();
    setState(() {
      _syncingLyricIndex--;
      _syncLyrics[_syncingLyricIndex].startTimeMs = 0;
      final targetMs = math.max(0, player.positionMs - 3000);
      player.seekToMs(targetMs);
    });
  }

  void _stopSyncingLyrics() {
    setState(() {
      _isSyncingLyrics = false;
      _syncingLyricIndex = -1;
    });
  }

  // ── Save Song ─────────────────────────────────────────────────────────────

  Future<void> _saveSong() async {
    final title = _titleController.text.trim();
    final artist = _artistController.text.trim().isNotEmpty
        ? _artistController.text.trim()
        : 'Tidak Diketahui';
    final key = _keyController.text.trim().isNotEmpty ? _keyController.text.trim() : 'C';

    if (title.isEmpty) {
      _showToast('Judul lagu wajib diisi!', isError: true);
      return;
    }

    setState(() {
      _isSaving = true;
      _saveStatusMessage = 'Menyimpan lagu...';
    });

    try {
      final driveSync = context.read<GoogleDriveSyncService>();
      final library = context.read<LibraryProvider>();

      String finalCoverUrl = _coverImageUrl ?? '';
      String? finalFilePath = _audioFilePath;
      String? finalStreamUrl = _existingStreamUrl;

      // 1. Upload Cover jika file lokal dipilih
      if (_coverImagePath != null && File(_coverImagePath!).existsSync() && driveSync.isConfigured) {
        setState(() => _saveStatusMessage = 'Mengunggah foto cover ke Google Drive...');
        final bytes = await File(_coverImagePath!).readAsBytes();
        final ext = p.extension(_coverImagePath!).replaceFirst('.', '');
        final safeName = 'cover_${DateTime.now().millisecondsSinceEpoch}.$ext';
        final cloudCoverUrl = await driveSync.uploadCoverImage(filename: safeName, bytes: bytes);
        if (cloudCoverUrl != null) finalCoverUrl = cloudCoverUrl;
      }

      // 2. Audio Link
      final driveLinkText = _driveLinkController.text.trim();
      if (driveLinkText.isNotEmpty) {
        final fileId = GoogleDriveAudioService.extractFileId(driveLinkText);
        if (fileId != null) {
          finalStreamUrl = 'https://drive.usercontent.google.com/download?id=$fileId&export=download';
        }
      }

      if (_audioFilePath != null && File(_audioFilePath!).existsSync()) {
        final docsDir = await getApplicationDocumentsDirectory();
        final destPath = p.join(docsDir.path, 'songs', p.basename(_audioFilePath!));
        final destFile = File(destPath);
        await destFile.parent.create(recursive: true);
        if (destFile.path != _audioFilePath) {
          await File(_audioFilePath!).copy(destPath);
          finalFilePath = destPath;
        }

        if (driveSync.isConfigured && (finalStreamUrl == null || finalStreamUrl.isEmpty)) {
          setState(() => _saveStatusMessage = 'Mengunggah audio ke Google Drive...');
          final audioBytes = await destFile.readAsBytes();
          final uploadRes = await driveSync.uploadAudioFile(
            filename: p.basename(_audioFilePath!),
            bytes: audioBytes,
          );
          if (uploadRes != null && uploadRes['streamUrl'] != null) {
            finalStreamUrl = uploadRes['streamUrl'] as String;
          }
        }
      }

      final id = widget.existingSong?.id ??
          (finalStreamUrl != null && finalStreamUrl.contains('id=')
              ? 'drive_${GoogleDriveAudioService.extractFileId(finalStreamUrl) ?? DateTime.now().millisecondsSinceEpoch}'
              : 'custom_${DateTime.now().millisecondsSinceEpoch}');

      final lines = _buildSongLines();

      final typedBpm = double.tryParse(_bpmController.text.trim());
      final finalBpm = (typedBpm != null && typedBpm >= 40 && typedBpm <= 240) ? typedBpm : _bpm;

      final song = Song(
        id: id,
        title: title,
        artist: artist,
        albumArtUrl: finalCoverUrl.isNotEmpty ? finalCoverUrl : null,
        durationMs: widget.existingSong?.durationMs ?? 180000,
        originalKey: key,
        lines: lines,
        filePath: finalFilePath,
        streamUrl: finalStreamUrl,
        bpm: finalBpm,
        timeSignature: _timeSignature,
        startBeat: _startBeat,
        startBeatOffsetMs: _startBeatOffsetMs,
      );

      setState(() => _saveStatusMessage = 'Menyimpan ke database lokal...');
      await library.saveLocalSong(song);

      // Live update active player song
      if (mounted) {
        final player = context.read<PlayerProvider>();
        player.updateCurrentSong(song);
      }

      if (driveSync.isConfigured) {
        setState(() => _saveStatusMessage = 'Menyinkronkan ke Google Drive...');
        await driveSync.saveChordToCloud(song);
      }

      _showToast('Lagu "${song.title}" berhasil disimpan!');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _showToast('Gagal menyimpan: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _saveStatusMessage = null;
        });
      }
    }
  }

  void _showToast(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white, fontSize: 13)),
        backgroundColor: isError ? Colors.redAccent : const Color(0xFF10B981),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _formatMs(int ms) {
    if (ms <= 0) return '00:00';
    final s = ms ~/ 1000;
    final m = s ~/ 60;
    final remSec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${remSec.toString().padLeft(2, '0')}';
  }

  // ── BUILD UI ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final targetSong = widget.existingSong ?? player.currentSong;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.35),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: InkWell(
            onTap: () => Navigator.pop(context),
            borderRadius: BorderRadius.circular(20),
            child: LiquidGlassLens(
              style: const LiquidGlassStyle(
                shape: LiquidGlassShape.roundedRectangle(cornerRadius: 18),
                appearance: LiquidGlassAppearance(
                  blur: LiquidGlassBlur(sigmaX: 10, sigmaY: 10),
                  color: Color(0x33FFFFFF),
                ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
                ),
                child: const Center(
                  child: Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 16),
                ),
              ),
            ),
          ),
        ),
        title: Text(
          widget.existingSong != null ? 'Edit Lagu & Chord' : 'Tambah Lagu Baru',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.bold,
            shadows: _textShadows,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Import Chordify MIDI (.mid)',
            onPressed: _importChordifyMidi,
            icon: const Icon(Icons.file_upload_rounded, color: Color(0xFFD9F99D)),
          ),
          const SizedBox(width: 4),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFD9F99D),
          indicatorWeight: 3,
          labelColor: const Color(0xFFD9F99D),
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(icon: Icon(Icons.edit_note_rounded), text: 'Info & Input Terpisah'),
            Tab(icon: Icon(Icons.timer_rounded), text: 'Sinkronisasi Waktu'),
          ],
          onTap: (idx) {
            if (idx == 1) {
              _refreshFromTextControllers(preserveTimestamps: true);
            }
          },
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Dynamic Wavy Apple Music Aura Background
          Positioned.fill(
            child: ValueListenableBuilder<int>(
              valueListenable: AmbianceColorHelper.colorExtractionNotifier,
              builder: (context, value, child) {
                final primary = AmbianceColorHelper.getPrimaryColor(targetSong);
                final secondary = AmbianceColorHelper.getSecondaryColor(targetSong);
                return AppleMusicAuraBackground(
                  primaryColor: primary,
                  secondaryColor: secondary,
                  isPlaying: player.isPlaying,
                  vignetteOpacity: 0.25,
                );
              },
            ),
          ),
          _isSaving
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(color: Color(0xFFD9F99D)),
                      const SizedBox(height: 16),
                      Text(
                        _saveStatusMessage ?? 'Menyimpan...',
                        style: const TextStyle(color: Colors.white70, fontSize: 14, shadows: _textShadows),
                      ),
                    ],
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildInfoAndInputTab(),
                    _buildSyncTab(),
                  ],
                ),
        ],
      ),
    );
  }

  // ── TAB 1: INFO & INPUT TERPISAH ─────────────────────────────────────────

  Widget _buildInfoAndInputTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Judul Lagu (Full-width for ample breathing room)
          TextField(
            controller: _titleController,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
            decoration: _inputDecor(
              label: 'Judul Lagu *',
              icon: Icons.music_note_rounded,
              hint: 'Misal: Tercurah Darah',
            ),
          ),
          const SizedBox(height: 12),

          // Artis & Kunci (Row with flex-distributed space)
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _artistController,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: _inputDecor(
                    label: 'Artis / Penyanyi',
                    icon: Icons.person_rounded,
                    hint: 'GKI / Penyanyi',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _keyController,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  textAlign: TextAlign.center,
                  decoration: _inputDecor(
                    label: 'Kunci',
                    icon: Icons.tune_rounded,
                    hint: 'C',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 2. Birama & Tempo (BPM) - Liquid Glass Container
          _buildGlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Birama selector
                Row(
                  children: const [
                    Icon(Icons.music_note_rounded, size: 18, color: Color(0xFFD9F99D)),
                    SizedBox(width: 8),
                    Text(
                      'Birama:',
                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: ['4/4', '3/4', '6/8', '2/4'].map((sig) {
                    final isSel = _timeSignature == sig;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: InkWell(
                          onTap: () => setState(() => _timeSignature = sig),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isSel ? const Color(0xFFD9F99D) : Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSel ? const Color(0xFFD9F99D) : Colors.white.withValues(alpha: 0.10),
                              ),
                              boxShadow: isSel
                                  ? [
                                      BoxShadow(
                                        color: const Color(0xFFD9F99D).withValues(alpha: 0.35),
                                        blurRadius: 8,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Text(
                              sig,
                              style: TextStyle(
                                color: isSel ? const Color(0xFF09090B) : Colors.white70,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),

                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
                ),

                // Tempo Stepper (Anti-overflow)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.speed_rounded, size: 18, color: Color(0xFFD9F99D)),
                          SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Tempo (BPM):',
                              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildGlassCircleBtn(
                          icon: Icons.remove_rounded,
                          size: 32,
                          iconColor: Colors.white70,
                          onTap: () => setState(() {
                            _bpm = (_bpm - 5).clamp(40.0, 240.0);
                            _bpmController.text = '${_bpm.round()}';
                          }),
                        ),
                        const SizedBox(width: 8),
                        // Editable BPM badge
                        Container(
                          constraints: const BoxConstraints(minWidth: 80),
                          height: 34,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFFD9F99D).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFD9F99D)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IntrinsicWidth(
                                child: TextField(
                                  controller: _bpmController,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: false, signed: false),
                                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Color(0xFFD9F99D),
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                                    border: InputBorder.none,
                                  ),
                                  onChanged: (val) {
                                    final parsed = int.tryParse(val.trim());
                                    if (parsed != null && parsed >= 40 && parsed <= 240) {
                                      setState(() => _bpm = parsed.toDouble());
                                    }
                                  },
                                ),
                              ),
                              const Text(
                                ' BPM',
                                style: TextStyle(color: Color(0xFFD9F99D), fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(width: 2),
                              const Icon(Icons.edit_rounded, color: Color(0xFFD9F99D), size: 10),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildGlassCircleBtn(
                          icon: Icons.add_rounded,
                          size: 32,
                          iconColor: Colors.white70,
                          onTap: () => setState(() {
                            _bpm = (_bpm + 5).clamp(40.0, 240.0);
                            _bpmController.text = '${_bpm.round()}';
                          }),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                    activeTrackColor: const Color(0xFFD9F99D),
                    inactiveTrackColor: Colors.white.withValues(alpha: 0.10),
                    thumbColor: const Color(0xFFD9F99D),
                  ),
                  child: Slider(
                    value: _bpm,
                    min: 40.0,
                    max: 240.0,
                    onChanged: (val) => setState(() {
                      _bpm = val.roundToDouble();
                      _bpmController.text = '${_bpm.round()}';
                    }),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
                ),

                // ── Mulai Di Beat Ke- (Start Beat) ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.flag_rounded, size: 18, color: Color(0xFFD9F99D)),
                        SizedBox(width: 8),
                        Text(
                          'Mulai Di Beat Ke-:',
                          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD9F99D).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFD9F99D).withValues(alpha: 0.5)),
                      ),
                      child: Text(
                        'Beat $_startBeat',
                        style: const TextStyle(color: Color(0xFFD9F99D), fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Builder(
                  builder: (context) {
                    final parts = _timeSignature.split('/');
                    final beatsPerBar = math.max(1, int.tryParse(parts.first) ?? 4);
                    if (_startBeat > beatsPerBar) {
                      _startBeat = 1;
                    }
                    return Wrap(
                      spacing: 8,
                      children: List.generate(beatsPerBar, (index) {
                        final beatNum = index + 1;
                        final isSel = _startBeat == beatNum;
                        return InkWell(
                          onTap: () => setState(() => _startBeat = beatNum),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: isSel ? const Color(0xFFD9F99D) : Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSel ? const Color(0xFFD9F99D) : Colors.white.withValues(alpha: 0.10),
                              ),
                            ),
                            child: Text(
                              'Beat $beatNum',
                              style: TextStyle(
                                color: isSel ? const Color(0xFF09090B) : Colors.white70,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        );
                      }),
                    );
                  },
                ),

                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
                ),

                // ── Offset Hening Awal (Start Beat Offset) ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.timer_outlined, size: 18, color: Color(0xFFD9F99D)),
                          SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Offset Hening Awal:',
                              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD9F99D).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFD9F99D).withValues(alpha: 0.5)),
                      ),
                      child: Text(
                        '${(_startBeatOffsetMs / 1000).toStringAsFixed(2)}s (${_startBeatOffsetMs}ms)',
                        style: const TextStyle(color: Color(0xFFD9F99D), fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      OutlinedButton(
                        onPressed: () => setState(() => _startBeatOffsetMs = math.max(0, _startBeatOffsetMs - 500)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Colors.white24),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        ),
                        child: const Text('-0.5s', style: TextStyle(fontSize: 11)),
                      ),
                      const SizedBox(width: 6),
                      OutlinedButton(
                        onPressed: () => setState(() => _startBeatOffsetMs = math.max(0, _startBeatOffsetMs - 100)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Colors.white24),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        ),
                        child: const Text('-0.1s', style: TextStyle(fontSize: 11)),
                      ),
                      const SizedBox(width: 6),
                      OutlinedButton(
                        onPressed: () => setState(() => _startBeatOffsetMs += 100),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Colors.white24),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        ),
                        child: const Text('+0.1s', style: TextStyle(fontSize: 11)),
                      ),
                      const SizedBox(width: 6),
                      OutlinedButton(
                        onPressed: () => setState(() => _startBeatOffsetMs += 500),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Colors.white24),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        ),
                        child: const Text('+0.5s', style: TextStyle(fontSize: 11)),
                      ),
                      const SizedBox(width: 6),
                      TextButton(
                        onPressed: () => setState(() => _startBeatOffsetMs = 0),
                        child: const Text('Reset (0s)', style: TextStyle(color: Colors.white54, fontSize: 11)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 3. Cover Photo Section
          _buildCoverSection(),
          const SizedBox(height: 14),

          // 4. Audio Source Section
          _buildAudioSection(),
          const SizedBox(height: 18),

          // ── 5. INPUT CHORD TERPISAH (CHORDS ONLY) ──────────────────────────
          _buildGlassCard(
            padding: const EdgeInsets.all(16),
            borderColor: const Color(0xFFD9F99D).withValues(alpha: 0.25),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: const [
                          Icon(Icons.piano_rounded, color: Color(0xFFD9F99D), size: 20),
                          SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              '1. Input Akord Lagu (Chord)',
                              style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _importChordifyMidi,
                      icon: const Icon(Icons.file_upload_rounded, size: 14),
                      label: const Text('Import .mid', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFD9F99D),
                        side: const BorderSide(color: Color(0xFFD9F99D)),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD9F99D).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${_syncChords.length} Akord',
                        style: const TextStyle(color: Color(0xFFD9F99D), fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Ketik urutan chord lagu atau sentuh tombol di bawah. Jangan masukkan lirik di kotak ini.',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
                const SizedBox(height: 10),

                // Quick Chord Chips
                SizedBox(
                  height: 34,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _quickChords.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 6),
                    itemBuilder: (context, idx) {
                      final c = _quickChords[idx];
                      return ActionChip(
                        label: Text('+$c', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        backgroundColor: Colors.white.withValues(alpha: 0.08),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        onPressed: () => _insertChord(c),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),

                // Chords TextField
                TextField(
                  controller: _chordsTextController,
                  maxLines: 6,
                  minLines: 3,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                  onChanged: (_) => _refreshFromTextControllers(preserveTimestamps: true),
                  decoration: InputDecoration(
                    hintText: 'Contoh:\nBb  Bbm  A/C#  D\nC   G    Am    F',
                    hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.04),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.10))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.10))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFD9F99D))),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),

                if (_syncChords.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 5,
                    children: [
                      for (final c in _syncChords)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                          ),
                          child: Text(
                            c.chord,
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),

          // ── 6. INPUT LIRIK TERPISAH (LYRICS ONLY) ──────────────────────────
          _buildGlassCard(
            padding: const EdgeInsets.all(16),
            borderColor: Colors.white.withValues(alpha: 0.15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: const [
                          Icon(Icons.mic_rounded, color: Color(0xFF38BDF8), size: 20),
                          SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              '2. Input Lirik Vokal (Lirik Bersih)',
                              style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${_syncLyrics.length} Baris',
                        style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Ketik atau salin-tempel lirik lagu bersih per baris (tanpa perlu tanda kurung chord).',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
                const SizedBox(height: 10),

                // Lyrics TextField
                TextField(
                  controller: _lyricsTextController,
                  maxLines: 12,
                  minLines: 6,
                  style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5),
                  onChanged: (_) => _refreshFromTextControllers(preserveTimestamps: true),
                  decoration: InputDecoration(
                    hintText: 'Contoh:\nTercurah darah Tuhanku\nDi bukit Golgota\nMenghapus dosa-dosaku\nHidupku jadi baru',
                    hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.04),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.10))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.10))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF38BDF8))),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Save Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveSong,
              icon: const Icon(Icons.cloud_upload_rounded, size: 20),
              label: Text(
                widget.existingSong != null ? 'Simpan Perubahan Lagu' : 'Simpan ke Google Drive & Accord',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 0.2),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD9F99D),
                foregroundColor: const Color(0xFF09090B),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                elevation: 4,
                shadowColor: const Color(0xFFD9F99D).withValues(alpha: 0.4),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ── Cover Image Section Widget ───────────────────────────────────────────

  Widget _buildCoverSection() {
    ImageProvider? imageProvider;
    if (_coverImagePath != null && File(_coverImagePath!).existsSync()) {
      imageProvider = FileImage(File(_coverImagePath!));
    } else if (_coverImageUrl != null && _coverImageUrl!.isNotEmpty) {
      imageProvider = NetworkImage(_coverImageUrl!);
    }

    return _buildGlassCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.white.withValues(alpha: 0.10), const Color(0xFF141522)],
                ),
                image: imageProvider != null ? DecorationImage(image: imageProvider, fit: BoxFit.cover) : null,
              ),
              child: imageProvider == null ? const Icon(Icons.image_rounded, color: Colors.white54, size: 28) : null,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Foto Cover / Profil', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _pickCoverFromGallery,
                      icon: const Icon(Icons.photo_library_rounded, size: 14),
                      label: const Text('Galeri', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFD9F99D),
                        side: const BorderSide(color: Color(0xFFD9F99D)),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _showCoverUrlDialog,
                      icon: const Icon(Icons.link_rounded, size: 14),
                      label: const Text('URL', style: TextStyle(fontSize: 11)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    if (imageProvider != null) ...[
                      const SizedBox(width: 6),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 18),
                        onPressed: () => setState(() {
                          _coverImagePath = null;
                          _coverImageUrl = null;
                        }),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Audio Source Section Widget ──────────────────────────────────────────

  Widget _buildAudioSection() {
    final hasAudio = (_audioFilePath != null && _audioFilePath!.isNotEmpty) ||
        (_existingStreamUrl != null && _existingStreamUrl!.isNotEmpty) ||
        _driveLinkController.text.trim().isNotEmpty;

    return _buildGlassCard(
      padding: const EdgeInsets.all(14),
      borderColor: hasAudio ? const Color(0xFFD9F99D).withValues(alpha: 0.35) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasAudio ? Icons.check_circle_rounded : Icons.audiotrack_rounded,
                color: hasAudio ? const Color(0xFFD9F99D) : Colors.white54,
                size: 18,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Musik / Audio Lagu',
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
              if (_audioFilePath != null)
                Text(
                  _audioFileSize != null ? '${(_audioFileSize! / (1024 * 1024)).toStringAsFixed(1)} MB' : '',
                  style: const TextStyle(color: Color(0xFFD9F99D), fontSize: 11, fontWeight: FontWeight.bold),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (_audioFileName != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFD9F99D).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.audio_file_rounded, color: Color(0xFFD9F99D), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _audioFileName!,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _pickAudioFile,
                  icon: const Icon(Icons.folder_open_rounded, size: 16),
                  label: Text(_audioFilePath != null ? 'Ganti File Audio HP' : 'Pilih File MP3 dari HP'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFFD9F99D), width: 1.0),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _driveLinkController,
            style: const TextStyle(color: Colors.white, fontSize: 12),
            decoration: _inputDecor(
              label: 'Atau Link Google Drive',
              icon: Icons.link_rounded,
              hint: 'https://drive.google.com/file/d/.../view',
            ),
          ),
        ],
      ),
    );
  }

  // ── TAB 2: SINKRONISASI WAKTU ─────────────────────────────────────────────

  Widget _buildSyncTab() {
    final player = context.watch<PlayerProvider>();
    final hasAudioSource = (_audioFilePath != null && _audioFilePath!.isNotEmpty) ||
        (_existingStreamUrl != null && _existingStreamUrl!.isNotEmpty) ||
        _driveLinkController.text.trim().isNotEmpty;

    return Column(
      children: [
        // ── 1. Integrated Audio Player Controller ────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF141522).withValues(alpha: 0.65),
            border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          player.isPlaying ? Icons.graphic_eq_rounded : Icons.audiotrack_rounded,
                          color: player.isPlaying ? const Color(0xFFD9F99D) : Colors.white60,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _titleController.text.trim().isNotEmpty ? _titleController.text.trim() : 'Lagu Pratinjau',
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!player.isPlaying && hasAudioSource)
                    TextButton.icon(
                      onPressed: () => _playDraftAudio(player),
                      icon: const Icon(Icons.play_circle_fill_rounded, color: Color(0xFFD9F99D), size: 16),
                      label: const Text('Putar', style: TextStyle(color: Color(0xFFD9F99D), fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
              // Slider
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  activeTrackColor: const Color(0xFFD9F99D),
                  inactiveTrackColor: Colors.white12,
                  thumbColor: const Color(0xFFD9F99D),
                ),
                child: Slider(
                  value: (player.durationMs > 0 ? (player.positionMs / player.durationMs) : 0.0).clamp(0.0, 1.0),
                  onChanged: (val) => player.seek(val),
                ),
              ),
              Row(
                children: [
                  Text(
                    _formatMs(player.positionMs),
                    style: const TextStyle(color: Color(0xFFD9F99D), fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.replay_5_rounded, color: Colors.white70, size: 20),
                    tooltip: 'Mundur 3 detik',
                    onPressed: () => player.seekToMs(math.max(0, player.positionMs - 3000)),
                  ),
                  GestureDetector(
                    onTap: () {
                      if (!player.isPlaying && !hasAudioSource) {
                        _showToast('Pilih file audio atau tempel link Google Drive terlebih dahulu!', isError: true);
                        return;
                      }
                      if (!player.isPlaying && player.currentSong == null) {
                        _playDraftAudio(player);
                      } else {
                        player.togglePlayPause();
                      }
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFD9F99D),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFD9F99D).withValues(alpha: 0.35),
                            blurRadius: 10,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Icon(
                        player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: const Color(0xFF09090B),
                        size: 24,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.forward_5_rounded, color: Colors.white70, size: 20),
                    tooltip: 'Maju 3 detik',
                    onPressed: () => player.seekToMs(math.min(player.durationMs, player.positionMs + 3000)),
                  ),
                  const Spacer(),
                  Text(
                    _formatMs(player.durationMs),
                    style: const TextStyle(color: Colors.white38, fontSize: 12, fontFamily: 'monospace'),
                  ),
                ],
              ),
            ],
          ),
        ),

        // ── 2. Sub-Mode Toggle: CHORD SATU PER SATU vs LIRIK PER BARIS ────────
        Container(
          width: double.infinity,
          color: const Color(0xFF10111A).withValues(alpha: 0.50),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: _buildSubModeButton(
                  title: '🎸 Sync Tiap Chord',
                  count: '${_syncChords.length} Akord',
                  isSelected: _syncSubMode == SyncSubMode.chords,
                  activeColor: const Color(0xFFD9F99D),
                  onTap: () {
                    setState(() {
                      _syncSubMode = SyncSubMode.chords;
                      _stopSyncingLyrics();
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildSubModeButton(
                  title: '🎤 Sync Baris Lirik',
                  count: '${_syncLyrics.length} Baris',
                  isSelected: _syncSubMode == SyncSubMode.lyrics,
                  activeColor: const Color(0xFF38BDF8),
                  onTap: () {
                    setState(() {
                      _syncSubMode = SyncSubMode.lyrics;
                      _stopSyncingChords();
                    });
                  },
                ),
              ),
            ],
          ),
        ),

        // ── 3. Content: Either Chords or Lyrics ──────────────────────────────
        Expanded(
          child: _syncSubMode == SyncSubMode.chords
              ? _buildChordSyncView(player)
              : _buildLyricSyncView(player),
        ),
      ],
    );
  }

  Widget _buildSubModeButton({
    required String title,
    required String count,
    required bool isSelected,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? activeColor : Colors.white.withValues(alpha: 0.1),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          children: [
            Text(
              title,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              count,
              style: TextStyle(
                color: isSelected ? activeColor : Colors.white38,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactActionBtn({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onPressed,
    double size = 18,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 32,
          height: 32,
          child: Center(
            child: Icon(icon, color: color, size: size),
          ),
        ),
      ),
    );
  }

  // ── VIEW 1: SINKRONISASI CHORD SATU PER SATU ──────────────────────────────

  Widget _buildChordSyncView(PlayerProvider player) {
    final accidentalPref = AccidentalPreferenceService.of(context);
    final syncedCount = _syncChords.where((c) => c.startTimeMs > 0).length;

    return Column(
      children: [
        // ── Beat Grid Preview ──
        if (_syncChords.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: const Color(0xFF12131E).withValues(alpha: 0.60),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'PRATINJAU BEAT GRID (CHORDIFY)',
                      style: TextStyle(color: Color(0xFFD9F99D), fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                    ),
                    Text(
                      'Tersinkron: $syncedCount / ${_syncChords.length}',
                      style: const TextStyle(color: Color(0xFFD9F99D), fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ChordifyBeatGridWidget(
                  lines: _syncChords.asMap().entries.map((e) => SongLine(
                    lineIndex: e.key,
                    startTimeMs: e.value.startTimeMs,
                    rawLine: '[${e.value.chord}]',
                  )).toList(),
                  positionMs: player.positionMs,
                  totalDurationMs: player.durationMs,
                  bpm: _bpm,
                  timeSignature: _timeSignature,
                  startBeat: _startBeat,
                  startBeatOffsetMs: _startBeatOffsetMs,
                  onSeek: (seekMs) => player.seekToMs(seekMs),
                ),
              ],
            ),
          ),
        ],

        // ── Active Sync Bar (Chord Satu per Satu) ──
        if (_isSyncingChords && _syncingChordIndex >= 0 && _syncingChordIndex < _syncChords.length) ...[
          Builder(
            builder: (context) {
              final currentChordItem = _syncChords[_syncingChordIndex];
              final hasNext = _syncingChordIndex + 1 < _syncChords.length;
              final nextChordItem = hasNext ? _syncChords[_syncingChordIndex + 1] : null;

              return Container(
                padding: const EdgeInsets.all(14),
                color: const Color(0xFF181A2A).withValues(alpha: 0.65),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'AKORD ${_syncingChordIndex + 1} DARI ${_syncChords.length}',
                          style: const TextStyle(color: Color(0xFFD9F99D), fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        TextButton(
                          onPressed: _stopSyncingChords,
                          style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(50, 20)),
                          child: const Text('Hentikan', style: TextStyle(color: Colors.redAccent, fontSize: 11)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        PianoChordDiagramWidget(
                          chordName: currentChordItem.chord,
                          width: 130,
                          height: 68,
                          isCurrent: true,
                          showChordName: false,
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              currentChordItem.chord,
                              style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900),
                            ),
                            if (nextChordItem != null)
                              Text(
                                'Berikutnya: ${nextChordItem.chord}',
                                style: const TextStyle(color: Colors.white54, fontSize: 12),
                              ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (_syncingChordIndex > 0) ...[
                          OutlinedButton.icon(
                            onPressed: _undoSyncChord,
                            icon: const Icon(Icons.undo_rounded, size: 14),
                            label: const Text('Mundur', style: TextStyle(fontSize: 11)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                              side: const BorderSide(color: Colors.white24),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _tapSyncChord,
                            icon: const Icon(Icons.touch_app_rounded, size: 20),
                            label: Text(
                              'KETUK CHORD: [${currentChordItem.chord}] (${_formatMs(player.positionMs)})',
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFD9F99D),
                              foregroundColor: const Color(0xFF09090B),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              elevation: 4,
                              shadowColor: const Color(0xFFD9F99D).withValues(alpha: 0.4),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ] else ...[
          // Idle Action Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            color: const Color(0xFF12131E).withValues(alpha: 0.60),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _startSyncingChords,
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: const Text('Sync Chord Satu per Satu', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD9F99D),
                          foregroundColor: const Color(0xFF09090B),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _importChordifyMidi,
                      icon: const Icon(Icons.file_upload_rounded, size: 15),
                      label: const Text('Import .mid', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFD9F99D),
                        side: const BorderSide(color: Color(0xFFD9F99D)),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _showShiftAllChordsDialog(player),
                        icon: const Icon(Icons.tune_rounded, size: 16),
                        label: const Text('Geser Semua Akord', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF38BDF8),
                          side: const BorderSide(color: Color(0xFF38BDF8)),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () => _showAddChordDialog(player),
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Tambah Akord', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFD9F99D),
                        side: const BorderSide(color: Color(0xFFD9F99D)),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          for (final c in _syncChords) {
                            c.startTimeMs = 0;
                          }
                        });
                        _showToast('Timestamp semua chord direset.');
                      },
                      child: const Text('Reset', style: TextStyle(color: Colors.redAccent, fontSize: 11)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],

        // ── Pratinjau Diagram Akord Terpilih / Di-Hover ──
        if (_syncChords.isNotEmpty) ...[
          Builder(builder: (context) {
            final activeIdx = (_hoveredChordIndex != null && _hoveredChordIndex! < _syncChords.length)
                ? _hoveredChordIndex!
                : (_selectedChordIndex != null && _selectedChordIndex! < _syncChords.length
                    ? _selectedChordIndex!
                    : 0);
            final activeItem = _syncChords[activeIdx];
            final isHovering = _hoveredChordIndex == activeIdx;
            final isSelected = _selectedChordIndex == activeIdx;
            final voicing = PianoChordEngine.getVoicing(activeItem.chord);

            return Container(
              margin: const EdgeInsets.fromLTRB(14, 4, 14, 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isHovering ? const Color(0xFF191E34) : const Color(0xFF141624),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isHovering
                      ? const Color(0xFF38BDF8)
                      : (isSelected
                          ? const Color(0xFFD9F99D).withValues(alpha: 0.6)
                          : Colors.white.withValues(alpha: 0.12)),
                  width: isHovering ? 1.5 : 1.0,
                ),
                boxShadow: isHovering
                    ? [
                        BoxShadow(
                          color: const Color(0xFF38BDF8).withValues(alpha: 0.22),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                children: [
                  PianoChordDiagramWidget(
                    chordName: activeItem.chord,
                    width: 124,
                    height: 56,
                    isCurrent: true,
                    showChordName: false,
                    activeColor: isHovering ? const Color(0xFF38BDF8) : const Color(0xFFD9F99D),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: (isHovering
                                        ? const Color(0xFF38BDF8)
                                        : const Color(0xFFD9F99D))
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                isHovering
                                    ? 'DI-HOVER (#${activeIdx + 1})'
                                    : 'TERPILIH (#${activeIdx + 1})',
                                style: TextStyle(
                                  color: isHovering ? const Color(0xFF38BDF8) : const Color(0xFFD9F99D),
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (activeItem.startTimeMs > 0)
                              Text(
                                _formatMs(activeItem.startTimeMs),
                                style: const TextStyle(color: Colors.white60, fontSize: 10, fontFamily: 'monospace'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          accidentalPref.formatChord(activeItem.chord),
                          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
                        ),
                        if (voicing.notes.isNotEmpty)
                          Text(
                            'Nada: ${voicing.notes.join(' - ')}',
                            style: const TextStyle(color: Colors.white54, fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_rounded, size: 18, color: Colors.white70),
                    tooltip: 'Edit Kunci',
                    onPressed: () => _showEditChordDialog(activeIdx),
                  ),
                ],
              ),
            );
          }),
        ],

        // ── List of Chord Items ──
        Expanded(
          child: _syncChords.isEmpty
              ? const Center(
                  child: Text('Belum ada akord. Masukkan di Tab 1 atau Import MIDI.', style: TextStyle(color: Colors.white38)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  itemCount: _syncChords.length,
                  itemBuilder: (context, idx) {
                    final item = _syncChords[idx];
                    final hasTime = item.startTimeMs > 0;
                    final isHovered = _hoveredChordIndex == idx;
                    final isSelected = _selectedChordIndex == idx;

                    return MouseRegion(
                      cursor: SystemMouseCursors.click,
                      onEnter: (_) => setState(() => _hoveredChordIndex = idx),
                      onExit: (_) => setState(() {
                        if (_hoveredChordIndex == idx) _hoveredChordIndex = null;
                      }),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() => _selectedChordIndex = idx),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          curve: Curves.easeOut,
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: isHovered
                                ? const Color(0xFF22283E)
                                : (isSelected
                                    ? const Color(0xFF1E2436)
                                    : Colors.white.withValues(alpha: hasTime ? 0.06 : 0.02)),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isHovered
                                  ? const Color(0xFF38BDF8)
                                  : (isSelected
                                      ? const Color(0xFFD9F99D).withValues(alpha: 0.85)
                                      : (hasTime
                                          ? const Color(0xFFD9F99D).withValues(alpha: 0.35)
                                          : Colors.white.withValues(alpha: 0.06))),
                              width: isHovered ? 1.8 : (isSelected ? 1.4 : 1.0),
                            ),
                            boxShadow: isHovered
                                ? [
                                    BoxShadow(
                                      color: const Color(0xFF38BDF8).withValues(alpha: 0.35),
                                      blurRadius: 10,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : (isSelected
                                    ? [
                                        BoxShadow(
                                          color: const Color(0xFFD9F99D).withValues(alpha: 0.15),
                                          blurRadius: 6,
                                        ),
                                      ]
                                    : null),
                          ),
                          child: Row(
                            children: [
                              Text(
                                '#${idx + 1}',
                                style: TextStyle(
                                  color: isHovered
                                      ? const Color(0xFF38BDF8)
                                      : (isSelected ? const Color(0xFFD9F99D) : Colors.white30),
                                  fontSize: 10,
                                  fontWeight: isHovered || isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                              const SizedBox(width: 6),
                              // Tap badge akord untuk edit kunci & waktu langsung
                              InkWell(
                                onTap: () => _showEditChordDialog(idx),
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isHovered
                                        ? const Color(0xFF283454)
                                        : const Color(0xFF222433),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: isHovered
                                          ? const Color(0xFF38BDF8)
                                          : (isSelected
                                              ? const Color(0xFFD9F99D).withValues(alpha: 0.6)
                                              : Colors.white.withValues(alpha: 0.15)),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        accidentalPref.formatChord(item.chord),
                                        style: TextStyle(
                                          color: isHovered ? const Color(0xFF38BDF8) : Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(
                                        Icons.edit_rounded,
                                        color: isHovered ? const Color(0xFF38BDF8) : const Color(0xFFD9F99D),
                                        size: 10,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Tap timestamp badge untuk edit
                              InkWell(
                                onTap: () => _showEditChordDialog(idx),
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: hasTime ? const Color(0xFFD9F99D).withValues(alpha: 0.18) : Colors.white12,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    hasTime ? _formatMs(item.startTimeMs) : '--:--',
                                    style: TextStyle(
                                      color: hasTime ? const Color(0xFFD9F99D) : Colors.white38,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                              ),
                              const Spacer(),
                              // Nudge -0.5s
                              _buildCompactActionBtn(
                                icon: Icons.remove_circle_outline_rounded,
                                color: isHovered ? Colors.white70 : Colors.white54,
                                tooltip: '-0.5s',
                                onPressed: () {
                                  setState(() {
                                    item.startTimeMs = math.max(0, item.startTimeMs - 500);
                                  });
                                },
                              ),
                              // Nudge +0.5s
                              _buildCompactActionBtn(
                                icon: Icons.add_circle_outline_rounded,
                                color: isHovered ? Colors.white70 : Colors.white54,
                                tooltip: '+0.5s',
                                onPressed: () {
                                  setState(() {
                                    item.startTimeMs += 500;
                                  });
                                },
                              ),
                              // Set waktu detik ini
                              _buildCompactActionBtn(
                                icon: Icons.timer_outlined,
                                color: const Color(0xFFD9F99D),
                                tooltip: 'Set Waktu Detik Ini',
                                onPressed: () {
                                  setState(() {
                                    item.startTimeMs = player.positionMs;
                                  });
                                },
                                size: 18,
                              ),
                              // Tombol Edit Kunci & Detik
                              _buildCompactActionBtn(
                                icon: Icons.edit_note_rounded,
                                color: const Color(0xFFD9F99D),
                                tooltip: 'Edit Kunci & Detik',
                                onPressed: () => _showEditChordDialog(idx),
                                size: 20,
                              ),
                              // Dengar
                              _buildCompactActionBtn(
                                icon: Icons.play_circle_outline_rounded,
                                color: const Color(0xFF38BDF8),
                                tooltip: 'Dengar',
                                onPressed: () {
                                  if (item.startTimeMs > 0) {
                                    player.seekToMs(item.startTimeMs);
                                    if (!player.isPlaying) player.togglePlayPause();
                                  } else {
                                    _showToast('Chord belum memiliki timestamp.');
                                  }
                                },
                                size: 18,
                              ),
                              // Hapus Akord
                              _buildCompactActionBtn(
                                icon: Icons.delete_outline_rounded,
                                color: Colors.redAccent,
                                tooltip: 'Hapus Akord',
                                onPressed: () => _deleteChordAt(idx),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ── VIEW 2: SINKRONISASI LIRIK PER BARIS ──────────────────────────────────

  Widget _buildLyricSyncView(PlayerProvider player) {
    return Column(
      children: [
        // ── Active Sync Bar (Lirik) ──
        if (_isSyncingLyrics && _syncingLyricIndex >= 0 && _syncingLyricIndex < _syncLyrics.length) ...[
          Builder(
            builder: (context) {
              final currentLyric = _syncLyrics[_syncingLyricIndex];
              final hasNext = _syncingLyricIndex + 1 < _syncLyrics.length;
              final nextLyric = hasNext ? _syncLyrics[_syncingLyricIndex + 1] : null;

              return Container(
                padding: const EdgeInsets.all(14),
                color: const Color(0xFF141D26).withValues(alpha: 0.65),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'BARIS LIRIK ${_syncingLyricIndex + 1} DARI ${_syncLyrics.length}',
                          style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        TextButton(
                          onPressed: _stopSyncingLyrics,
                          style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(50, 20)),
                          child: const Text('Hentikan', style: TextStyle(color: Colors.redAccent, fontSize: 11)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      currentLyric.text,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (nextLyric != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Berikutnya: ${nextLyric.text}',
                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (_syncingLyricIndex > 0) ...[
                          OutlinedButton.icon(
                            onPressed: _undoSyncLyric,
                            icon: const Icon(Icons.undo_rounded, size: 14),
                            label: const Text('Mundur', style: TextStyle(fontSize: 11)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                              side: const BorderSide(color: Colors.white24),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _tapSyncLyric,
                            icon: const Icon(Icons.mic_rounded, size: 20),
                            label: Text(
                              'KETUK LIRIK INI (${_formatMs(player.positionMs)})',
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF38BDF8),
                              foregroundColor: const Color(0xFF09090B),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              elevation: 4,
                              shadowColor: const Color(0xFF38BDF8).withValues(alpha: 0.4),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ] else ...[
          // Idle Action Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            color: const Color(0xFF12131E).withValues(alpha: 0.60),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _startSyncingLyrics,
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('Sync Lirik Per Baris', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF38BDF8),
                      foregroundColor: const Color(0xFF09090B),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    setState(() {
                      for (final l in _syncLyrics) {
                        l.startTimeMs = 0;
                      }
                    });
                    _showToast('Timestamp semua lirik direset.');
                  },
                  child: const Text('Reset', style: TextStyle(color: Colors.redAccent, fontSize: 11)),
                ),
              ],
            ),
          ),
        ],

        // ── List of Lyric Items ──
        Expanded(
          child: _syncLyrics.isEmpty
              ? const Center(
                  child: Text('Belum ada lirik. Masukkan di Tab 1.', style: TextStyle(color: Colors.white38)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  itemCount: _syncLyrics.length,
                  itemBuilder: (context, idx) {
                    final item = _syncLyrics[idx];
                    final hasTime = item.startTimeMs > 0;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: hasTime ? 0.06 : 0.02),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: hasTime ? const Color(0xFF38BDF8).withValues(alpha: 0.35) : Colors.white.withValues(alpha: 0.05),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.text,
                                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: hasTime ? const Color(0xFF38BDF8).withValues(alpha: 0.18) : Colors.white12,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    hasTime ? _formatMs(item.startTimeMs) : '--:--',
                                    style: TextStyle(
                                      color: hasTime ? const Color(0xFF38BDF8) : Colors.white38,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Nudge -0.5s
                          _buildCompactActionBtn(
                            icon: Icons.remove_circle_outline_rounded,
                            color: Colors.white54,
                            tooltip: '-0.5s',
                            onPressed: () {
                              setState(() {
                                item.startTimeMs = math.max(0, item.startTimeMs - 500);
                              });
                            },
                          ),
                          // Nudge +0.5s
                          _buildCompactActionBtn(
                            icon: Icons.add_circle_outline_rounded,
                            color: Colors.white54,
                            tooltip: '+0.5s',
                            onPressed: () {
                              setState(() {
                                item.startTimeMs += 500;
                              });
                            },
                          ),
                          // Set Waktu
                          _buildCompactActionBtn(
                            icon: Icons.timer_outlined,
                            color: const Color(0xFF38BDF8),
                            tooltip: 'Set Waktu Detik Ini',
                            onPressed: () {
                              setState(() {
                                item.startTimeMs = player.positionMs;
                              });
                            },
                            size: 18,
                          ),
                          // Dengar
                          _buildCompactActionBtn(
                            icon: Icons.play_circle_outline_rounded,
                            color: const Color(0xFFD9F99D),
                            tooltip: 'Dengar',
                            onPressed: () {
                              if (item.startTimeMs > 0) {
                                player.seekToMs(item.startTimeMs);
                                if (!player.isPlaying) player.togglePlayPause();
                              } else {
                                _showToast('Baris lirik belum memiliki timestamp.');
                              }
                            },
                            size: 18,
                          ),
                          // Hapus
                          _buildCompactActionBtn(
                            icon: Icons.close_rounded,
                            color: Colors.redAccent,
                            tooltip: 'Hapus Waktu',
                            onPressed: () {
                              setState(() {
                                item.startTimeMs = 0;
                              });
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildGlassCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(18),
    EdgeInsetsGeometry? margin,
    double borderRadius = 20,
    Color? borderColor,
  }) {
    Widget lens = LiquidGlassLens(
      style: LiquidGlassStyle(
        shape: LiquidGlassShape.roundedRectangle(cornerRadius: borderRadius),
        appearance: const LiquidGlassAppearance(
          blur: LiquidGlassBlur(sigmaX: 14, sigmaY: 14),
          color: Color(0x3B0B0C12),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(
            color: borderColor ?? Colors.white.withValues(alpha: 0.12),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
    if (margin != null) {
      return Padding(padding: margin, child: lens);
    }
    return lens;
  }

  Widget _buildGlassCircleBtn({
    required IconData icon,
    required VoidCallback onTap,
    String? tooltip,
    Color? iconColor,
    double size = 36,
  }) {
    Widget btn = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(size / 2),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.08),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        ),
        child: Center(
          child: Icon(icon, size: 18, color: iconColor ?? Colors.white),
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip, child: btn);
    }
    return btn;
  }

  InputDecoration _inputDecor({
    required String label,
    required IconData icon,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70, fontSize: 13),
      hintText: hint,
      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.30), fontSize: 13),
      prefixIcon: Icon(icon, color: const Color(0xFFD9F99D), size: 20),
      filled: true,
      fillColor: const Color(0x3B0B0C12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFD9F99D), width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }
}
