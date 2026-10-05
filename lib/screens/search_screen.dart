import 'dart:io';
import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../services/google_drive_audio_service.dart';
import '../utils/ambiance_color_helper.dart';
import '../widgets/animated_equalizer.dart';
import '../widgets/apple_music_aura_background.dart';
import 'song_editor_screen.dart';

class SearchScreen extends StatefulWidget {
  final VoidCallback? onNavigateToPlayer;

  const SearchScreen({super.key, this.onNavigateToPlayer});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String _activeQuery = '';
  List<String> _searchHistory = [];
  static const String _prefHistoryKey = 'accord_search_history_v1';

  static const List<Shadow> _textShadows = [
    Shadow(color: Color(0xD9000000), blurRadius: 6, offset: Offset(0, 1)),
  ];

  final List<String> _quickSuggestions = const [
    'Praise & Worship',
    'Akustik',
    'Chord & Lirik',
    'Google Drive',
    'GMS Live',
  ];

  @override
  void initState() {
    super.initState();
    _loadSearchHistory();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_prefHistoryKey) ?? [];
    if (mounted) {
      setState(() {
        _searchHistory = list;
      });
    }
  }

  Future<void> _addSearchQueryToHistory(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    final updated = List<String>.from(_searchHistory);
    updated.remove(trimmed);
    updated.insert(0, trimmed);
    if (updated.length > 15) {
      updated.removeRange(15, updated.length);
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefHistoryKey, updated);
    if (mounted) {
      setState(() {
        _searchHistory = updated;
      });
    }
  }

  Future<void> _removeHistoryItem(String query) async {
    final updated = List<String>.from(_searchHistory)..remove(query);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefHistoryKey, updated);
    if (mounted) {
      setState(() {
        _searchHistory = updated;
      });
    }
  }

  Future<void> _clearAllHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefHistoryKey);
    if (mounted) {
      setState(() {
        _searchHistory = [];
      });
    }
  }

  void _applySearch(String query) {
    _controller.text = query;
    _controller.selection = TextSelection.fromPosition(TextPosition(offset: query.length));
    setState(() {
      _activeQuery = query;
    });
    _addSearchQueryToHistory(query);
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final driveAudio = context.watch<GoogleDriveAudioService>();
    final player = context.watch<PlayerProvider>();

    // Combine all songs across sources (library.allSongs has user edits and takes precedence)
    final allSongsMap = <String, Song>{};
    for (final s in driveAudio.driveSongs) {
      allSongsMap[s.id] = s;
    }
    for (final s in library.localDeviceSongs) {
      allSongsMap[s.id] = s;
    }
    for (final s in library.allSongs) {
      allSongsMap[s.id] = s;
    }
    final allSongs = allSongsMap.values.toList();
    final ambientSong = player.currentSong ?? (allSongs.isNotEmpty ? allSongs.first : null);

    final q = _activeQuery.trim().toLowerCase();
    final results = q.isEmpty
        ? <Song>[]
        : allSongs.where((s) {
            final titleMatch = s.title.toLowerCase().contains(q);
            final artistMatch = s.artist.toLowerCase().contains(q);
            return titleMatch || artistMatch;
          }).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Dynamic Wavy Apple Music Aura Background
          Positioned.fill(
            child: ValueListenableBuilder<int>(
              valueListenable: AmbianceColorHelper.colorExtractionNotifier,
              builder: (context, value, child) {
                final primary = AmbianceColorHelper.getPrimaryColor(ambientSong);
                final secondary = AmbianceColorHelper.getSecondaryColor(ambientSong);
                return AppleMusicAuraBackground(
                  primaryColor: primary,
                  secondaryColor: secondary,
                  isPlaying: player.isPlaying,
                  vignetteOpacity: 0.20,
                );
              },
            ),
          ),

          SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Header Bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Pencarian',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                            shadows: _textShadows,
                          ),
                        ),
                      ),
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.08),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15),
                          ),
                        ),
                        child: const Icon(
                          Icons.search_rounded,
                          color: Color(0xFFD9F99D),
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),

                // 2. Search Input Field ("Mau search lagu apa...")
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: LiquidGlassLens(
                    style: const LiquidGlassStyle(
                      shape: LiquidGlassShape.roundedRectangle(cornerRadius: 26),
                      appearance: LiquidGlassAppearance(
                        blur: LiquidGlassBlur(sigmaX: 14, sigmaY: 14),
                        color: Color(0x3D10111D),
                      ),
                    ),
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(
                          color: _activeQuery.isNotEmpty
                              ? const Color(0xFFD9F99D).withValues(alpha: 0.50)
                              : Colors.white.withValues(alpha: 0.15),
                          width: 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.search_rounded,
                            color: Color(0xFFD9F99D),
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              focusNode: _focusNode,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                shadows: _textShadows,
                              ),
                              onChanged: (val) {
                                setState(() => _activeQuery = val);
                              },
                              onSubmitted: (val) {
                                _addSearchQueryToHistory(val);
                              },
                              decoration: const InputDecoration(
                                hintText: 'Mau search lagu apa...',
                                hintStyle: TextStyle(
                                  color: Color(0xFFA1A1AA),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                ),
                                border: InputBorder.none,
                                isDense: true,
                              ),
                            ),
                          ),
                          if (_activeQuery.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                _controller.clear();
                                setState(() => _activeQuery = '');
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(6),
                                child: Icon(
                                  Icons.close_rounded,
                                  color: Colors.white.withValues(alpha: 0.6),
                                  size: 18,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // 3. Body: Either Search History or Search Results
                Expanded(
                  child: _activeQuery.isEmpty
                      ? _buildSearchHistoryView()
                      : _buildSearchResultsView(results, player, library),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Search History & Suggestions ──────────────────────────────────────────

  Widget _buildSearchHistoryView() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 160),
      children: [
        // History Section Header
        if (_searchHistory.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.history_rounded,
                    color: Color(0xFFD9F99D),
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Riwayat Pencarian',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      shadows: _textShadows,
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: _clearAllHistory,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                  child: Text(
                    'Hapus Semua',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      shadows: _textShadows,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // History Chips Wrap
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _searchHistory.map((query) {
              return GestureDetector(
                onTap: () => _applySearch(query),
                child: LiquidGlassLens(
                  style: const LiquidGlassStyle(
                    shape: LiquidGlassShape.roundedRectangle(cornerRadius: 20),
                    appearance: LiquidGlassAppearance(
                      blur: LiquidGlassBlur(sigmaX: 10, sigmaY: 10),
                      color: Color(0x3B12131F),
                    ),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.history_rounded,
                          color: Colors.white60,
                          size: 14,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          query,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            shadows: _textShadows,
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => _removeHistoryItem(query),
                          child: Icon(
                            Icons.close_rounded,
                            color: Colors.white.withValues(alpha: 0.5),
                            size: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 28),
        ],

        // Suggestions / Discovery Section
        const Row(
          children: [
            Icon(
              Icons.explore_outlined,
              color: Color(0xFFD9F99D),
              size: 18,
            ),
            SizedBox(width: 8),
            Text(
              'Rekomendasi Pencarian',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                shadows: _textShadows,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _quickSuggestions.map((suggestion) {
            return GestureDetector(
              onTap: () => _applySearch(suggestion),
              child: LiquidGlassLens(
                style: const LiquidGlassStyle(
                  shape: LiquidGlassShape.roundedRectangle(cornerRadius: 20),
                  appearance: LiquidGlassAppearance(
                    blur: LiquidGlassBlur(sigmaX: 10, sigmaY: 10),
                    color: Color(0x3B12131F),
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.music_note_rounded,
                        color: Color(0xFFD9F99D),
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        suggestion,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          shadows: _textShadows,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),

        if (_searchHistory.isEmpty) ...[
          const SizedBox(height: 50),
          Center(
            child: Column(
              children: [
                Icon(
                  Icons.search_rounded,
                  color: Colors.white.withValues(alpha: 0.15),
                  size: 56,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Ketik lagu apa yang ingin kamu dengarkan',
                  style: TextStyle(
                    color: Color(0xFFA1A1AA),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ── Seamless Search Results List ──────────────────────────────────────────

  Widget _buildSearchResultsView(
    List<Song> results,
    PlayerProvider player,
    LibraryProvider library,
  ) {
    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              color: Colors.white.withValues(alpha: 0.2),
              size: 56,
            ),
            const SizedBox(height: 14),
            Text(
              'Tidak ditemukan lagu untuk "$_activeQuery"',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Coba periksa ejaan atau cari kata kunci lain',
              style: TextStyle(
                color: Color(0xFFA1A1AA),
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 160),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final song = results[index];
        final isFav = library.isFavorite(song.id);
        final isCurrentPlaying = player.currentSong?.id == song.id && player.isPlaying;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Material(
            color: isCurrentPlaying
                ? const Color(0xFFD9F99D).withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              splashColor: const Color(0xFFD9F99D).withValues(alpha: 0.12),
              highlightColor: Colors.white.withValues(alpha: 0.04),
              onTap: () {
                _addSearchQueryToHistory(_activeQuery);
                player.playSong(song, playlist: results);
                widget.onNavigateToPlayer?.call();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Row(
                  children: [
                    // Album Thumbnail
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: song.gradientColors ??
                                const [Color(0xFFD9F99D), Color(0xFF84CC16)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (song.albumArtUrl != null && song.albumArtUrl!.isNotEmpty)
                              (song.albumArtUrl!.startsWith('http://') || song.albumArtUrl!.startsWith('https://'))
                                  ? Image.network(
                                      song.albumArtUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => const Icon(
                                        Icons.music_note_rounded,
                                        color: Colors.white60,
                                      ),
                                    )
                                  : Image.file(
                                      File(song.albumArtUrl!),
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => const Icon(
                                        Icons.music_note_rounded,
                                        color: Colors.white60,
                                      ),
                                    )
                            else
                              const Center(
                                child: Icon(
                                  Icons.music_note_rounded,
                                  color: Colors.white60,
                                ),
                              ),
                            if (isCurrentPlaying) ...[
                              Container(
                                color: Colors.black.withValues(alpha: 0.52),
                              ),
                              const Center(
                                child: AnimatedEqualizer(
                                  color: Color(0xFFD9F99D),
                                  maxHeight: 18,
                                  barWidth: 3.2,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),

                    // Title & Artist
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            song.title,
                            style: TextStyle(
                              color: isCurrentPlaying
                                  ? const Color(0xFFD9F99D)
                                  : Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                              shadows: _textShadows,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            song.displayArtist,
                            style: const TextStyle(
                              color: Color(0xFFA1A1AA),
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              shadows: _textShadows,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),

                    // More Options Button (...)
                    PopupMenuButton<String>(
                      icon: const Icon(
                        Icons.more_horiz_rounded,
                        color: Colors.white70,
                        size: 22,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      color: const Color(0xFF18181F),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.15),
                        ),
                      ),
                      onSelected: (val) {
                        if (val == 'edit') {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SongEditorScreen(existingSong: song),
                            ),
                          );
                        } else if (val == 'delete') {
                          library.deleteLocalSong(song.id);
                        }
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit_note_rounded, color: Color(0xFFD9F99D), size: 18),
                              SizedBox(width: 8),
                              Text('Edit Chord & Lirik', style: TextStyle(color: Colors.white, fontSize: 13)),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                              SizedBox(width: 8),
                              Text('Hapus Lagu', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 14),

                    // Heart / Favorite Icon Button
                    GestureDetector(
                      onTap: () => library.toggleFavorite(song.id),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Icon(
                          isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          color: isFav ? const Color(0xFFD9F99D) : Colors.white38,
                          size: 22,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
