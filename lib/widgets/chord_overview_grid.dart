import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/song_line.dart';
import '../services/accidental_preference.dart';
import 'chordify_beat_grid.dart';

/// Full-Page 2D Chord Overview Grid ala Chordify
/// Menampilkan seluruh pergerakan akor lagu dalam bentuk matriks ketukan dan birama berurutan.
class ChordOverviewGridWidget extends StatefulWidget {
  final List<SongLine> lines;
  final int positionMs;
  final int totalDurationMs;
  final double bpm;
  final String timeSignature;
  final int transposeOffset;
  final int startBeat;
  final int startBeatOffsetMs;
  final ValueChanged<int> onSeek;

  const ChordOverviewGridWidget({
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

  @override
  State<ChordOverviewGridWidget> createState() => _ChordOverviewGridWidgetState();
}

class _ChordOverviewGridWidgetState extends State<ChordOverviewGridWidget> {
  final ScrollController _scrollController = ScrollController();
  int _lastActiveRow = -1;
  int _barsPerRow = 4; // Default 4 bar ala Chordify screenshot, bisa diubah ke 2 bar

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _autoScrollToRow(int rowIndex) {
    if (rowIndex == _lastActiveRow || rowIndex < 0) return;
    _lastActiveRow = rowIndex;

    if (_scrollController.hasClients) {
      const rowHeight = 48.0;
      // Posisikan baris aktif di sepertiga atas layar agar baris berikutnya terlihat lapang
      final target = (rowIndex * rowHeight) - 96.0;
      _scrollController.animateTo(
        target.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    }
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

    int activeBeatIndex = -1;
    if (widget.positionMs >= 0 && beatDurMs > 0) {
      if (widget.positionMs < safeOffsetMs) {
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

    final totalBars = (beats.length / beatsPerBar).ceil();
    final totalRows = math.max(1, (totalBars / _barsPerRow).ceil());

    int activeRow = -1;
    if (activeBeatIndex >= 0 && activeBeatIndex < beats.length) {
      final activeBar = beats[activeBeatIndex].barIndex;
      activeRow = activeBar ~/ _barsPerRow;
    }

    if (activeRow >= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoScrollToRow(activeRow);
      });
    }

    return Column(
      children: [
        // Sub-header kecil pengatur baris (2 Bar / 4 Bar) dan info birama
        Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 2, right: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1F2937),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        '$totalBars BAR',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '${widget.timeSignature} • ${effectiveBpm.round()} BPM',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFA1A1AA),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Segmented toggle untuk 4 Bar / 2 Bar per baris
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF23242E),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                padding: const EdgeInsets.all(2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _BarCountPill(
                      label: '4 Bar',
                      isSelected: _barsPerRow == 4,
                      onTap: () => setState(() => _barsPerRow = 4),
                    ),
                    _BarCountPill(
                      label: '2 Bar',
                      isSelected: _barsPerRow == 2,
                      onTap: () => setState(() => _barsPerRow = 2),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Matriks Utama Chord Overview
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF141520),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 1.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: ListView.separated(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: totalRows,
                separatorBuilder: (context, index) => Container(
                  height: 1.0,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
                itemBuilder: (context, rowIndex) {
                  return _buildGridRow(
                    rowIndex: rowIndex,
                    beats: beats,
                    beatsPerBar: beatsPerBar,
                    activeBeatIndex: activeBeatIndex,
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGridRow({
    required int rowIndex,
    required List<ChordifyBeat> beats,
    required int beatsPerBar,
    required int activeBeatIndex,
  }) {
    final startBar = rowIndex * _barsPerRow;

    return SizedBox(
      height: 48,
      child: Row(
        children: [
          for (int b = 0; b < _barsPerRow; b++) ...[
            if (b > 0)
              // Garis pemisah birama tebal antar bar
              Container(
                width: 2.0,
                height: 48,
                color: Colors.white.withValues(alpha: 0.18),
              ),
            Expanded(
              child: _buildBarCells(
                barIndex: startBar + b,
                beats: beats,
                beatsPerBar: beatsPerBar,
                activeBeatIndex: activeBeatIndex,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBarCells({
    required int barIndex,
    required List<ChordifyBeat> beats,
    required int beatsPerBar,
    required int activeBeatIndex,
  }) {
    final startBeat = barIndex * beatsPerBar;

    return Row(
      children: [
        for (int beatInBar = 0; beatInBar < beatsPerBar; beatInBar++) ...[
          if (beatInBar > 0)
            // Garis pembatas ketukan halus dalam birama yang sama
            Container(
              width: 0.8,
              height: 48,
              color: Colors.white.withValues(alpha: 0.05),
            ),
          Expanded(
            child: Builder(
              builder: (context) {
                final beatIdx = startBeat + beatInBar;
                if (beatIdx >= beats.length) {
                  return const SizedBox.shrink();
                }
                final beat = beats[beatIdx];
                final isActive = (beatIdx == activeBeatIndex);

                return _buildCell(beat: beat, isActive: isActive);
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCell({
    required ChordifyBeat beat,
    required bool isActive,
  }) {
    return _OverviewBeatCellItem(
      beat: beat,
      isActive: isActive,
      barsPerRow: _barsPerRow,
      onSeek: widget.onSeek,
    );
  }
}

class _OverviewBeatCellItem extends StatefulWidget {
  final ChordifyBeat beat;
  final bool isActive;
  final int barsPerRow;
  final ValueChanged<int> onSeek;

  const _OverviewBeatCellItem({
    required this.beat,
    required this.isActive,
    required this.barsPerRow,
    required this.onSeek,
  });

  @override
  State<_OverviewBeatCellItem> createState() => _OverviewBeatCellItemState();
}

class _OverviewBeatCellItemState extends State<_OverviewBeatCellItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final accidentalPref = AccidentalPreferenceService.of(context);
    final beat = widget.beat;
    final isActive = widget.isActive;
    final hasChord = beat.chords.isNotEmpty;

    final formattedChords = beat.chords.map((c) => accidentalPref.formatChord(c)).toList();

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: () => widget.onSeek(beat.startTimeMs),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          transform: Matrix4.diagonal3Values(_isHovered ? 1.06 : 1.0, _isHovered ? 1.06 : 1.0, 1.0),
          transformAlignment: Alignment.center,
          margin: const EdgeInsets.all(2.0),
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFF283618)
                : _isHovered
                    ? const Color(0xFF2C3246)
                    : hasChord
                        ? const Color(0xFF222433)
                        : const Color(0xFF181926).withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isActive
                  ? const Color(0xFFD9F99D)
                  : _isHovered
                      ? const Color(0xFF38BDF8)
                      : hasChord
                          ? Colors.white.withValues(alpha: 0.16)
                          : Colors.white.withValues(alpha: 0.05),
              width: isActive || _isHovered ? 1.8 : 1.0,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: const Color(0xFFD9F99D).withValues(alpha: 0.45),
                      blurRadius: 8,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : _isHovered
                    ? [
                        BoxShadow(
                          color: const Color(0xFF38BDF8).withValues(alpha: 0.5),
                          blurRadius: 8,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : null,
          ),
          child: Center(
            child: _buildCellContent(beat, isActive, formattedChords),
          ),
        ),
      ),
    );
  }

  Widget _buildCellContent(ChordifyBeat beat, bool isActive, List<String> formattedChords) {
    if (beat.isRest) {
      return Text(
        '𝄽',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: isActive ? const Color(0xFFD9F99D) : const Color(0xFF71717A),
        ),
      );
    }

    if (formattedChords.isEmpty) {
      if (beat.isContinuation) {
        return Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? const Color(0xFFD9F99D) : Colors.white24,
          ),
        );
      }
      return const SizedBox.shrink();
    }

    if (formattedChords.length == 1) {
      final chord = formattedChords.first;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2.0),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            chord,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: widget.barsPerRow == 4 ? 13 : 15,
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
      );
    }

    final displayChords = formattedChords.take(2).toList();
    return Row(
      children: [
        for (int i = 0; i < displayChords.length; i++) ...[
          if (i > 0)
            Container(
              width: 0.8,
              height: 24,
              color: isActive ? const Color(0xFFD9F99D).withValues(alpha: 0.3) : Colors.white12,
            ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 0.5),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    displayChords[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
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
    );
  }
}

class _BarCountPill extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _BarCountPill({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFD9F99D) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFFD9F99D).withValues(alpha: 0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? const Color(0xFF09090B) : const Color(0xFFA1A1AA),
          ),
        ),
      ),
    );
  }
}
