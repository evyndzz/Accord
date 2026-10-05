import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/song_line.dart';
import '../services/accidental_preference.dart';
import '../utils/chord_parser.dart';
import '../utils/transposer.dart';

class ChordifyBeat {
  final int barIndex;
  final int beatInBar; // 0, 1, 2, ... beatsPerBar-1
  final int startTimeMs;
  final int durationMs;
  final List<String> chords; // Multi-chord per beat support (e.g. ['C', 'G'])
  final bool isRest;
  final bool isContinuation; // Chord from previous beat is sustained

  const ChordifyBeat({
    required this.barIndex,
    required this.beatInBar,
    required this.startTimeMs,
    required this.durationMs,
    this.chords = const [],
    this.isRest = false,
    this.isContinuation = false,
  });

  bool get hasChord => chords.isNotEmpty;
  String? get primaryChord => chords.isNotEmpty ? chords.first : null;
}

class ChordifyBeatGridWidget extends StatefulWidget {
  final List<SongLine> lines;
  final int positionMs;
  final int totalDurationMs;
  final double bpm;
  final String timeSignature;
  final int transposeOffset;
  final int startBeat;
  final int startBeatOffsetMs;
  final ValueChanged<int> onSeek;

  const ChordifyBeatGridWidget({
    super.key,
    required this.lines,
    required this.positionMs,
    required this.totalDurationMs,
    this.bpm = 120.0,
    this.timeSignature = '4/4',
    this.transposeOffset = 0,
    this.startBeat = 1,
    this.startBeatOffsetMs = 0,
    required this.onSeek,
  });

  /// Ekstraksi & pembentukan list beat birama ala Chordify berdasarkan tempo dan birama
  static List<ChordifyBeat> generateBeats({
    required List<SongLine> lines,
    required int totalDurationMs,
    double bpm = 120.0,
    String timeSignature = '4/4',
    int transposeOffset = 0,
    int startBeat = 1,
    int startBeatOffsetMs = 0,
  }) {
    final effectiveBpm = (bpm > 0) ? bpm : 120.0;
    final beatDurMs = (60000.0 / effectiveBpm).round();
    final parts = timeSignature.split('/');
    final beatsPerBar = math.max(1, int.tryParse(parts.first) ?? 4);
    final startBeatIdx = (startBeat - 1).clamp(0, beatsPerBar - 1);
    final safeOffsetMs = math.max(0, startBeatOffsetMs);

    final hasAnyTimestamp = lines.any((l) => l.startTimeMs > 0);

    // Kumpulkan semua event akord berurutan dengan waktu timestamp
    final chordEvents = <_TimedChord>[];
    for (int i = 0; i < lines.length; i++) {
      final l = lines[i];
      // Jika lagu sudah memiliki timestamp, abaikan baris yang belum disinkronisasi (startTimeMs <= 0) agar tidak menumpuk di beat 0
      if (hasAnyTimestamp && l.startTimeMs <= 0 && i > 0) continue;

      final transposed = TransposeEngine.transposeLine(l.rawLine, transposeOffset);
      final parsed = ChordParser.parse(transposed);
      if (parsed.chords.isNotEmpty) {
        if (parsed.chords.length == 1) {
          chordEvents.add(_TimedChord(l.startTimeMs, parsed.chords.first.chord));
        } else {
          // Jika dalam 1 baris teks terdapat deretan chord, sebar dalam rentang waktu baris
          final count = parsed.chords.length;
          final stepMs = math.max(beatDurMs ~/ 2, 400);
          for (int cIdx = 0; cIdx < count; cIdx++) {
            chordEvents.add(_TimedChord(
              l.startTimeMs + (cIdx * stepMs),
              parsed.chords[cIdx].chord,
            ));
          }
        }
      }
    }

    // Urutkan event akord berdasarkan waktu
    chordEvents.sort((a, b) => a.timeMs.compareTo(b.timeMs));

    // Tentukan durasi maksimal grid
    int maxMs = totalDurationMs;
    if (chordEvents.isNotEmpty && chordEvents.last.timeMs >= maxMs) {
      maxMs = chordEvents.last.timeMs + (beatDurMs * beatsPerBar);
    }
    if (maxMs <= 0) {
      maxMs = safeOffsetMs + (beatDurMs * beatsPerBar * 4); // fallback 4 birama jika durasi 0
    }

    // Hitung total ketukan yang dibutuhkan hingga durasi lagu (dibulatkan ke birama penuh)
    final elapsedMs = math.max(0, maxMs - safeOffsetMs);
    final beatsAfterStart = (elapsedMs / beatDurMs).ceil();
    final rawTotalBeats = startBeatIdx + beatsAfterStart;
    final totalBars = math.max(1, (rawTotalBeats / beatsPerBar).ceil());
    final totalBeats = totalBars * beatsPerBar;

    // Petakan akord ke slot beat: 1 beat bisa menampung maksimal 2 akord
    final beatChordsMap = <int, List<String>>{};
    for (final ev in chordEvents) {
      final relMs = ev.timeMs - safeOffsetMs;
      final beatIdx = startBeatIdx + (relMs / beatDurMs).floor();
      if (beatIdx >= 0) {
        final list = beatChordsMap.putIfAbsent(beatIdx, () => []);
        if (list.length < 2 && !list.contains(ev.chord)) {
          list.add(ev.chord);
        }
      }
    }

    final beats = <ChordifyBeat>[];
    bool hasSeenFirstChord = false;

    for (int b = 0; b < totalBeats; b++) {
      final bar = b ~/ beatsPerBar;
      final beatInBar = b % beatsPerBar;
      final startTime = safeOffsetMs + ((b - startBeatIdx) * beatDurMs);

      if (b < startBeatIdx) {
        // Ketukan intro / jeda sebelum beat mulai lagu
        beats.add(ChordifyBeat(
          barIndex: bar,
          beatInBar: beatInBar,
          startTimeMs: math.max(0, startTime),
          durationMs: beatDurMs,
          chords: const [],
          isRest: true,
          isContinuation: false,
        ));
      } else {
        final assignedChords = beatChordsMap[b] ?? const <String>[];

        if (assignedChords.isNotEmpty) {
          hasSeenFirstChord = true;
          beats.add(ChordifyBeat(
            barIndex: bar,
            beatInBar: beatInBar,
            startTimeMs: math.max(0, startTime),
            durationMs: beatDurMs,
            chords: assignedChords,
            isRest: false,
            isContinuation: false,
          ));
        } else {
          // Tidak ada pergantian akord baru di beat ini
          final isRest = !hasSeenFirstChord;
          final isContinuation = hasSeenFirstChord;
          beats.add(ChordifyBeat(
            barIndex: bar,
            beatInBar: beatInBar,
            startTimeMs: math.max(0, startTime),
            durationMs: beatDurMs,
            chords: const [],
            isRest: isRest,
            isContinuation: isContinuation,
          ));
        }
      }
    }

    return beats;
  }

  @override
  State<ChordifyBeatGridWidget> createState() => _ChordifyBeatGridWidgetState();
}

class _TimedChord {
  final int timeMs;
  final String chord;
  const _TimedChord(this.timeMs, this.chord);
}

class _ChordifyBeatGridWidgetState extends State<ChordifyBeatGridWidget> {
  final ScrollController _scrollController = ScrollController();
  int _lastActiveBeatIndex = -1;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _autoScrollToBeat(int activeIndex, int beatsPerBar) {
    if (activeIndex == _lastActiveBeatIndex || activeIndex < 0) return;
    _lastActiveBeatIndex = activeIndex;

    if (!_scrollController.hasClients) return;

    // Ukuran real setiap sel beat (harus cocok dengan ListView)
    const double beatCellWidth = 50.0;
    const double beatMarginHoriz = 3.0; // 1.5 kiri + 1.5 kanan
    const double separatorWidth = 3.0;
    const double separatorMarginHoriz = 6.0; // 3 kiri + 3 kanan

    // Hitung berapa separator yang muncul sebelum beat ini
    // Separator muncul di setiap awal birama kecuali index 0
    final int numSeparatorsBefore = activeIndex ~/ beatsPerBar;

    // Posisi pixel kiri dari beat aktif (termasuk padding awal ListView = 4px)
    final double beatPixelOffset = 4.0
        + activeIndex * (beatCellWidth + beatMarginHoriz)
        + numSeparatorsBefore * (separatorWidth + separatorMarginHoriz);

    // Agar beat aktif selalu di tengah viewport
    final double viewportWidth = _scrollController.position.viewportDimension;
    final double targetScroll = beatPixelOffset - (viewportWidth / 2) + (beatCellWidth / 2);

    _scrollController.animateTo(
      targetScroll.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutQuad,
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveBpm = (widget.bpm > 0) ? widget.bpm : 120.0;
    final beatDurMs = (60000.0 / effectiveBpm).round();
    final parts = widget.timeSignature.split('/');
    final beatsPerBar = math.max(1, int.tryParse(parts.first) ?? 4);
    final startBeatIdx = (widget.startBeat - 1).clamp(0, beatsPerBar - 1);
    final safeOffsetMs = math.max(0, widget.startBeatOffsetMs);

    final beats = ChordifyBeatGridWidget.generateBeats(
      lines: widget.lines,
      totalDurationMs: widget.totalDurationMs,
      bpm: widget.bpm,
      timeSignature: widget.timeSignature,
      transposeOffset: widget.transposeOffset,
      startBeat: widget.startBeat,
      startBeatOffsetMs: widget.startBeatOffsetMs,
    );

    // Cari beat aktif berdasarkan tempo & offset awal
    int activeBeatIndex = -1;
    if (widget.positionMs >= 0 && beatDurMs > 0) {
      if (widget.positionMs < safeOffsetMs) {
        // Jika sedang di dalam lead-in bar sebelum safeOffsetMs
        final timeBeforeStart = safeOffsetMs - widget.positionMs;
        final beatsBefore = (timeBeforeStart / beatDurMs).ceil();
        if (beatsBefore <= startBeatIdx && startBeatIdx > 0) {
          activeBeatIndex = startBeatIdx - beatsBefore;
        } else {
          activeBeatIndex = -1;
        }
      } else {
        final elapsed = widget.positionMs - safeOffsetMs;
        activeBeatIndex = startBeatIdx + (elapsed / beatDurMs).floor();
        if (activeBeatIndex >= beats.length) {
          activeBeatIndex = beats.length - 1;
        }
      }
    }

    if (activeBeatIndex >= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoScrollToBeat(activeBeatIndex, beatsPerBar);
      });
    }

    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F0F5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: ListView.builder(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        itemCount: beats.length,
        itemBuilder: (context, index) {
          final beat = beats[index];
          final isActive = index == activeBeatIndex;
          final isFirstInBar = beat.beatInBar == 0;

          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Garis pemisah birama tebal di setiap awal birama
              if (index > 0 && isFirstInBar)
                Container(
                  width: 3.0,
                  height: 52,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4B5563),
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),

              // Kotak Beat (Cell ala Chordify dengan Hover Effect)
              _HoverableBeatCell(
                beat: beat,
                isActive: isActive,
                onTap: () => widget.onSeek(beat.startTimeMs),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HoverableBeatCell extends StatefulWidget {
  final ChordifyBeat beat;
  final bool isActive;
  final VoidCallback onTap;

  const _HoverableBeatCell({
    required this.beat,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_HoverableBeatCell> createState() => _HoverableBeatCellState();
}

class _HoverableBeatCellState extends State<_HoverableBeatCell> {
  bool _isHovered = false;

  String _formatTime(int ms) {
    final s = ms ~/ 1000;
    final m = s ~/ 60;
    final remS = s % 60;
    return '${m.toString().padLeft(2, '0')}:${remS.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final accidentalPref = AccidentalPreferenceService.of(context);
    final beat = widget.beat;
    final isActive = widget.isActive;

    final chordNames = beat.chords.map((c) => accidentalPref.formatChord(c)).toList();
    final tooltipText = chordNames.isNotEmpty
        ? '${chordNames.join(" - ")} • ${_formatTime(beat.startTimeMs)}'
        : _formatTime(beat.startTimeMs);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Tooltip(
        message: tooltipText,
        waitDuration: const Duration(milliseconds: 300),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            transform: Matrix4.diagonal3Values(_isHovered ? 1.05 : 1.0, _isHovered ? 1.05 : 1.0, 1.0),
            transformAlignment: Alignment.center,
            width: 50,
            height: 52,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(
              color: isActive
                  ? const Color(0xFF2A3022)
                  : _isHovered
                      ? const Color(0xFF2D3244)
                      : const Color(0xFF23242E),
              borderRadius: BorderRadius.circular(8),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: const Color(0xFFD9F99D).withValues(alpha: 0.45),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : _isHovered
                      ? [
                          BoxShadow(
                            color: const Color(0xFF38BDF8).withValues(alpha: 0.5),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
              border: Border.all(
                color: isActive
                    ? const Color(0xFFD9F99D)
                    : _isHovered
                        ? const Color(0xFF38BDF8)
                        : Colors.white.withValues(alpha: 0.12),
                width: isActive || _isHovered ? 2.0 : 1.0,
              ),
            ),
            child: _buildBeatCellContent(beat, isActive, chordNames),
          ),
        ),
      ),
    );
  }

  Widget _buildBeatCellContent(ChordifyBeat beat, bool isActive, List<String> formattedChords) {
    if (beat.isRest) {
      return Center(
        child: Text(
          '𝄽',
          style: TextStyle(
            fontSize: 20,
            color: isActive ? const Color(0xFFD9F99D) : const Color(0xFFA1A1AA),
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    if (beat.isContinuation && formattedChords.isEmpty) {
      return Center(
        child: Text(
          '•',
          style: TextStyle(
            fontSize: 22,
            color: isActive ? const Color(0xFFD9F99D) : Colors.white24,
            fontWeight: FontWeight.w900,
          ),
        ),
      );
    }

    if (formattedChords.isEmpty) {
      return const SizedBox.shrink();
    }

    if (formattedChords.length == 1) {
      final chord = formattedChords.first;
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2.0),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              chord,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: chord.length > 3 ? 12 : 14,
                fontWeight: FontWeight.w900,
                color: isActive
                    ? const Color(0xFFD9F99D)
                    : _isHovered
                        ? const Color(0xFF38BDF8)
                        : Colors.white,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: Row(
        children: [
          for (int i = 0; i < formattedChords.length; i++) ...[
            if (i > 0)
              Container(
                width: 1,
                color: isActive ? const Color(0xFFD9F99D).withValues(alpha: 0.3) : Colors.white12,
              ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.0),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      formattedChords[i],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: isActive
                            ? const Color(0xFFD9F99D)
                            : _isHovered
                                ? const Color(0xFF38BDF8)
                                : Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
