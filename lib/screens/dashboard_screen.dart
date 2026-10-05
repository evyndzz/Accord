import 'dart:io';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/playlist.dart';
import '../models/song.dart';
import '../providers/cosmic_theme_provider.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../providers/profile_provider.dart';
import '../services/google_drive_audio_service.dart';
import '../services/google_drive_sync_service.dart';
import '../utils/ambiance_color_helper.dart';
import '../widgets/animated_equalizer.dart';
import '../widgets/apple_music_aura_background.dart';
import '../widgets/liquid_glass_container.dart';
import 'settings_screen.dart';
import 'song_editor_screen.dart';

class DashboardScreen extends StatefulWidget {
  final VoidCallback? onNavigateToPlayer;

  const DashboardScreen({super.key, this.onNavigateToPlayer});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedFilterIndex = 0;
  final List<String> _filters = const [
    'Semua Lagu',
    'Chord & Lirik',
    'Tanpa Chord & Lirik',
  ];

  static const List<Shadow> _textShadows = [
    Shadow(color: Color(0xD9000000), blurRadius: 6, offset: Offset(0, 1)),
  ];

  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final driveAudio = context.read<GoogleDriveAudioService>();
      final library = context.read<LibraryProvider>();
      final driveSync = context.read<GoogleDriveSyncService>();

      driveAudio.loadDriveSongs();
      library.refreshLocalSongs();

      if (driveSync.isConfigured && !Platform.environment.containsKey('FLUTTER_TEST')) {
        driveSync.syncVault(silent: true).then((ok) {
          if (ok && mounted) {
            driveAudio.loadDriveSongs();
            library.refreshLocalSongs();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  List<Song> _getFilteredSongs(
    List<Song> allSongs,
    int filterIndex,
  ) {
    switch (filterIndex) {
      case 1: // Chord & Lirik
        return allSongs.where((s) => s.lines.isNotEmpty).toList();
      case 2: // Tanpa Chord & Lirik
        return allSongs.where((s) => s.lines.isEmpty).toList();
      case 0: // Semua Lagu
      default:
        return allSongs;
    }
  }

  void _showProfileModal(BuildContext context) {
    final profile = context.read<ProfileProvider>();
    final nameController = TextEditingController(text: profile.name);
    String selectedAvatarId = profile.avatarId;
    String? selectedCustomImagePath = profile.customImagePath;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final hasCustomImage = selectedCustomImagePath != null &&
                selectedCustomImagePath!.isNotEmpty &&
                File(selectedCustomImagePath!).existsSync();

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
                padding: EdgeInsets.only(
                  left: 24,
                  right: 24,
                  top: 20,
                  bottom: MediaQuery.of(modalContext).viewInsets.bottom + 28,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // iOS Drag Handle
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 18),
                      // Header Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Edit Profil',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: Colors.white60),
                            onPressed: () => Navigator.pop(modalContext),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Avatar Preview with Camera Overlay
                      Center(
                        child: GestureDetector(
                          onTap: () async {
                            final newPath = await profile.pickAndSaveCustomImage();
                            if (newPath != null) {
                              setModalState(() {
                                selectedCustomImagePath = newPath;
                              });
                            }
                          },
                          child: Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              Container(
                                width: 88,
                                height: 88,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(0xFFD9F99D),
                                    width: 2.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFD9F99D).withValues(alpha: 0.35),
                                      blurRadius: 18,
                                    ),
                                  ],
                                ),
                                child: ClipOval(
                                  child: hasCustomImage
                                      ? Image.file(
                                          File(selectedCustomImagePath!),
                                          fit: BoxFit.cover,
                                          width: 88,
                                          height: 88,
                                        )
                                      : Builder(
                                          builder: (_) {
                                            final opt = ProfileProvider.avatarOptions.firstWhere(
                                              (o) => o.id == selectedAvatarId,
                                              orElse: () => ProfileProvider.avatarOptions.first,
                                            );
                                            return Container(
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  colors: opt.gradient,
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                ),
                                              ),
                                              child: Icon(opt.icon, color: Colors.white, size: 44),
                                            );
                                          },
                                        ),
                                ),
                              ),
                              // Floating Camera Badge
                              Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFD9F99D),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: const Color(0xFF141419), width: 2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.5),
                                      blurRadius: 6,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.camera_alt_rounded,
                                  color: Color(0xFF09090B),
                                  size: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Button to Pick Photo or Reset to Cosmic Avatar
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton.icon(
                            onPressed: () async {
                              final newPath = await profile.pickAndSaveCustomImage();
                              if (newPath != null) {
                                setModalState(() {
                                  selectedCustomImagePath = newPath;
                                });
                              }
                            },
                            icon: const Icon(Icons.photo_library_rounded, size: 16, color: Color(0xFFD9F99D)),
                            label: Text(
                              hasCustomImage ? 'Ganti Foto' : 'Upload Foto Sendiri',
                              style: const TextStyle(
                                color: Color(0xFFD9F99D),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: TextButton.styleFrom(
                              backgroundColor: const Color(0xFFD9F99D).withValues(alpha: 0.12),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            ),
                          ),
                          if (hasCustomImage) ...[
                            const SizedBox(width: 8),
                            TextButton.icon(
                              onPressed: () {
                                setModalState(() {
                                  selectedCustomImagePath = null;
                                });
                              },
                              icon: const Icon(Icons.refresh_rounded, size: 16, color: Colors.white70),
                              label: const Text(
                                'Pakai Avatar',
                                style: TextStyle(color: Colors.white70, fontSize: 13),
                              ),
                              style: TextButton.styleFrom(
                                backgroundColor: Colors.white.withValues(alpha: 0.08),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Name Input Field
                      TextField(
                        controller: nameController,
                        style: const TextStyle(color: Colors.white, fontSize: 15),
                        decoration: InputDecoration(
                          labelText: 'Nama Pengguna',
                          labelStyle: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 13),
                          prefixIcon: const Icon(Icons.person_outline_rounded, color: Color(0xFFD9F99D), size: 20),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.07),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: Color(0xFFD9F99D), width: 1.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Avatar Options Grid
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Pilih Avatar Kosmik',
                          style: TextStyle(
                            color: Color(0xFFA1A1AA),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 76,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: ProfileProvider.avatarOptions.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 12),
                          itemBuilder: (ctx, idx) {
                            final opt = ProfileProvider.avatarOptions[idx];
                            final isSelected = !hasCustomImage && opt.id == selectedAvatarId;
                            return GestureDetector(
                              onTap: () {
                                setModalState(() {
                                  selectedAvatarId = opt.id;
                                  selectedCustomImagePath = null;
                                });
                              },
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: LinearGradient(
                                        colors: opt.gradient,
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      border: Border.all(
                                        color: isSelected ? const Color(0xFFD9F99D) : Colors.transparent,
                                        width: isSelected ? 2.5 : 0,
                                      ),
                                      boxShadow: isSelected
                                          ? [
                                              BoxShadow(
                                                color: const Color(0xFFD9F99D).withValues(alpha: 0.45),
                                                blurRadius: 12,
                                                spreadRadius: 1,
                                              ),
                                            ]
                                          : null,
                                    ),
                                    child: Icon(opt.icon, color: Colors.white, size: 24),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    opt.name,
                                    style: TextStyle(
                                      color: isSelected ? Colors.white : Colors.white60,
                                      fontSize: 10,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Save Button (Liquid neon lime pill)
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () async {
                            final newName = nameController.text.trim();
                            await profile.updateProfile(
                              newName: newName,
                              newAvatarId: selectedAvatarId,
                              newCustomImagePath: selectedCustomImagePath,
                            );
                            if (modalContext.mounted) {
                              Navigator.pop(modalContext);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Profil berhasil diperbarui!'),
                                  backgroundColor: Color(0xFF10B981),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFD9F99D),
                            foregroundColor: const Color(0xFF09090B),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            'Simpan Profil',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Settings Shortcut
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(modalContext);
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const SettingsScreen()),
                          );
                        },
                        icon: const Icon(Icons.settings_outlined, color: Colors.white60, size: 18),
                        label: const Text(
                          'Pengaturan Aplikasi',
                          style: TextStyle(color: Colors.white60, fontSize: 13),
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

  void _showDriveVaultSetupDialog(BuildContext context) {
    final driveSync = context.read<GoogleDriveSyncService>();
    final urlController = TextEditingController(text: driveSync.bridgeUrl ?? '');
    String? localError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
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
                padding: EdgeInsets.only(
                  left: 24,
                  right: 24,
                  top: 24,
                  bottom: MediaQuery.of(bottomSheetContext).viewInsets.bottom + 28,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD9F99D).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.cloud_sync_rounded, color: Color(0xFFD9F99D), size: 28),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Google Drive Vault',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Penyimpanan Cloud Musik & Chord',
                                  style: TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(bottomSheetContext),
                            icon: const Icon(Icons.close_rounded, color: Colors.white54),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline_rounded, color: Color(0xFFD9F99D), size: 18),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Accord Music Vault menyimpan lagu dan chord secara otomatis di Google Drive Anda.',
                                style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'URL Google Apps Script Web App:',
                        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: urlController,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'https://script.google.com/macros/s/.../exec',
                          hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.08),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFD9F99D), width: 1.5),
                          ),
                        ),
                      ),
                      if (localError != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          localError!,
                          style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          if (driveSync.isConfigured)
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () async {
                                  await driveSync.clearConfiguration();
                                  if (bottomSheetContext.mounted) {
                                    Navigator.pop(bottomSheetContext);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Konfigurasi Google Drive dinonaktifkan'),
                                        backgroundColor: Colors.orange,
                                      ),
                                    );
                                  }
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.redAccent,
                                  side: const BorderSide(color: Colors.redAccent),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  padding: const EdgeInsets.symmetric(vertical: 13),
                                ),
                                child: const Text('Putuskan'),
                              ),
                            ),
                          if (driveSync.isConfigured) const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              onPressed: () async {
                                final rawUrl = urlController.text.trim();
                                if (rawUrl.isEmpty) {
                                  setModalState(() => localError = 'URL Web App tidak boleh kosong.');
                                  return;
                                }
                                if (!rawUrl.startsWith('https://script.google.com/')) {
                                  setModalState(() => localError = 'Format URL harus diawali https://script.google.com/...');
                                  return;
                                }

                                setModalState(() => localError = null);
                                await driveSync.setBridgeUrl(rawUrl);

                                if (bottomSheetContext.mounted) {
                                  Navigator.pop(bottomSheetContext);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Row(
                                        children: [
                                          SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                          ),
                                          SizedBox(width: 12),
                                          Expanded(child: Text('Menyinkronkan dengan Google Drive...')),
                                        ],
                                      ),
                                      backgroundColor: Color(0xFF10B981),
                                      duration: Duration(seconds: 3),
                                    ),
                                  );
                                }

                                final ok = await driveSync.syncVault();
                                if (!context.mounted) return;
                                await Future.wait([
                                  context.read<GoogleDriveAudioService>().loadDriveSongs(),
                                  context.read<LibraryProvider>().refreshLocalSongs(),
                                ]);
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(ok
                                        ? 'Google Drive Vault terhubung! (${driveSync.cloudSongCount} lagu, ${driveSync.cloudChordCount} chord)'
                                        : 'Gagal menghubungi Drive: ${driveSync.error}'),
                                    backgroundColor: ok ? const Color(0xFF10B981) : Colors.redAccent,
                                  ),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFD9F99D),
                                foregroundColor: const Color(0xFF09090B),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                elevation: 0,
                              ),
                              child: const Text('Simpan & Sinkronkan', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
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

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final player = context.watch<PlayerProvider>();
    final driveAudio = context.watch<GoogleDriveAudioService>();
    final driveSync = context.watch<GoogleDriveSyncService>();
    final profile = context.watch<ProfileProvider>();

    // Combine local songs and drive songs (local library edits take precedence)
    final allSongsMap = <String, Song>{};
    for (final s in driveAudio.driveSongs) {
      allSongsMap[s.id] = s;
    }
    for (final s in library.allSongs) {
      allSongsMap[s.id] = s;
    }
    final allCombinedSongs = allSongsMap.values.toList();
    final displayedSongs = _getFilteredSongs(allCombinedSongs, _selectedFilterIndex);
    final ambientSong = player.currentSong ?? (allCombinedSongs.isNotEmpty ? allCombinedSongs.first : null);

    return Scaffold(
      backgroundColor: Colors.black,
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
            child: RefreshIndicator(
              color: const Color(0xFFD9F99D),
              backgroundColor: const Color(0xFF16161B),
              onRefresh: () async {
                await Future.wait([
                  driveAudio.loadDriveSongs(),
                  library.refreshLocalSongs(),
                  if (driveSync.isConfigured) driveSync.syncVault(),
                ]);
              },
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  // 1. Top App Header Bar
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      child: Row(
                        children: [
                          // App Title "Accord"
                          const Expanded(
                            child: Text(
                              'Accord',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                                shadows: _textShadows,
                              ),
                            ),
                          ),
                          // Notification / Sync Bell Icon
                          LiquidGlassContainer(
                            borderRadius: 22,
                            blur: 14,
                            width: 44,
                            height: 44,
                            padding: EdgeInsets.zero,
                            onTap: () {
                              if (!driveSync.isConfigured) {
                                _showDriveVaultSetupDialog(context);
                              } else {
                                final driveAudioService = driveAudio;
                                final libraryService = library;
                                driveSync.syncVault().then((ok) {
                                  if (mounted && ok) {
                                    driveAudioService.loadDriveSongs();
                                    libraryService.refreshLocalSongs();
                                  }
                                });
                              }
                            },
                            child: Center(
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Icon(
                                    driveSync.isConfigured ? Icons.cloud_done_rounded : Icons.notifications_none_rounded,
                                    color: driveSync.isConfigured ? const Color(0xFFD9F99D) : Colors.white70,
                                    size: 20,
                                  ),
                                  if (driveSync.isSyncing)
                                    const Positioned.fill(
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFFD9F99D),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Profile Avatar (Tap to open Edit Profile)
                          GestureDetector(
                            onTap: () => _showProfileModal(context),
                            child: profile.buildAvatarWidget(size: 44, showBorder: true),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 2. "History play" Section
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 20, right: 20, top: 14, bottom: 10),
                      child: const Text(
                        'History play',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          shadows: _textShadows,
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _buildHistoryPlaySection(context, player, allCombinedSongs, library),
                  ),

                  // 3. "Playlist" Section
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 20, right: 20, top: 22, bottom: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Playlist',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                              shadows: _textShadows,
                            ),
                          ),
                          GestureDetector(
                            onTap: () => _showCreatePlaylistDialog(context, library),
                            child: LiquidGlassLens(
                              style: LiquidGlassStyle(
                                shape: const LiquidGlassShape.roundedRectangle(cornerRadius: 14),
                                appearance: LiquidGlassAppearance(
                                  blur: const LiquidGlassBlur(sigmaX: 8, sigmaY: 8),
                                  color: Colors.white.withValues(alpha: 0.08),
                                ),
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.add_rounded, color: Color(0xFFD9F99D), size: 16),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Buat Baru',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.80),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _buildPlaylistsSection(context, library, player, allCombinedSongs),
                  ),

                  // 4. "Daftar Lagu" Tracks List Section
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 20, right: 20, top: 24, bottom: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Daftar Lagu',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                              shadows: _textShadows,
                            ),
                          ),
                          Text(
                            '${displayedSongs.length} lagu',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.70),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              shadows: _textShadows,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 4. 3 Filter Category Chips (Semua Lagu, Chord & Lirik, Tanpa Chord & Lirik)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 12),
                      child: SizedBox(
                        height: 38,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _filters.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final isActive = _selectedFilterIndex == index;
                            return GestureDetector(
                              onTap: () {
                                setState(() => _selectedFilterIndex = index);
                              },
                              child: LiquidGlassLens(
                                style: LiquidGlassStyle(
                                  shape: const LiquidGlassShape.roundedRectangle(cornerRadius: 20),
                                  appearance: LiquidGlassAppearance(
                                    blur: const LiquidGlassBlur(sigmaX: 10, sigmaY: 10),
                                    color: isActive
                                        ? const Color(0xFFD9F99D).withValues(alpha: 0.18)
                                        : Colors.white.withValues(alpha: 0.06),
                                  ),
                                ),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: isActive
                                          ? const Color(0xFFD9F99D).withValues(alpha: 0.65)
                                          : Colors.white.withValues(alpha: 0.12),
                                      width: 1.0,
                                    ),
                                    boxShadow: isActive
                                        ? [
                                            BoxShadow(
                                              color: const Color(0xFFD9F99D).withValues(alpha: 0.18),
                                              blurRadius: 10,
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: Center(
                                    child: Text(
                                      _filters[index],
                                      style: TextStyle(
                                        color: isActive ? const Color(0xFFD9F99D) : Colors.white70,
                                        fontSize: 13,
                                        fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                                        shadows: _textShadows,
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

                  // 5. Tracks List (Liquid Glass items)
                  if (displayedSongs.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(
                                Icons.music_off_rounded,
                                size: 48,
                                color: Colors.white.withValues(alpha: 0.25),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _selectedFilterIndex == 1
                                    ? 'Belum ada lagu dengan chord & lirik'
                                    : (_selectedFilterIndex == 2
                                        ? 'Semua lagu sudah memiliki chord & lirik'
                                        : 'Belum ada lagu di perpustakaan'),
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 14,
                                ),
                                textAlign: TextAlign.center,
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

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: LiquidGlassLens(
                                style: LiquidGlassStyle(
                                  shape: const LiquidGlassShape.roundedRectangle(cornerRadius: 18),
                                  appearance: LiquidGlassAppearance(
                                    blur: const LiquidGlassBlur(sigmaX: 10, sigmaY: 10),
                                    color: isCurrentPlaying
                                        ? const Color(0xFFD9F99D).withValues(alpha: 0.14)
                                        : Colors.white.withValues(alpha: 0.06),
                                  ),
                                ),
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: isCurrentPlaying
                                          ? const Color(0xFFD9F99D).withValues(alpha: 0.45)
                                          : Colors.white.withValues(alpha: 0.10),
                                      width: 1.0,
                                    ),
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    borderRadius: BorderRadius.circular(18),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(18),
                                      splashColor: const Color(0xFFD9F99D).withValues(alpha: 0.14),
                                      highlightColor: Colors.white.withValues(alpha: 0.05),
                                      onTap: () {
                                        player.playSong(song);
                                      },
                                      onLongPress: () {
                                        _showSongOptionsMenu(context, song);
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        child: Row(
                                          children: [
                                            // Album Thumbnail
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(12),
                                              child: Container(
                                                width: 48,
                                                height: 48,
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
                                            const SizedBox(width: 12),

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
                                                  const SizedBox(height: 3),
                                                  Text(
                                                    song.displayArtist,
                                                    style: TextStyle(
                                                      color: Colors.white.withValues(alpha: 0.75),
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

                                            // More Options Button (...) -> opens liquid glass modal
                                            GestureDetector(
                                              behavior: HitTestBehavior.opaque,
                                              onTap: () => _showSongOptionsMenu(context, song),
                                              child: const Padding(
                                                padding: EdgeInsets.all(6),
                                                child: Icon(
                                                  Icons.more_horiz_rounded,
                                                  color: Colors.white70,
                                                  size: 22,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),

                                            // Heart / Favorite Icon Button
                                            GestureDetector(
                                              behavior: HitTestBehavior.opaque,
                                              onTap: () => library.toggleFavorite(song.id),
                                              child: Padding(
                                                padding: const EdgeInsets.all(6),
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
          ),
        ],
      ),
    );
  }

  void _showSongOptionsMenu(BuildContext context, Song song) {
    final library = context.read<LibraryProvider>();
    final isFav = library.isFavorite(song.id);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color.fromARGB(0, 77, 76, 76),
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
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 50,
                        height: 50,
                        child: (song.albumArtUrl != null && song.albumArtUrl!.isNotEmpty)
                            ? ((song.albumArtUrl!.startsWith('http://') || song.albumArtUrl!.startsWith('https://'))
                                ? Image.network(
                                    song.albumArtUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => Container(
                                      color: const Color(0xFF27272E),
                                      child: const Icon(Icons.music_note_rounded, color: Colors.white60),
                                    ),
                                  )
                                : Image.file(
                                    File(song.albumArtUrl!),
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => Container(
                                      color: const Color(0xFF27272E),
                                      child: const Icon(Icons.music_note_rounded, color: Colors.white60),
                                    ),
                                  ))
                            : Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: song.gradientColors ?? const [Color(0xFFD9F99D), Color(0xFF65A30D)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                ),
                                child: const Icon(Icons.music_note_rounded, color: Colors.white70),
                              ),
                      ),
                    ),
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

                _buildSongActionTile(
                  icon: Icons.playlist_add_rounded,
                  title: 'Tambahkan ke Playlist',
                  onTap: () {
                    Navigator.pop(modalCtx);
                    _showAddToPlaylistDialog(context, library, song);
                  },
                ),
                _buildSongActionTile(
                  icon: isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  iconColor: isFav ? const Color(0xFFF43F5E) : Colors.white,
                  title: isFav ? 'Hapus dari Disukai' : 'Sukai Lagu (Like)',
                  onTap: () {
                    library.toggleFavorite(song.id);
                    Navigator.pop(modalCtx);
                  },
                ),
                _buildSongActionTile(
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
                _buildSongActionTile(
                  icon: Icons.delete_outline_rounded,
                  iconColor: Colors.redAccent,
                  title: 'Hapus Lagu',
                  onTap: () {
                    Navigator.pop(modalCtx);
                    library.deleteLocalSong(song.id);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSongActionTile({
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

  Widget _buildHistoryPlaySection(
    BuildContext context,
    PlayerProvider player,
    List<Song> allCombinedSongs,
    LibraryProvider library,
  ) {
    // Take from player.playHistory if not empty, otherwise show recently added / all combined songs
    final songs = player.playHistory.isNotEmpty
        ? player.playHistory
        : allCombinedSongs;

    if (songs.isEmpty) {
      return Container(
        height: 100,
        margin: const EdgeInsets.symmetric(horizontal: 20),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Text(
          'Belum ada riwayat putar lagu',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
        ),
      );
    }

    return SizedBox(
      height: 154,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: songs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final song = songs[index];
          final isPlayingCurrent = player.currentSong?.id == song.id && player.isPlaying;
          final primary = AmbianceColorHelper.getPrimaryColor(song);
          final secondary = AmbianceColorHelper.getSecondaryColor(song);
          final hasArt = song.albumArtUrl != null && song.albumArtUrl!.isNotEmpty;

          return GestureDetector(
            onTap: () {
              player.playSong(song, playlist: songs);
            },
            child: Container(
              width: 154,
              height: 154,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: isPlayingCurrent
                      ? const Color(0xFFD9F99D).withValues(alpha: 0.7)
                      : Colors.white.withValues(alpha: 0.12),
                  width: isPlayingCurrent ? 1.6 : 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: primary.withValues(alpha: isPlayingCurrent ? 0.35 : 0.20),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(25),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Background: Cover artwork image if present, or dynamic ambiance gradient
                    if (hasArt) ...[
                      (song.albumArtUrl!.startsWith('http://') || song.albumArtUrl!.startsWith('https://'))
                          ? Image.network(
                              song.albumArtUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => _buildFallbackCardArt(primary, secondary),
                            )
                          : Image.file(
                              File(song.albumArtUrl!),
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => _buildFallbackCardArt(primary, secondary),
                            ),
                      // Soft gradient overlay for subtle blending
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.35),
                            ],
                            stops: const [0.4, 1.0],
                          ),
                        ),
                      ),
                    ] else ...[
                      _buildFallbackCardArt(primary, secondary),
                    ],

                    // Top-right: Equalizer when playing or history icon
                    Positioned(
                      top: 12,
                      right: 12,
                      child: isPlayingCurrent
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.65),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFD9F99D).withValues(alpha: 0.4)),
                              ),
                              child: const AnimatedEqualizer(
                                color: Color(0xFFD9F99D),
                                maxHeight: 12,
                                barWidth: 2.2,
                              ),
                            )
                          : Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black.withValues(alpha: 0.35),
                              ),
                              child: const Icon(
                                Icons.history_rounded,
                                size: 14,
                                color: Colors.white70,
                              ),
                            ),
                    ),

                    // Bottom-left: Translucent Liquid Glass Pill with song title & artist
                    Positioned(
                      bottom: 10,
                      left: 10,
                      right: 10,
                      child: LiquidGlassLens(
                        style: LiquidGlassStyle(
                          shape: const LiquidGlassShape.roundedRectangle(cornerRadius: 16),
                          appearance: LiquidGlassAppearance(
                            blur: const LiquidGlassBlur(sigmaX: 12, sigmaY: 12),
                            color: Colors.black.withValues(alpha: 0.28),
                          ),
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.22),
                              width: 1.0,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                song.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.2,
                                  shadows: [
                                    Shadow(
                                      color: Color(0xD9000000),
                                      blurRadius: 4,
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
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  shadows: const [
                                    Shadow(
                                      color: Color(0xD9000000),
                                      blurRadius: 4,
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
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFallbackCardArt(Color primary, Color secondary) {
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(-0.2, -0.3),
          radius: 1.15,
          colors: [primary, secondary, const Color(0xFF0B0C12)],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          size: 40,
          color: Colors.white.withValues(alpha: 0.22),
        ),
      ),
    );
  }

  Widget _buildPlaylistsSection(
    BuildContext context,
    LibraryProvider library,
    PlayerProvider player,
    List<Song> allCombinedSongs,
  ) {
    final playlists = library.playlists;
    final favoriteSongs = library.favoriteSongs;

    return SizedBox(
      height: 168,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          // 1. Lagu Disukai (Favorites Playlist) with dynamic ambiance following its cover
          Builder(builder: (ctx) {
            final topSong = favoriteSongs.isNotEmpty ? favoriteSongs.first : null;
            return _buildPlaylistCard(
              title: 'Lagu Disukai',
              subtitle: '${favoriteSongs.length} lagu',
              songs: favoriteSongs,
              topSong: topSong,
              fallbackIcon: Icons.favorite_rounded,
              fallbackIconColor: const Color(0xFFF43F5E),
              onPlay: () {
                if (favoriteSongs.isNotEmpty) {
                  player.playSong(favoriteSongs.first, playlist: favoriteSongs);
                }
              },
            );
          }),
          const SizedBox(width: 14),

          // 2. User Playlists with dynamic ambiance following their song covers
          for (final Playlist pl in playlists) ...[
            Builder(builder: (ctx) {
              final plSongs = library.getSongsForPlaylist(pl);
              final topSong = plSongs.isNotEmpty ? plSongs.first : null;
              return _buildPlaylistCard(
                title: pl.name,
                subtitle: '${plSongs.length} lagu',
                songs: plSongs,
                topSong: topSong,
                logoId: pl.logoId,
                onPlay: () {
                  if (plSongs.isNotEmpty) {
                    player.playSong(plSongs.first, playlist: plSongs);
                  }
                },
              );
            }),
            const SizedBox(width: 14),
          ],

          // 3. Quick Create Playlist Card
          GestureDetector(
            onTap: () => _showCreatePlaylistDialog(context, library),
            child: LiquidGlassLens(
              style: LiquidGlassStyle(
                shape: const LiquidGlassShape.roundedRectangle(cornerRadius: 26),
                appearance: LiquidGlassAppearance(
                  blur: const LiquidGlassBlur(sigmaX: 10, sigmaY: 10),
                  color: Colors.white.withValues(alpha: 0.05),
                ),
              ),
              child: Container(
                width: 130,
                height: 168,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                    width: 1.0,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFD9F99D).withValues(alpha: 0.15),
                        border: Border.all(color: const Color(0xFFD9F99D).withValues(alpha: 0.4)),
                      ),
                      child: const Icon(
                        Icons.add_rounded,
                        color: Color(0xFFD9F99D),
                        size: 24,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Buat Playlist',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaylistCard({
    required String title,
    required String subtitle,
    required List<Song> songs,
    required VoidCallback onPlay,
    Song? topSong,
    String? logoId,
    IconData? fallbackIcon,
    Color? fallbackIconColor,
  }) {
    // Dynamic ambiance following artwork colors and patterns of the playlist songs
    final primary = AmbianceColorHelper.getPrimaryColor(topSong);
    final secondary = AmbianceColorHelper.getSecondaryColor(topSong);
    final artUrl = topSong?.albumArtUrl;
    final hasArt = artUrl != null && artUrl.isNotEmpty;

    return Container(
      width: 270,
      height: 168,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.14),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: topSong != null ? 0.25 : 0.10),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(25),
        child: Stack(
          children: [
            // 1. Background: Album artwork pattern from songs in playlist, or dynamic gradient
            Positioned.fill(
              child: hasArt
                  ? ((artUrl.startsWith('http://') || artUrl.startsWith('https://'))
                      ? Image.network(
                          artUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _buildPlaylistGradient(primary, secondary),
                        )
                      : Image.file(
                          File(artUrl),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _buildPlaylistGradient(primary, secondary),
                        ))
                  : _buildPlaylistGradient(primary, secondary),
            ),

            // 2. Translucent ambient gradient overlay so text & controls remain punchy
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      primary.withValues(alpha: hasArt ? 0.70 : 0.85),
                      secondary.withValues(alpha: hasArt ? 0.65 : 0.80),
                      const Color(0xFF090A0F).withValues(alpha: 0.92),
                    ],
                  ),
                ),
              ),
            ),

            // 3. Fluid ambient wave curves matching the artwork's radiant glow
            Positioned.fill(
              child: CustomPaint(
                painter: _MixWavePainter(color: primary.withValues(alpha: 0.22)),
              ),
            ),

            // 4. Content: Logo/Emblem, Title & Subtitle
            Positioned(
              left: 20,
              top: 22,
              right: 76,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Astronomy Emblem / Favorite Heart
                  if (logoId != null) ...[
                    CosmicThemeProvider.buildEmblemForId(logoId, size: 32),
                    const SizedBox(height: 10),
                  ] else if (fallbackIcon != null) ...[
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: (fallbackIconColor ?? const Color(0xFFD9F99D)).withValues(alpha: 0.18),
                      ),
                      child: Icon(fallbackIcon, color: fallbackIconColor ?? const Color(0xFFD9F99D), size: 18),
                    ),
                    const SizedBox(height: 10),
                  ],

                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      height: 1.15,
                      shadows: _textShadows,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      shadows: _textShadows,
                    ),
                  ),
                ],
              ),
            ),

            // 5. Floating circular dark liquid glass Play button
            Positioned(
              right: 18,
              bottom: 18,
              child: GestureDetector(
                onTap: onPlay,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.50),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.30),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistGradient(Color primary, Color secondary) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            primary,
            secondary,
            const Color(0xFF090A0F),
          ],
        ),
      ),
    );
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

class _MixWavePainter extends CustomPainter {
  final Color color;

  const _MixWavePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final path1 = Path();
    path1.moveTo(0, size.height * 0.75);
    path1.quadraticBezierTo(
      size.width * 0.35,
      size.height * 0.30,
      size.width * 0.70,
      size.height * 0.65,
    );
    path1.quadraticBezierTo(
      size.width * 0.85,
      size.height * 0.82,
      size.width,
      size.height * 0.50,
    );
    canvas.drawPath(path1, paint);

    final path2 = Path();
    path2.moveTo(0, size.height * 0.90);
    path2.quadraticBezierTo(
      size.width * 0.45,
      size.height * 0.45,
      size.width * 0.80,
      size.height * 0.80,
    );
    path2.quadraticBezierTo(
      size.width * 0.90,
      size.height * 0.92,
      size.width,
      size.height * 0.70,
    );
    canvas.drawPath(path2, paint..strokeWidth = 1.4);
  }

  @override
  bool shouldRepaint(covariant _MixWavePainter oldDelegate) => oldDelegate.color != color;
}
