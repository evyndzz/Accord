import 'dart:io';
import 'dart:math' as math;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'song_editor_screen.dart';
import '../models/song.dart';
import '../models/song_line.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../utils/ambiance_color_helper.dart';
import '../utils/chord_parser.dart';
import '../widgets/apple_music_aura_background.dart';
import '../widgets/chord_overview_grid.dart';
import '../widgets/chordify_beat_grid.dart';
import '../widgets/piano_chord_diagram.dart';
import '../widgets/waveform.dart';

enum PlayerViewMode {
  chordDiagrams, // Tampilan Diagram Piano & Lirik Terpadu
  chordOverview, // Tampilan Full Matriks Chord ala Chordify
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final ScrollController _lyricsScrollController = ScrollController();
  final Map<int, GlobalKey> _lyricKeys = {};
  int _lastAutoScrolledIndex = -1;
  String? _lastSongId;
  PlayerViewMode _viewMode = PlayerViewMode.chordDiagrams;

  @override
  void dispose() {
    _lyricsScrollController.dispose();
    super.dispose();
  }

  void _scrollToActiveLyric(int index) {
    if (index < 0) return;

    final key = _lyricKeys[index];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        alignment: 0.5,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    } else if (_lyricsScrollController.hasClients) {
      final viewportHeight = _lyricsScrollController.position.viewportDimension;
      const estimatedItemHeight = 58.0;
      final targetOffset = (index * estimatedItemHeight) - (viewportHeight / 2) + (estimatedItemHeight / 2);
      _lyricsScrollController.animateTo(
        targetOffset.clamp(0.0, _lyricsScrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _showTempoBottomSheet(BuildContext context, Song song) {
    final player = context.read<PlayerProvider>();
    double currentBpm = song.effectiveBpm;
    String currentTimeSignature = song.effectiveTimeSignature;
    int currentStartBeat = song.effectiveStartBeat;
    int currentStartBeatOffsetMs = song.effectiveStartBeatOffsetMs;
    final List<int> tapTimes = [];
    final bpmController = TextEditingController(text: '${currentBpm.round()}');

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            void syncChanges() {
              player.updateSongBeatSettings(
                bpm: currentBpm,
                timeSignature: currentTimeSignature,
                startBeat: currentStartBeat,
                startBeatOffsetMs: currentStartBeatOffsetMs,
              );
            }

            void updateBpm(double newBpm) {
              currentBpm = newBpm.clamp(40.0, 240.0);
              final textVal = '${currentBpm.round()}';
              if (bpmController.text != textVal) {
                bpmController.text = textVal;
              }
              syncChanges();
            }

            void recordTap() {
              final now = DateTime.now().millisecondsSinceEpoch;
              tapTimes.add(now);
              if (tapTimes.length > 5) tapTimes.removeAt(0);

              if (tapTimes.length >= 2) {
                int totalDiff = 0;
                for (int i = 1; i < tapTimes.length; i++) {
                  totalDiff += (tapTimes[i] - tapTimes[i - 1]);
                }
                final avgMs = totalDiff / (tapTimes.length - 1);
                if (avgMs > 200 && avgMs < 2000) {
                  final calculatedBpm = (60000.0 / avgMs).clamp(40.0, 240.0).roundToDouble();
                  setSheetState(() => updateBpm(calculatedBpm));
                }
              }
            }

            final parts = currentTimeSignature.split('/');
            final beatsPerBar = math.max(1, int.tryParse(parts.first) ?? 4);
            if (currentStartBeat > beatsPerBar) {
              currentStartBeat = 1;
            }

            return LiquidGlassLens(
              style: const LiquidGlassStyle(
                shape: LiquidGlassShape.roundedRectangle(cornerRadius: 28),
                appearance: LiquidGlassAppearance(
                  blur: LiquidGlassBlur(sigmaX: 24, sigmaY: 24),
                  color: Color(0x520B0C12),
                ),
              ),
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.88,
                ),
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
                ),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    top: 16,
                    bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
                  ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Atur Birama & Tempo',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white70),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // ── 1. Birama (Time Signature) ──
                    const Text('Birama (Time Signature)', style: TextStyle(color: Color(0xFFD9F99D), fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      children: ['4/4', '3/4', '6/8', '2/4'].map((sig) {
                        final isSelected = currentTimeSignature == sig;
                        return ChoiceChip(
                          label: Text(sig, style: TextStyle(color: isSelected ? const Color(0xFF09090B) : Colors.white70, fontWeight: FontWeight.bold)),
                          selected: isSelected,
                          selectedColor: const Color(0xFFD9F99D),
                          backgroundColor: const Color(0xFF282935),
                          onSelected: (val) {
                            if (val) {
                              setSheetState(() => currentTimeSignature = sig);
                              syncChanges();
                            }
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 18),

                    // ── 2. Mulai Di Beat Ke- (Start Beat) ──
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text(
                            'Mulai Di Beat Ke- (Start Beat)',
                            style: TextStyle(color: Color(0xFFD9F99D), fontSize: 12, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
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
                            'Beat $currentStartBeat',
                            style: const TextStyle(color: Color(0xFFD9F99D), fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Pilih ketukan awal lagu dalam birama (anacrusis/intro).',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: List.generate(beatsPerBar, (index) {
                        final beatNum = index + 1;
                        final isSelected = currentStartBeat == beatNum;
                        return ChoiceChip(
                          label: Text(
                            'Beat $beatNum',
                            style: TextStyle(
                              color: isSelected ? const Color(0xFF09090B) : Colors.white70,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          selected: isSelected,
                          selectedColor: const Color(0xFFD9F99D),
                          backgroundColor: const Color(0xFF282935),
                          onSelected: (val) {
                            if (val) {
                              setSheetState(() => currentStartBeat = beatNum);
                              syncChanges();
                            }
                          },
                        );
                      }),
                    ),
                    const SizedBox(height: 18),

                    // ── 3. Offset Waktu Hening Awal (Start Beat Offset) ──
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text(
                            'Offset Awal / Hening (Delay)',
                            style: TextStyle(color: Color(0xFFD9F99D), fontSize: 12, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
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
                            '${(currentStartBeatOffsetMs / 1000).toStringAsFixed(2)}s (${currentStartBeatOffsetMs}ms)',
                            style: const TextStyle(color: Color(0xFFD9F99D), fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Sesuaikan jika audio memiliki jeda hening di awal agar metronome pas.',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
                    ),
                    const SizedBox(height: 8),

                    // Tombol 1-Tap Gunakan Posisi Audio Sekarang
                    OutlinedButton.icon(
                      onPressed: () {
                        setSheetState(() => currentStartBeatOffsetMs = player.positionMs);
                        syncChanges();
                      },
                      icon: const Icon(Icons.timer_outlined, size: 16),
                      label: Text('Gunakan Posisi Lagu Sekarang (${player.currentTimeFormatted})'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFD9F99D),
                        side: BorderSide(color: const Color(0xFFD9F99D).withValues(alpha: 0.6)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Stepper Offset Cepat
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          OutlinedButton(
                            onPressed: () {
                              setSheetState(() => currentStartBeatOffsetMs = math.max(0, currentStartBeatOffsetMs - 500));
                              syncChanges();
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                              side: const BorderSide(color: Colors.white24),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            ),
                            child: const Text('-0.5s', style: TextStyle(fontSize: 11)),
                          ),
                          const SizedBox(width: 6),
                          OutlinedButton(
                            onPressed: () {
                              setSheetState(() => currentStartBeatOffsetMs = math.max(0, currentStartBeatOffsetMs - 100));
                              syncChanges();
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                              side: const BorderSide(color: Colors.white24),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            ),
                            child: const Text('-0.1s', style: TextStyle(fontSize: 11)),
                          ),
                          const SizedBox(width: 6),
                          OutlinedButton(
                            onPressed: () {
                              setSheetState(() => currentStartBeatOffsetMs += 100);
                              syncChanges();
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                              side: const BorderSide(color: Colors.white24),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            ),
                            child: const Text('+0.1s', style: TextStyle(fontSize: 11)),
                          ),
                          const SizedBox(width: 6),
                          OutlinedButton(
                            onPressed: () {
                              setSheetState(() => currentStartBeatOffsetMs += 500);
                              syncChanges();
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                              side: const BorderSide(color: Colors.white24),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            ),
                            child: const Text('+0.5s', style: TextStyle(fontSize: 11)),
                          ),
                          const SizedBox(width: 6),
                          TextButton(
                            onPressed: () {
                              setSheetState(() => currentStartBeatOffsetMs = 0);
                              syncChanges();
                            },
                            child: const Text('Reset (0s)', style: TextStyle(color: Colors.white54, fontSize: 11)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // ── 4. Tempo (BPM) ──
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Tempo (BPM)', style: TextStyle(color: Color(0xFFD9F99D), fontSize: 12, fontWeight: FontWeight.bold)),
                        // Editable BPM badge
                        Container(
                          constraints: const BoxConstraints(minWidth: 100),
                          height: 36,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
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
                                  controller: bpmController,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: false, signed: false),
                                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Color(0xFFD9F99D),
                                    fontSize: 16,
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
                                      setSheetState(() {
                                        currentBpm = parsed.toDouble();
                                      });
                                      syncChanges();
                                    }
                                  },
                                ),
                              ),
                              const Text(
                                ' BPM',
                                style: TextStyle(color: Color(0xFFD9F99D), fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(width: 2),
                              const Icon(Icons.edit_rounded, color: Color(0xFFD9F99D), size: 11),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        IconButton.filledTonal(
                          onPressed: () {
                            setSheetState(() => updateBpm(currentBpm - 5));
                          },
                          icon: const Text('-5', style: TextStyle(fontWeight: FontWeight.bold)),
                          style: IconButton.styleFrom(backgroundColor: const Color(0xFF282935), foregroundColor: Colors.white),
                        ),
                        const SizedBox(width: 4),
                        IconButton.filledTonal(
                          onPressed: () {
                            setSheetState(() => updateBpm(currentBpm - 1));
                          },
                          icon: const Icon(Icons.remove, size: 18),
                          style: IconButton.styleFrom(backgroundColor: const Color(0xFF282935), foregroundColor: Colors.white),
                        ),
                        Expanded(
                          child: Slider(
                            value: currentBpm.clamp(40.0, 240.0),
                            min: 40.0,
                            max: 240.0,
                            divisions: 200,
                            activeColor: const Color(0xFFD9F99D),
                            inactiveColor: Colors.white24,
                            onChanged: (val) {
                              setSheetState(() => updateBpm(val.roundToDouble()));
                            },
                          ),
                        ),
                        IconButton.filledTonal(
                          onPressed: () {
                            setSheetState(() => updateBpm(currentBpm + 1));
                          },
                          icon: const Icon(Icons.add, size: 18),
                          style: IconButton.styleFrom(backgroundColor: const Color(0xFF282935), foregroundColor: Colors.white),
                        ),
                        const SizedBox(width: 4),
                        IconButton.filledTonal(
                          onPressed: () {
                            setSheetState(() => updateBpm(currentBpm + 5));
                          },
                          icon: const Text('+5', style: TextStyle(fontWeight: FontWeight.bold)),
                          style: IconButton.styleFrom(backgroundColor: const Color(0xFF282935), foregroundColor: Colors.white),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: OutlinedButton.icon(
                        onPressed: recordTap,
                        icon: const Icon(Icons.touch_app_rounded, size: 18),
                        label: const Text('TAP TEMPO'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFD9F99D),
                          side: const BorderSide(color: Color(0xFFD9F99D)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD9F99D),
                          foregroundColor: const Color(0xFF09090B),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('SELESAI', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
  }

  Widget _buildFallbackArt(double size, Color primary, Color secondary) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primary, secondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          color: Colors.white.withValues(alpha: 0.8),
          size: size * 0.45,
        ),
      ),
    );
  }

  Widget _buildAlbumArtwork(Song song, {double size = 48, double borderRadius = 12, bool showGlow = false}) {
    final hasArt = song.albumArtUrl != null && song.albumArtUrl!.isNotEmpty;
    final primary = AmbianceColorHelper.getPrimaryColor(song);
    final secondary = AmbianceColorHelper.getSecondaryColor(song);

    Widget artImage;
    if (hasArt) {
      if (song.albumArtUrl!.startsWith('http://') || song.albumArtUrl!.startsWith('https://')) {
        artImage = Image.network(
          song.albumArtUrl!,
          fit: BoxFit.cover,
          width: size,
          height: size,
          errorBuilder: (_, _, _) => _buildFallbackArt(size, primary, secondary),
        );
      } else {
        artImage = Image.file(
          File(song.albumArtUrl!),
          fit: BoxFit.cover,
          width: size,
          height: size,
          errorBuilder: (_, _, _) => _buildFallbackArt(size, primary, secondary),
        );
      }
    } else {
      artImage = _buildFallbackArt(size, primary, secondary);
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: showGlow
            ? [
                BoxShadow(
                  color: primary.withValues(alpha: 0.45),
                  blurRadius: 36,
                  offset: const Offset(0, 14),
                  spreadRadius: 2,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: artImage,
      ),
    );
  }


  void _showSongOptionsMenu(BuildContext context, Song song) {
    final library = context.read<LibraryProvider>();
    final isFav = library.isFavorite(song.id);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (modalCtx) {
        return LiquidGlassLens(
          style: const LiquidGlassStyle(
            shape: LiquidGlassShape.roundedRectangle(cornerRadius: 28),
            appearance: LiquidGlassAppearance(
              blur: LiquidGlassBlur(sigmaX: 24, sigmaY: 24),
              color: Color.fromARGB(35, 15, 18, 26),
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            ),
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 18,
              bottom: MediaQuery.of(modalCtx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _buildAlbumArtwork(song, size: 52, borderRadius: 14),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            song.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            song.displayArtist,
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(color: Colors.white12, height: 1),
                const SizedBox(height: 8),

                _buildActionTile(
                  icon: Icons.playlist_add_rounded,
                  title: 'Tambahkan ke Playlist',
                  onTap: () {
                    Navigator.pop(modalCtx);
                    _showAddToPlaylistDialog(context, song);
                  },
                ),
                _buildActionTile(
                  icon: isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  iconColor: isFav ? const Color(0xFFF43F5E) : Colors.white,
                  title: isFav ? 'Hapus dari Disukai' : 'Sukai Lagu (Like)',
                  onTap: () {
                    library.toggleFavorite(song.id);
                    Navigator.pop(modalCtx);
                  },
                ),
                _buildActionTile(
                  icon: Icons.speed_rounded,
                  title: 'Atur Birama & Tempo',
                  onTap: () {
                    Navigator.pop(modalCtx);
                    _showTempoBottomSheet(context, song);
                  },
                ),
                _buildActionTile(
                  icon: Icons.edit_note_rounded,
                  title: 'Edit Chord & Lirik',
                  onTap: () {
                    Navigator.pop(modalCtx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SongEditorScreen(existingSong: song),
                      ),
                    );
                  },
                ),
                _buildActionTile(
                  icon: Icons.share_rounded,
                  title: 'Bagikan Info Lagu',
                  onTap: () {
                    Navigator.pop(modalCtx);
                    Clipboard.setData(ClipboardData(text: '${song.title} - ${song.artist}'));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Info lagu disalin ke clipboard'),
                        backgroundColor: Color(0xFF10B981),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color iconColor = Colors.white,
  }) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        leading: Icon(icon, color: iconColor, size: 22),
        title: Text(
          title,
          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
        ),
        onTap: onTap,
      ),
    );
  }

  void _showAddToPlaylistDialog(BuildContext context, Song song) {
    final library = context.read<LibraryProvider>();
    final playlists = library.playlists;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return LiquidGlassLens(
          style: const LiquidGlassStyle(
            shape: LiquidGlassShape.roundedRectangle(cornerRadius: 28),
            appearance: LiquidGlassAppearance(
              blur: LiquidGlassBlur(sigmaX: 24, sigmaY: 24),
              color: Color(0x520B0C12),
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pilih Playlist',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 14),
                if (playlists.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      'Belum ada playlist. Buat playlist baru di halaman Library.',
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                else
                  for (final pl in playlists)
                    ListTile(
                      leading: const Icon(Icons.queue_music_rounded, color: Color(0xFFD9F99D)),
                      title: Text(pl.name, style: const TextStyle(color: Colors.white)),
                      subtitle: Text('${library.getSongsForPlaylist(pl).length} lagu', style: const TextStyle(color: Colors.white54)),
                      onTap: () {
                        library.addSongToPlaylist(pl.id, song.id);
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Ditambahkan ke playlist "${pl.name}"'),
                            backgroundColor: const Color(0xFF10B981),
                          ),
                        );
                      },
                    ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopHeader(BuildContext context, Song song, PlayerProvider player) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            }
          },
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 28),
          tooltip: 'Minimize',
        ),
        IconButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SongEditorScreen(existingSong: song),
              ),
            );
          },
          icon: const Icon(Icons.edit_note_rounded, color: Colors.white, size: 26),
          tooltip: 'Edit / Add Chords',
        ),
      ],
    );
  }


  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final song = player.currentSong;

    if (song == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF090A0F),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.music_off_rounded, size: 64, color: Color(0xFF52525B)),
              SizedBox(height: 16),
              Text(
                'Tidak ada lagu yang diputar',
                style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      );
    }
 
    if (song.id != _lastSongId) {
      _lastSongId = song.id;
      _lastAutoScrolledIndex = -1;
    }

    final currentChord = player.currentChord;
    final nextChord = player.nextChord;
    final upcomingChord = player.upcomingChord;

    return Scaffold(
      backgroundColor: Colors.black,
      body: ValueListenableBuilder<int>(
        valueListenable: AmbianceColorHelper.colorExtractionNotifier,
        builder: (context, value, child) {
          final primary = AmbianceColorHelper.getPrimaryColor(song);
          final secondary = AmbianceColorHelper.getSecondaryColor(song);

          return SizedBox.expand(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 1. Moving Apple Music style liquid aura background (following cover artwork colors)
                Positioned.fill(
                  child: AppleMusicAuraBackground(
                    primaryColor: primary,
                    secondaryColor: secondary,
                    isPlaying: player.isPlaying,
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Column(
                      children: [
                        // Top Drag Handle Bar (iOS Style Pull-Down)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onVerticalDragUpdate: (details) {
                            if (details.primaryDelta != null && details.primaryDelta! > 5) {
                              if (Navigator.canPop(context)) Navigator.pop(context);
                            }
                          },
                          onVerticalDragEnd: (details) {
                            if (details.primaryVelocity != null && details.primaryVelocity! > 180) {
                              if (Navigator.canPop(context)) Navigator.pop(context);
                            }
                          },
                          child: Center(
                            child: Container(
                              width: 42,
                              height: 4.5,
                              margin: const EdgeInsets.only(top: 6, bottom: 8),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.32),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ),

                        // Top Bar (Minimize + NOW PLAYING + Edit + Queue)
                        _buildTopHeader(context, song, player),
                        const SizedBox(height: 6),

                        // Main Unified Player Content (Integrated Cover, Info, Chords, and Synced Lyrics)
                        Expanded(
                          child: _buildUnifiedPlayerView(
                            context,
                            song,
                            player,
                            currentChord,
                            nextChord,
                            upcomingChord,
                          ),
                        ),

                        const SizedBox(height: 6),

                        // Linear Audio Progress Slider (WaveformWidget)
                        WaveformWidget(
                          progress: player.progress,
                          currentTime: player.currentTimeFormatted,
                          totalTime: player.totalTimeFormatted,
                          onSeek: player.seek,
                          activeColor: AmbianceColorHelper.getPrimaryColor(song),
                        ),

                        // Playback Controls Row (Matching Gambar 1)
                        _buildControlsRow(context, player, song),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildUnifiedPlayerView(
    BuildContext context,
    Song song,
    PlayerProvider player,
    String currentChord,
    String? nextChord,
    String? upcomingChord,
  ) {
    if (_viewMode == PlayerViewMode.chordOverview) {
      return Column(
        children: [
          // Top Control Bar in Overview Mode: Transpose & Switch back to Diagram/Lyrics
          Padding(
            padding: const EdgeInsets.only(bottom: 6, left: 2, right: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Transpose Controls
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Transpose: ',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            shadows: [
                              Shadow(color: Color(0xD9000000), blurRadius: 4, offset: Offset(0, 1)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        _TransposeButton(label: '−', onPressed: player.transposeDown),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            player.transposeOffset > 0 ? '+${player.transposeOffset}' : '${player.transposeOffset}',
                            style: const TextStyle(
                              color: Color(0xFFD9F99D),
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              shadows: [
                                Shadow(color: Color(0xD9000000), blurRadius: 4, offset: Offset(0, 1)),
                              ],
                            ),
                          ),
                        ),
                        _TransposeButton(label: '+', onPressed: player.transposeUp),
                        if (player.transposeOffset != 0) ...[
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: player.resetTranspose,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text('Reset', style: TextStyle(color: Colors.white70, fontSize: 10)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Toggle to return to Diagrams & Lyrics view
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _viewMode = PlayerViewMode.chordDiagrams;
                    });
                  },
                  child: LiquidGlassLens(
                    style: LiquidGlassStyle(
                      shape: const LiquidGlassShape.roundedRectangle(cornerRadius: 8),
                      appearance: LiquidGlassAppearance(
                        blur: const LiquidGlassBlur(sigmaX: 8, sigmaY: 8),
                        color: const Color(0xFFD9F99D).withValues(alpha: 0.15),
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFD9F99D).withValues(alpha: 0.4)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lyrics_rounded, size: 13, color: Color(0xFFD9F99D)),
                          SizedBox(width: 4),
                          Text('Diagram & Lirik', style: TextStyle(color: Color(0xFFD9F99D), fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ChordOverviewGridWidget(
              lines: song.lines,
              positionMs: player.positionMs,
              totalDurationMs: player.durationMs,
              bpm: song.effectiveBpm,
              timeSignature: song.effectiveTimeSignature,
              transposeOffset: player.transposeOffset,
              startBeat: song.effectiveStartBeat,
              startBeatOffsetMs: song.effectiveStartBeatOffsetMs,
              onSeek: (seekMs) => player.seekToMs(seekMs),
            ),
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final lyricItems = _buildLyricItems(song.lines);

        int activeLyricItemIndex = -1;
        for (int i = 0; i < lyricItems.length; i++) {
          final item = lyricItems[i];
          if (item.line.startTimeMs > 0 && player.positionMs >= item.line.startTimeMs) {
            activeLyricItemIndex = i;
          }
        }

        if (activeLyricItemIndex >= 0 && activeLyricItemIndex != _lastAutoScrolledIndex) {
          _lastAutoScrolledIndex = activeLyricItemIndex;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToActiveLyric(activeLyricItemIndex);
          });
        }

        return Column(
          children: [
            // 1. Compact Track Header Row: Corner Album Artwork + Title & Artist + Quick Actions
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              child: Row(
                children: [
                  // Corner album artwork (compact, elegant, with ambient drop shadow, long-press for options)
                  GestureDetector(
                    onLongPress: () => _showSongOptionsMenu(context, song),
                    child: _buildAlbumArtwork(
                      song,
                      size: 54,
                      borderRadius: 12,
                      showGlow: true,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Title and Artist Column
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          song.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                            shadows: [
                              Shadow(
                                color: Color(0xD9000000),
                                blurRadius: 6,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          song.displayArtist,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            shadows: const [
                              Shadow(
                                color: Color(0xD9000000),
                                blurRadius: 6,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Favorite button
                  Builder(
                    builder: (context) {
                      LibraryProvider? lib;
                      try {
                        lib = Provider.of<LibraryProvider>(context, listen: true);
                      } catch (_) {
                        lib = null;
                      }
                      final isFav = lib?.isFavorite(song.id) ?? false;
                      final l = lib;
                      return IconButton(
                        icon: Icon(
                          isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          color: isFav ? const Color(0xFFE11D48) : Colors.white70,
                          size: 22,
                        ),
                        tooltip: isFav ? 'Hapus dari Favorit' : 'Tambah ke Favorit',
                        onPressed: l != null ? () => l.toggleFavorite(song.id) : null,
                        constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                        padding: EdgeInsets.zero,
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),

            // 3. Transpose Controls Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Transpose: ',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            shadows: [
                              Shadow(
                                color: Color(0xD9000000),
                                blurRadius: 4,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        _TransposeButton(label: '−', onPressed: player.transposeDown),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            player.transposeOffset > 0 ? '+${player.transposeOffset}' : '${player.transposeOffset}',
                            style: const TextStyle(
                              color: Color(0xFFD9F99D),
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              shadows: [
                                Shadow(
                                  color: Color(0xD9000000),
                                  blurRadius: 4,
                                  offset: Offset(0, 1),
                                ),
                              ],
                            ),
                          ),
                        ),
                        _TransposeButton(label: '+', onPressed: player.transposeUp),
                        if (player.transposeOffset != 0) ...[
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: player.resetTranspose,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'Reset',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 10,
                                  shadows: [
                                    Shadow(color: Color(0xD9000000), blurRadius: 4, offset: Offset(0, 1)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),

            // Chordify Beat Grid
            ChordifyBeatGridWidget(
              lines: song.lines,
              positionMs: player.positionMs,
              totalDurationMs: player.durationMs,
              bpm: song.effectiveBpm,
              timeSignature: song.effectiveTimeSignature,
              transposeOffset: player.transposeOffset,
              startBeat: song.effectiveStartBeat,
              startBeatOffsetMs: song.effectiveStartBeatOffsetMs,
              onSeek: (seekMs) => player.seekToMs(seekMs),
            ),
            const SizedBox(height: 4),

            // Piano Chord Diagram Strip
            SizedBox(
              height: 72,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    PianoChordDiagramWidget(
                      chordName: currentChord.isNotEmpty
                          ? currentChord
                          : (nextChord != null ? '𝄽' : (song.lines.isEmpty ? '--' : '𝄽')),
                      width: 120,
                      height: 44,
                      isCurrent: true,
                      activeColor: AmbianceColorHelper.getPrimaryColor(song),
                      showChordName: true,
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.arrow_forward_rounded, size: 16, color: Colors.white70),
                    const SizedBox(width: 6),
                    PianoChordDiagramWidget(
                      chordName: nextChord ?? (currentChord.isNotEmpty ? '--' : '𝄽'),
                      width: 120,
                      height: 44,
                      isCurrent: false,
                      showChordName: true,
                    ),
                    if (upcomingChord != null) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.arrow_forward_rounded, size: 14, color: Colors.white54),
                      const SizedBox(width: 6),
                      PianoChordDiagramWidget(
                        chordName: upcomingChord,
                        width: 104,
                        height: 44,
                        isCurrent: false,
                        showChordName: true,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),

            // 4. Lyrics Auto-scrolling List
            Expanded(
              child: lyricItems.isEmpty
                  ? const Center(
                      child: Text(
                        '♪ Musik / Instrumen ♪',
                        style: TextStyle(color: Color(0xFF71717A), fontSize: 15, fontStyle: FontStyle.italic),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, lyricConstraints) {
                        final halfH = lyricConstraints.maxHeight / 2;
                        final maxVPad = halfH > 0 ? halfH : 0.0;
                        final minVPad = 16.0 <= maxVPad ? 16.0 : maxVPad;
                        final vPad = (halfH - 28).clamp(minVPad, maxVPad);

                        return ListView.builder(
                          controller: _lyricsScrollController,
                          // ignore: deprecated_member_use
                          cacheExtent: 2500,
                          physics: const BouncingScrollPhysics(),
                          padding: EdgeInsets.only(top: vPad, bottom: vPad),
                          itemCount: lyricItems.length,
                          itemBuilder: (_, index) {
                            final item = lyricItems[index];
                            final isItemActive = index == activeLyricItemIndex;
                            final isPast = activeLyricItemIndex >= 0 && index < activeLyricItemIndex;
                            final key = _lyricKeys.putIfAbsent(index, () => GlobalKey());

                            return _PureLyricItemWidget(
                              key: key,
                              item: item,
                              isActive: isItemActive,
                              isPast: isPast,
                              positionMs: player.positionMs,
                              onSeek: (seekMs) => player.seekToMs(seekMs),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildControlsRow(BuildContext context, PlayerProvider player, Song song) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 1. Tombol Birama & Tempo (Pod Kaca Terpisah) - Matches Tooltip test
          _SeparateGlassControlButton(
            size: 46,
            tooltip: 'Atur Birama & Tempo',
            onTap: () => _showTempoBottomSheet(context, song),
            child: const Icon(
              Icons.speed_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),

          // 2. Tombol Rewind / Previous
          _SeparateGlassControlButton(
            size: 54,
            tooltip: 'Lagu Sebelumnya',
            onTap: player.previousSong,
            child: const Icon(
              Icons.fast_rewind_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),

          // 3. Tombol Play / Pause Utama (Glowing Radiant Button)
          _buildMainPlayPauseButton(player, song),

          // 4. Tombol Forward / Next
          _SeparateGlassControlButton(
            size: 54,
            tooltip: 'Lagu Berikutnya',
            onTap: player.nextSong,
            child: const Icon(
              Icons.fast_forward_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),

          // 5. Tombol Ganti Diagram / Overview
          _SeparateGlassControlButton(
            size: 46,
            tooltip: _viewMode == PlayerViewMode.chordDiagrams
                ? 'Beralih ke Chord Overview'
                : 'Beralih ke Diagram Piano',
            onTap: () {
              setState(() {
                _viewMode = _viewMode == PlayerViewMode.chordDiagrams
                    ? PlayerViewMode.chordOverview
                    : PlayerViewMode.chordDiagrams;
              });
            },
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
              child: Icon(
                _viewMode == PlayerViewMode.chordDiagrams
                    ? Icons.grid_view_rounded
                    : Icons.piano_rounded,
                key: ValueKey<PlayerViewMode>(_viewMode),
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainPlayPauseButton(PlayerProvider player, Song song) {
    final playGradient = AmbianceColorHelper.getPlayButtonGradient(song);
    final glowColor = AmbianceColorHelper.getPrimaryColor(song);

    return Tooltip(
      message: player.isPlaying ? 'Jeda' : 'Putar',
      child: GestureDetector(
        onTap: player.isLoadingAudio ? null : player.togglePlayPause,
        child: Container(
          width: 66,
          height: 66,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: playGradient,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.55),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: glowColor.withValues(alpha: 0.50),
                blurRadius: 22,
                spreadRadius: 2,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.40),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: player.isLoadingAudio
              ? const Padding(
                  padding: EdgeInsets.all(18.0),
                  child: CircularProgressIndicator(
                    strokeWidth: 2.8,
                    color: Colors.white,
                  ),
                )
              : Icon(
                  player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 38,
                ),
        ),
      ),
    );
  }
}

class _SeparateGlassControlButton extends StatelessWidget {
  final double size;
  final Widget child;
  final VoidCallback? onTap;
  final String tooltip;

  const _SeparateGlassControlButton({
    required this.size,
    required this.child,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: size,
        height: size,
        child: LiquidGlassLens(
          style: LiquidGlassStyle(
            shape: LiquidGlassShape.roundedRectangle(cornerRadius: size / 2),
            appearance: LiquidGlassAppearance(
              blur: const LiquidGlassBlur(sigmaX: 8, sigmaY: 8),
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(size / 2),
              splashColor: const Color(0xFFD9F99D).withValues(alpha: 0.2),
              highlightColor: Colors.white.withValues(alpha: 0.08),
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

class _TransposeButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _TransposeButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 38,
      height: 34,
      child: LiquidGlassLens(
        style: LiquidGlassStyle(
          shape: const LiquidGlassShape.roundedRectangle(cornerRadius: 10),
          appearance: LiquidGlassAppearance(
            blur: const LiquidGlassBlur(sigmaX: 8, sigmaY: 8),
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.15),
              width: 1.0,
            ),
          ),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(10),
            splashColor: const Color(0xFFD9F99D).withValues(alpha: 0.2),
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFD9F99D),
                  shadows: [
                    Shadow(
                      color: Color(0xD9000000),
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DisplayLyricItem {
  final SongLine line;
  final String text;
  final bool isHeader;

  const _DisplayLyricItem({
    required this.line,
    required this.text,
    this.isHeader = false,
  });
}

List<_DisplayLyricItem> _buildLyricItems(List<SongLine> lines) {
  final items = <_DisplayLyricItem>[];
  for (final l in lines) {
    final parsed = ChordParser.parse(l.rawLine);
    final text = parsed.plainText.trim();
    if (text.isEmpty) continue;

    final isHeader = RegExp(r'^(intro|verse|chorus|bridge|outro|interlude)\s*\d*$', caseSensitive: false).hasMatch(text);
    items.add(_DisplayLyricItem(
      line: l,
      text: text,
      isHeader: isHeader,
    ));
  }
  return items;
}

class _PureLyricItemWidget extends StatelessWidget {
  final _DisplayLyricItem item;
  final bool isActive;
  final bool isPast;
  final int positionMs;
  final Function(int seekMs) onSeek;

  const _PureLyricItemWidget({
    super.key,
    required this.item,
    required this.isActive,
    required this.isPast,
    required this.positionMs,
    required this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    if (item.isHeader) {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFD9F99D).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFFD9F99D).withValues(alpha: 0.25),
              width: 0.8,
            ),
          ),
          child: Text(
            item.text.toUpperCase(),
            style: const TextStyle(
              color: Color(0xFFD9F99D),
              fontWeight: FontWeight.bold,
              fontSize: 11,
              letterSpacing: 1.2,
            ),
          ),
        ),
      );
    }

    final lyricStart = item.line.startTimeMs;

    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        margin: EdgeInsets.symmetric(
          vertical: isActive ? 6 : 3,
          horizontal: 12,
        ),
        padding: EdgeInsets.symmetric(
          vertical: isActive ? 10 : 4,
          horizontal: isActive ? 18 : 8,
        ),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFFD9F99D).withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          border: isActive
              ? Border.all(
                  color: const Color(0xFFD9F99D).withValues(alpha: 0.28),
                  width: 1.0,
                )
              : null,
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: const Color(0xFFD9F99D).withValues(alpha: 0.10),
                    blurRadius: 16,
                    spreadRadius: -2,
                  ),
                ]
              : null,
        ),
        child: InkWell(
          onTap: () {
            if (lyricStart > 0) onSeek(lyricStart);
          },
          borderRadius: BorderRadius.circular(16),
          child: AnimatedScale(
            scale: isActive ? 1.06 : 1.0,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
              child: Text(
                item.text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isActive
                      ? const Color(0xFFD9F99D)
                      : (isPast
                          ? Colors.white.withValues(alpha: 0.38)
                          : Colors.white.withValues(alpha: 0.85)),
                  fontSize: isActive ? 22 : 16,
                  fontWeight: isActive
                      ? FontWeight.w800
                      : (isPast ? FontWeight.w500 : FontWeight.w600),
                  height: 1.34,
                  letterSpacing: isActive ? 0.2 : 0.0,
                  shadows: [
                    if (isActive)
                      Shadow(
                        color: const Color(0xFFD9F99D).withValues(alpha: 0.55),
                        blurRadius: 14,
                      ),
                    const Shadow(
                      color: Color(0xE6000000),
                      blurRadius: 6,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
