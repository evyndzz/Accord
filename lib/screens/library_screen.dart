import 'dart:io';
import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';

import '../models/playlist.dart';
import '../models/song.dart';
import '../providers/cosmic_theme_provider.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../services/google_drive_audio_service.dart';
import '../services/google_drive_sync_service.dart';
import '../utils/ambiance_color_helper.dart';
import '../widgets/animated_equalizer.dart';
import '../widgets/apple_music_aura_background.dart';
import '../widgets/liquid_glass_container.dart';
import 'settings_screen.dart';
import 'song_editor_screen.dart';

class LibraryScreen extends StatefulWidget {
  final VoidCallback? onNavigateToPlayer;

  const LibraryScreen({super.key, this.onNavigateToPlayer});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  int _selectedCategoryIndex = 0;

  static const List<Shadow> _textShadows = [
    Shadow(color: Color(0xD9000000), blurRadius: 6, offset: Offset(0, 1)),
  ];

  final List<String> _categories = const [
    'Semua Lagu',
    'Playlist',
    'Lagu Disukai',
  ];

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final driveService = context.watch<GoogleDriveAudioService>();
    final player = context.watch<PlayerProvider>();

    // Build unique master song collection
    final allSongsMap = <String, Song>{};
    for (final s in library.localDeviceSongs) {
      allSongsMap[s.id] = s;
    }
    for (final s in library.allSongs) {
      allSongsMap[s.id] = s;
    }
    for (final s in driveService.driveSongs) {
      allSongsMap[s.id] = s;
    }
    final allCombinedSongs = allSongsMap.values.toList();
    final ambientSong = player.currentSong ?? (allCombinedSongs.isNotEmpty ? allCombinedSongs.first : null);

    // Liked songs list
    final likedSongs = allCombinedSongs.where((s) => library.isFavorite(s.id)).toList();

    // Filter based on active tab
    final List<Song> displayedSongs;
    switch (_selectedCategoryIndex) {
      case 2: // Lagu Disukai
        displayedSongs = likedSongs;
        break;
      case 0: // Semua Lagu
      case 1: // Playlist
      default:
        displayedSongs = allCombinedSongs;
        break;
    }

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
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                // 1. Top Header Bar
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Koleksi Saya',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                              shadows: _textShadows,
                            ),
                          ),
                        ),
                        // Add Song Button
                        LiquidGlassContainer(
                          borderRadius: 20,
                          blur: 14,
                          width: 40,
                          height: 40,
                          padding: EdgeInsets.zero,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const SongEditorScreen(),
                              ),
                            );
                          },
                          child: const Center(
                            child: Icon(
                              Icons.add_rounded,
                              color: Color(0xFFD9F99D),
                              size: 22,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Settings Button
                        LiquidGlassContainer(
                          borderRadius: 20,
                          blur: 14,
                          width: 40,
                          height: 40,
                          padding: EdgeInsets.zero,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const SettingsScreen(),
                              ),
                            );
                          },
                          child: const Center(
                            child: Icon(
                              Icons.settings_outlined,
                              color: Colors.white70,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 2. Category & Playlist Filter Chips
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 12),
                    child: SizedBox(
                      height: 38,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _categories.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final isActive = _selectedCategoryIndex == index;
                          return GestureDetector(
                            onTap: () {
                              setState(() => _selectedCategoryIndex = index);
                            },
                            child: LiquidGlassLens(
                              style: LiquidGlassStyle(
                                shape: const LiquidGlassShape.roundedRectangle(cornerRadius: 20),
                                appearance: LiquidGlassAppearance(
                                  blur: const LiquidGlassBlur(sigmaX: 10, sigmaY: 10),
                                  color: isActive
                                      ? const Color(0x40D9F99D)
                                      : const Color(0x3B12131F),
                                ),
                              ),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isActive
                                        ? const Color(0xFFD9F99D)
                                        : Colors.white.withValues(alpha: 0.14),
                                    width: isActive ? 1.3 : 1.0,
                                  ),
                                  boxShadow: isActive
                                      ? [
                                          BoxShadow(
                                            color: const Color(0xFFD9F99D).withValues(alpha: 0.20),
                                            blurRadius: 8,
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Center(
                                  child: Text(
                                    _categories[index],
                                    style: TextStyle(
                                      color: isActive ? const Color(0xFF09090B) : Colors.white,
                                      fontSize: 13,
                                      fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
                                      shadows: isActive ? null : _textShadows,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),

                // 3. Seamless Songs List / Playlists View
                if (_selectedCategoryIndex == 1) ...[
                  ..._buildPlaylistsSlivers(context, library, player, allCombinedSongs),
                ] else if (displayedSongs.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 60),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(
                              Icons.music_off_rounded,
                              color: Colors.white.withValues(alpha: 0.18),
                              size: 52,
                            ),
                            const SizedBox(height: 14),
                            Text(
                              _selectedCategoryIndex == 2
                                  ? 'Belum ada lagu yang kamu sukai'
                                  : 'Koleksi musik masih kosong',
                              style: const TextStyle(
                                color: Color(0xFFA1A1AA),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.only(left: 20, right: 20, bottom: 160),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final song = displayedSongs[index];
                          final isFav = library.isFavorite(song.id);
                          final isCurrentPlaying = player.currentSong?.id == song.id && player.isPlaying;
                          final isDrive = song.sourceType == 'google_drive' || song.id.startsWith('drive_');

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
                                  player.playSong(song, playlist: displayedSongs);
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
                                                  const [Color(0xFFD9F99D), Color(0xFF65A30D)],
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
                                        onSelected: (val) async {
                                          if (val == 'add_to_playlist') {
                                            _showAddToPlaylistDialog(context, library, song);
                                          } else if (val == 'edit') {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => SongEditorScreen(existingSong: song),
                                              ),
                                            );
                                          } else if (val == 'delete') {
                                            final confirm = await showDialog<bool>(
                                              context: context,
                                              builder: (ctx) => AlertDialog(
                                                backgroundColor: const Color(0xFF22232A),
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                                title: Text(
                                                  isDrive ? 'Hapus Lagu dari Cloud?' : 'Hapus Lagu?',
                                                  style: const TextStyle(color: Colors.white, fontSize: 16),
                                                ),
                                                content: Text(
                                                  isDrive
                                                      ? 'Lagu "${song.title}" akan dipindahkan ke Sampah Google Drive.'
                                                      : 'Hapus lagu "${song.title}" dari penyimpanan lokal?',
                                                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () => Navigator.pop(ctx, false),
                                                    child: const Text('Batal', style: TextStyle(color: Colors.white54)),
                                                  ),
                                                  ElevatedButton(
                                                    onPressed: () => Navigator.pop(ctx, true),
                                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                                    child: const Text('Hapus', style: TextStyle(color: Colors.white)),
                                                  ),
                                                ],
                                              ),
                                            );

                                            if (confirm == true && context.mounted) {
                                              if (isDrive) {
                                                await driveService.deleteDriveSong(
                                                  song.id,
                                                  syncService: context.read<GoogleDriveSyncService>(),
                                                );
                                              } else {
                                                await library.deleteLocalSong(song.id);
                                              }
                                            }
                                          }
                                        },
                                        itemBuilder: (ctx) => [
                                          const PopupMenuItem(
                                            value: 'add_to_playlist',
                                            child: Row(
                                              children: [
                                                Icon(Icons.playlist_add_rounded, color: Color(0xFFD9F99D), size: 18),
                                                SizedBox(width: 8),
                                                Text('Tambah ke Playlist', style: TextStyle(color: Colors.white, fontSize: 13)),
                                              ],
                                            ),
                                          ),
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
                        childCount: displayedSongs.length,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPlaylistsSlivers(
    BuildContext context,
    LibraryProvider library,
    PlayerProvider player,
    List<Song> allCombinedSongs,
  ) {
    final playlists = library.playlists;

    return [
      // Quick Action Button: Create New Playlist
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: LiquidGlassContainer(
            borderRadius: 20,
            blur: 8,
            onTap: () => _showCreatePlaylistDialog(context, library),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFFD9F99D), Color(0xFF65A30D)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFD9F99D).withValues(alpha: 0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      color: Color(0xFF09090B),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Buat Playlist Baru',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Kelompokkan lagu favoritmu dalam satu wadah',
                          style: TextStyle(
                            color: Color(0xFFA1A1AA),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

      if (playlists.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 40),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Icons.queue_music_rounded,
                    color: Colors.white.withValues(alpha: 0.2),
                    size: 56,
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Belum Ada Playlist',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Tekan "Buat Playlist Baru" di atas untuk memulai',
                    style: TextStyle(
                      color: Color(0xFFA1A1AA),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.only(left: 20, right: 20, bottom: 160),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final playlist = playlists[index];
                final plSongs = library.getSongsForPlaylist(playlist);

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: LiquidGlassContainer(
                    borderRadius: 20,
                    blur: 8,
                    padding: EdgeInsets.zero,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => _showPlaylistDetailBottomSheet(
                        context,
                        library,
                        player,
                        playlist,
                        allCombinedSongs,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                      children: [
                        // Astronomy Logo with Glow
                        CosmicThemeProvider.buildEmblemForId(playlist.logoId, size: 48),
                        const SizedBox(width: 14),
                        // Playlist Name & Songs Count
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                playlist.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${plSongs.length} Lagu',
                                style: const TextStyle(
                                  color: Color(0xFFA1A1AA),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Play Playlist Button with Depth
                        if (plSongs.isNotEmpty) ...[
                          GestureDetector(
                            onTap: () {
                              player.playSong(plSongs.first, playlist: plSongs);
                              widget.onNavigateToPlayer?.call();
                            },
                            child: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFD9F99D), Color(0xFF65A30D)],
                                ),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.45),
                                  width: 1.2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFD9F99D).withValues(alpha: 0.45),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.play_arrow_rounded,
                                color: Color(0xFF09090B),
                                size: 24,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        // Delete Playlist Button
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38, size: 20),
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: const Color(0xFF22232A),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                title: const Text('Hapus Playlist?', style: TextStyle(color: Colors.white, fontSize: 16)),
                                content: Text(
                                  'Hapus "${playlist.name}"? Lagu di dalamnya tidak akan terhapus dari koleksi.',
                                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Batal', style: TextStyle(color: Colors.white54)),
                                  ),
                                  ElevatedButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                    child: const Text('Hapus', style: TextStyle(color: Colors.white)),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              await library.deletePlaylist(playlist.id);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
              childCount: playlists.length,
            ),
          ),
        ),
    ];
  }

  void _showCreatePlaylistDialog(BuildContext context, LibraryProvider library) {
    final controller = TextEditingController();
    String selectedLogoId = 'saturn_orbit';

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF161822),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
          ),
          title: const Text(
            'Buat Playlist Baru',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Nama playlist...',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFD9F99D), width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Pilih Lambang Astronomi:',
                  style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 84,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: CosmicThemeProvider.options.length,
                    separatorBuilder: (context, index) => const SizedBox(width: 8),
                    itemBuilder: (c, i) {
                      final opt = CosmicThemeProvider.options[i];
                      final isSelected = opt.id == selectedLogoId;
                      return GestureDetector(
                        onTap: () => setDialogState(() => selectedLogoId = opt.id),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFFD9F99D).withValues(alpha: 0.15)
                                : Colors.white.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSelected ? const Color(0xFFD9F99D) : Colors.white12,
                              width: isSelected ? 1.6 : 1,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CosmicThemeProvider.buildEmblemForId(opt.id, size: 36),
                              const SizedBox(height: 4),
                              Text(
                                opt.name,
                                style: TextStyle(
                                  color: isSelected ? const Color(0xFFD9F99D) : Colors.white60,
                                  fontSize: 10,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Batal', style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD9F99D),
                foregroundColor: const Color(0xFF09090B),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  await library.createPlaylist(name, logoId: selectedLogoId);
                  if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                }
              },
              child: const Text('Buat', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showPlaylistDetailBottomSheet(
    BuildContext context,
    LibraryProvider library,
    PlayerProvider player,
    Playlist playlist,
    List<Song> allSongs,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final currentPl = library.playlists.firstWhere(
              (p) => p.id == playlist.id,
              orElse: () => playlist,
            );
            final plSongs = library.getSongsForPlaylist(currentPl);

            return LiquidGlassLens(
              style: const LiquidGlassStyle(
                shape: LiquidGlassShape.roundedRectangle(cornerRadius: 32),
                appearance: LiquidGlassAppearance(
                  blur: LiquidGlassBlur(sigmaX: 24, sigmaY: 24),
                  color: Color(0x520B0C12),
                ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
                ),
                height: MediaQuery.of(context).size.height * 0.75,
                child: Column(
                  children: [
                    // Handle
                    Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 8),
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    // Header
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () => _showPickAstronomyLogoForPlaylistModal(
                              context,
                              library,
                              currentPl,
                              () => setModalState(() {}),
                            ),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                CosmicThemeProvider.buildEmblemForId(currentPl.logoId, size: 48),
                                Positioned(
                                  right: -2,
                                  bottom: -2,
                                  child: Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1E293B),
                                      shape: BoxShape.circle,
                                      border: Border.all(color: const Color(0xFFD9F99D), width: 1.2),
                                    ),
                                    child: const Icon(Icons.edit_rounded, size: 10, color: Color(0xFFD9F99D)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  currentPl.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${plSongs.length} Lagu',
                                  style: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                          // Change Logo Button
                          IconButton(
                            tooltip: 'Ganti Lambang Astronomi',
                            icon: const Icon(Icons.auto_awesome_rounded, color: Colors.white70, size: 22),
                            onPressed: () => _showPickAstronomyLogoForPlaylistModal(
                              context,
                              library,
                              currentPl,
                              () => setModalState(() {}),
                            ),
                          ),
                          // Add Song Button
                          IconButton(
                            tooltip: 'Tambah Lagu',
                            icon: const Icon(Icons.add_circle_outline_rounded, color: Color(0xFFD9F99D), size: 28),
                            onPressed: () => _showAddSongsToPlaylistDialog(context, library, currentPl, allSongs, () {
                              setModalState(() {});
                            }),
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: Colors.white12, height: 1),
                    // Songs List in Playlist
                    Expanded(
                      child: plSongs.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text(
                                    'Playlist ini masih kosong',
                                    style: TextStyle(color: Colors.white60, fontSize: 14),
                                  ),
                                  const SizedBox(height: 10),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFD9F99D),
                                      foregroundColor: const Color(0xFF09090B),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    ),
                                    icon: const Icon(Icons.add_rounded, size: 18),
                                    label: const Text('Tambah Lagu'),
                                    onPressed: () => _showAddSongsToPlaylistDialog(context, library, currentPl, allSongs, () {
                                      setModalState(() {});
                                    }),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: plSongs.length,
                              itemBuilder: (ctx, idx) {
                                final song = plSongs[idx];
                                return ListTile(
                                  leading: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      width: 44,
                                      height: 44,
                                      color: const Color(0xFF22232A),
                                      child: (song.albumArtUrl != null && song.albumArtUrl!.isNotEmpty)
                                          ? ((song.albumArtUrl!.startsWith('http://') || song.albumArtUrl!.startsWith('https://'))
                                              ? Image.network(
                                                  song.albumArtUrl!,
                                                  width: 44,
                                                  height: 44,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (context, error, stackTrace) => const Icon(
                                                    Icons.music_note_rounded,
                                                    color: Colors.white38,
                                                  ),
                                                )
                                              : Image.file(
                                                  File(song.albumArtUrl!),
                                                  width: 44,
                                                  height: 44,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (context, error, stackTrace) => const Icon(
                                                    Icons.music_note_rounded,
                                                    color: Colors.white38,
                                                  ),
                                                ))
                                          : const Icon(Icons.music_note_rounded, color: Colors.white38),
                                    ),
                                  ),
                                  title: Text(
                                    song.title,
                                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    song.displayArtist,
                                    style: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 12),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.remove_circle_outline_rounded, color: Colors.redAccent, size: 20),
                                    onPressed: () async {
                                      await library.removeSongFromPlaylist(currentPl.id, song.id);
                                      setModalState(() {});
                                    },
                                  ),
                                  onTap: () {
                                    player.playSong(song, playlist: plSongs);
                                    Navigator.pop(sheetCtx);
                                    widget.onNavigateToPlayer?.call();
                                  },
                                );
                              },
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

  void _showAddSongsToPlaylistDialog(
    BuildContext context,
    LibraryProvider library,
    Playlist playlist,
    List<Song> allSongs,
    VoidCallback onUpdated,
  ) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1C26),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Tambah Lagu ke Playlist', style: TextStyle(color: Colors.white, fontSize: 16)),
          content: SizedBox(
            width: double.maxFinite,
            height: 350,
            child: allSongs.isEmpty
                ? const Center(child: Text('Tidak ada lagu yang tersedia', style: TextStyle(color: Colors.white60)))
                : ListView.builder(
                    itemCount: allSongs.length,
                    itemBuilder: (_, idx) {
                      final s = allSongs[idx];
                      final isAlreadyAdded = playlist.songIds.contains(s.id);

                      return ListTile(
                        dense: true,
                        title: Text(s.title, style: const TextStyle(color: Colors.white, fontSize: 13)),
                        subtitle: Text(s.artist, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                        trailing: Icon(
                          isAlreadyAdded ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
                          color: isAlreadyAdded ? const Color(0xFFD9F99D) : Colors.white38,
                          size: 20,
                        ),
                        onTap: () async {
                          if (!isAlreadyAdded) {
                            await library.addSongToPlaylist(playlist.id, s.id);
                            onUpdated();
                            if (ctx.mounted) Navigator.pop(ctx);
                          }
                        },
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Tutup', style: TextStyle(color: Colors.white60)),
            ),
          ],
        );
      },
    );
  }

  void _showPickAstronomyLogoForPlaylistModal(
    BuildContext context,
    LibraryProvider library,
    Playlist playlist,
    VoidCallback onUpdated,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (modalCtx) {
        return LiquidGlassLens(
          style: const LiquidGlassStyle(
            shape: LiquidGlassShape.roundedRectangle(cornerRadius: 32),
            appearance: LiquidGlassAppearance(
              blur: LiquidGlassBlur(sigmaX: 24, sigmaY: 24),
              color: Color(0x520B0C12),
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
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
                    const SizedBox(height: 14),
                Row(
                  children: [
                    const Icon(Icons.auto_awesome_rounded, color: Color(0xFFD9F99D), size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'Pilih Lambang Astronomi',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white60, size: 20),
                      onPressed: () => Navigator.pop(modalCtx),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Kustomisasi lambang untuk playlist "${playlist.name}":',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: CosmicThemeProvider.options.map((opt) {
                      final isSelected = opt.id == playlist.logoId;
                      return InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () async {
                          await library.updatePlaylistLogo(playlist.id, opt.id);
                          onUpdated();
                          if (modalCtx.mounted) Navigator.pop(modalCtx);
                        },
                        child: Container(
                          width: 96,
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFFD9F99D).withValues(alpha: 0.15)
                                : Colors.white.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected ? const Color(0xFFD9F99D) : Colors.white12,
                              width: isSelected ? 1.6 : 1,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CosmicThemeProvider.buildEmblemForId(opt.id, size: 38),
                              const SizedBox(height: 6),
                              Text(
                                opt.name,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: isSelected ? const Color(0xFFD9F99D) : Colors.white70,
                                  fontSize: 11,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
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

  void _showAddToPlaylistDialog(BuildContext context, LibraryProvider library, Song song) {
    final playlists = library.playlists;
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1C26),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
          ),
          title: const Text('Tambah ke Playlist', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (playlists.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('Belum ada playlist. Buat terlebih dahulu:', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: playlists.length,
                      itemBuilder: (_, i) {
                        final pl = playlists[i];
                        final isAdded = pl.songIds.contains(song.id);
                        return ListTile(
                          dense: true,
                          leading: CosmicThemeProvider.buildEmblemForId(pl.logoId, size: 28),
                          title: Text(pl.name, style: const TextStyle(color: Colors.white, fontSize: 14)),
                          trailing: isAdded
                              ? const Icon(Icons.check_rounded, color: Color(0xFFD9F99D), size: 20)
                              : const Icon(Icons.add_rounded, color: Colors.white54, size: 20),
                          onTap: () async {
                            if (!isAdded) {
                              await library.addSongToPlaylist(pl.id, song.id);
                            }
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Ditambahkan ke "${pl.name}"'),
                                  duration: const Duration(seconds: 2),
                                  backgroundColor: const Color(0xFF1E293B),
                                ),
                              );
                            }
                          },
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFD9F99D),
                    side: const BorderSide(color: Color(0xFFD9F99D)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Buat Playlist Baru'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showCreatePlaylistDialog(context, library);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal', style: TextStyle(color: Colors.white60)),
            ),
          ],
        );
      },
    );
  }
}

