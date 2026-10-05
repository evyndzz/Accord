import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chord_shape.dart';
import '../models/song.dart';
import '../models/song_line.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../services/google_drive_sync_service.dart';
import '../widgets/chord_diagram.dart';

/// Screen for creating or editing a song's chord sheet locally.
class EditorScreen extends StatefulWidget {
  /// If provided, edit an existing local song
  final Song? existingSong;

  const EditorScreen({super.key, this.existingSong});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final _titleController = TextEditingController();
  final _artistController = TextEditingController();
  final _keyController = TextEditingController();
  final List<_LineEditor> _lines = [];
  bool _isSaving = false;
  bool _isSyncing = false;
  int _syncingLineIndex = -1;

  // Preview: chord being typed
  String _previewChord = '';

  @override
  void initState() {
    super.initState();

    if (widget.existingSong != null) {
      final song = widget.existingSong!;
      _titleController.text = song.title;
      _artistController.text = song.artist;
      _keyController.text = song.originalKey ?? '';
      for (final line in song.lines) {
        _lines.add(_LineEditor(
          controller: TextEditingController(text: line.rawLine),
          startTimeMs: line.startTimeMs,
        ));
      }
    } else {
      for (int i = 0; i < 4; i++) {
        _lines.add(_LineEditor(controller: TextEditingController()));
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    _keyController.dispose();
    for (final l in _lines) {
      l.controller.dispose();
    }
    super.dispose();
  }

  // ── Tap-to-Sync logic ────────────────────────────────────────────────────

  void _startSyncing() {
    final player = context.read<PlayerProvider>();
    if (player.currentSong == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Putar lagu terlebih dahulu untuk sinkronisasi waktu chord!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() {
      _isSyncing = true;
      _syncingLineIndex = 0;
      // Reset all timestamps
      for (final l in _lines) {
        l.startTimeMs = 0;
      }
    });
  }

  void _tapSync() {
    if (!_isSyncing || _syncingLineIndex >= _lines.length) return;
    final player = context.read<PlayerProvider>();
    setState(() {
      _lines[_syncingLineIndex].startTimeMs = player.positionMs;
      _syncingLineIndex++;
      if (_syncingLineIndex >= _lines.length) {
        _isSyncing = false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sync complete! All lines timed.'),
            backgroundColor: Color(0xFF181A2A),
          ),
        );
      }
    });
  }

  void _stopSyncing() {
    setState(() {
      _isSyncing = false;
      _syncingLineIndex = -1;
    });
  }

  // ── Save ─────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a title')),
      );
      return;
    }
    setState(() => _isSaving = true);

    final lines = <SongLine>[];
    for (int i = 0; i < _lines.length; i++) {
      final raw = _lines[i].controller.text.trim();
      if (raw.isNotEmpty) {
        lines.add(SongLine(
          lineIndex: i,
          startTimeMs: _lines[i].startTimeMs,
          rawLine: raw,
        ));
      }
    }

    final id = widget.existingSong?.id ??
        'local_${DateTime.now().millisecondsSinceEpoch}';

    final song = Song(
      id: id,
      title: _titleController.text.trim(),
      artist: _artistController.text.trim(),
      durationMs: widget.existingSong?.durationMs ?? 0,
      originalKey: _keyController.text.trim().isEmpty
          ? null
          : _keyController.text.trim(),
      lines: lines,
      gradientColors: widget.existingSong?.gradientColors,
    );

    final library = context.read<LibraryProvider>();
    final driveSync = context.read<GoogleDriveSyncService>();
    await library.saveLocalSong(song);

    // Also upload to Google Drive Cloud Vault if connected
    bool cloudSaved = false;
    if (driveSync.isConfigured) {
      cloudSaved = await driveSync.saveChordToCloud(song);
    }

    setState(() => _isSaving = false);

    if (mounted) {
      Navigator.pop(context, song);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(cloudSaved
              ? 'Chord & lirik berhasil disimpan ke HP & Google Drive Cloud Vault! ☁️'
              : 'Chord & lirik berhasil disimpan ke library!'),
          backgroundColor: const Color(0xFF181A2A),
        ),
      );
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFF0E0F17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141522),
        foregroundColor: Colors.white,
        title: const Text('Chord Editor',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    color: Color(0xFFD9F99D), strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: _save,
              child: const Text('Save',
                  style: TextStyle(
                      color: Color(0xFFD9F99D), fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Player Info Bar ───────────────────────────────────────────
          if (player.currentSong != null)
            _buildPlayerBar(player),

          // ── Sync Controls ──────────────────────────────────────────────
          if (_isSyncing) _buildSyncBar(player) else _buildToolBar(),

          // ── Chord Preview ──────────────────────────────────────────────
          if (_previewChord.isNotEmpty) _buildChordPreview(),

          // ── Lines Editor ───────────────────────────────────────────────
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _lines.length + 1,
              itemBuilder: (context, index) {
                if (index == _lines.length) {
                  return _buildAddLineButton();
                }
                return _buildLineRow(index, player);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerBar(PlayerProvider player) {
    final title = player.currentSong?.title ?? '';
    return Container(
      color: const Color(0xFFD9F99D).withValues(alpha: 0.1),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.music_note_rounded,
              color: Color(0xFFD9F99D), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (player.currentSong != null)
            Text(
              player.positionFormatted,
              style: const TextStyle(
                  color: Color(0xFFD9F99D),
                  fontSize: 13,
                  fontWeight: FontWeight.bold),
            ),
        ],
      ),
    );
  }

  Widget _buildToolBar() {
    return Container(
      color: const Color(0xFF161724),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Quick chord insert helpers
          const Text('Add:',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(width: 8),
          for (final chord in ['C', 'D', 'E', 'Am', 'G', 'F', 'Bm'])
            GestureDetector(
              onTap: () {
                // Insert chord at cursor — simplified
                setState(() => _previewChord = chord);
              },
              child: Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF222436),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15)),
                ),
                child: Text(
                  chord,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
          const Spacer(),
          TextButton.icon(
            onPressed: _startSyncing,
            icon: const Icon(Icons.sync_rounded,
                color: Color(0xFFD9F99D), size: 18),
            label: const Text('Sync',
                style: TextStyle(color: Color(0xFFD9F99D), fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncBar(PlayerProvider player) {
    return Container(
      color: const Color(0xFF181A2A),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.touch_app_rounded, color: Color(0xFFD9F99D), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _syncingLineIndex < _lines.length
                  ? 'Tap when line ${_syncingLineIndex + 1} starts singing...'
                  : 'Done!',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
          ElevatedButton(
            onPressed: _tapSync,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD9F99D),
              foregroundColor: const Color(0xFF09090B),
              minimumSize: const Size(64, 36),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('TAP', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white54),
            onPressed: _stopSyncing,
          ),
        ],
      ),
    );
  }

  Widget _buildChordPreview() {
    final shape = ChordDictionary.get(_previewChord);
    return Container(
      color: const Color(0xFF161724),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            height: 70,
            child: ChordDiagramWidget(shape: shape),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _previewChord,
                style: const TextStyle(
                    color: Color(0xFFD9F99D),
                    fontSize: 20,
                    fontWeight: FontWeight.bold),
              ),
              const Text('Tap chord to copy to line',
                  style: TextStyle(color: Colors.white54, fontSize: 11)),
            ],
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white54),
            onPressed: () => setState(() => _previewChord = ''),
          ),
        ],
      ),
    );
  }

  Widget _buildLineRow(int index, PlayerProvider player) {
    final line = _lines[index];
    final isActiveSyncLine = _isSyncing && index == _syncingLineIndex;
    final isSynced = line.startTimeMs > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isActiveSyncLine
            ? const Color(0xFFD9F99D).withValues(alpha: 0.15)
            : const Color(0xFF161724),
        borderRadius: BorderRadius.circular(12),
        border: isActiveSyncLine
            ? Border.all(color: const Color(0xFFD9F99D), width: 1.5)
            : Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          // Line number + sync status
          SizedBox(
            width: 44,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 16),
                Text(
                  '${index + 1}',
                  style: TextStyle(
                      color: isActiveSyncLine
                          ? const Color(0xFFD9F99D)
                          : Colors.white38,
                      fontSize: 12),
                ),
                if (isSynced)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      _formatMs(line.startTimeMs),
                      style: const TextStyle(
                          color: Color(0xFFD9F99D), fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                  ),
                const SizedBox(height: 16),
              ],
            ),
          ),
          // Text field
          Expanded(
            child: TextField(
              controller: line.controller,
              onChanged: (v) {
                // Show chord preview when typing inside brackets
                final match = RegExp(r'\[([A-G][^]]*)]?$').firstMatch(v);
                if (match != null) {
                  setState(() => _previewChord = match.group(1)!);
                }
              },
              style: const TextStyle(
                  color: Colors.white, fontSize: 14, height: 1.5),
              decoration: InputDecoration(
                hintText: index == 0
                    ? 'e.g. [Bm]Baby, I love your [Em]wants'
                    : '[Chord]Lyric text...',
                hintStyle:
                    const TextStyle(color: Colors.white24, fontSize: 13),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              ),
              maxLines: null,
            ),
          ),
          // Delete line
          IconButton(
            icon: const Icon(Icons.remove_circle_outline,
                color: Colors.white24, size: 18),
            onPressed: () => setState(() => _lines.removeAt(index)),
          ),
        ],
      ),
    );
  }

  Widget _buildAddLineButton() {
    return TextButton.icon(
      onPressed: () =>
          setState(() => _lines.add(_LineEditor(controller: TextEditingController()))),
      icon: const Icon(Icons.add_circle_outline, color: Color(0xFFD9F99D)),
      label: const Text('Add line',
          style: TextStyle(color: Color(0xFFD9F99D))),
    );
  }

  String _formatMs(int ms) {
    final m = ms ~/ 60000;
    final s = (ms % 60000) ~/ 1000;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

/// Simple mutable wrapper for a lyric line in the editor
class _LineEditor {
  final TextEditingController controller;
  int startTimeMs;

  _LineEditor({required this.controller, this.startTimeMs = 0});
}
