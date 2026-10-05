import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';

import '../providers/player_provider.dart';
import '../services/accidental_preference.dart';
import '../services/google_drive_sync_service.dart';
import '../utils/ambiance_color_helper.dart';
import '../widgets/apple_music_aura_background.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const List<Shadow> _textShadows = [
    Shadow(color: Color(0xD9000000), blurRadius: 6, offset: Offset(0, 1)),
  ];

  @override
  Widget build(BuildContext context) {
    final driveSync = context.watch<GoogleDriveSyncService>();
    final accidentalPref = AccidentalPreferenceService.of(context);
    PlayerProvider? player;
    try {
      player = context.watch<PlayerProvider>();
    } catch (_) {
      player = null;
    }
    final currentSong = player?.currentSong;

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
                final primary = AmbianceColorHelper.getPrimaryColor(currentSong);
                final secondary = AmbianceColorHelper.getSecondaryColor(currentSong);
                return AppleMusicAuraBackground(
                  primaryColor: primary,
                  secondaryColor: secondary,
                  isPlaying: player?.isPlaying ?? false,
                  vignetteOpacity: 0.20,
                );
              },
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                // App Bar / Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    children: [
                      if (Navigator.canPop(context)) ...[
                        InkWell(
                          onTap: () => Navigator.pop(context),
                          borderRadius: BorderRadius.circular(20),
                          child: LiquidGlassLens(
                            style: const LiquidGlassStyle(
                              shape: LiquidGlassShape.roundedRectangle(cornerRadius: 20),
                              appearance: LiquidGlassAppearance(
                                blur: LiquidGlassBlur(sigmaX: 10, sigmaY: 10),
                                color: Color(0x33FFFFFF),
                              ),
                            ),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
                              ),
                              child: const Center(
                                child: Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                      ],
                      const Expanded(
                        child: Text(
                          'Pengaturan',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                            shadows: _textShadows,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                  children: [
                    // ── 1. Cloud Sync Section ──
                    _buildSectionHeader('Cloud Sync'),
                    _buildGlassCard(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        leading: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF38BDF8).withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.35)),
                          ),
                          child: const Icon(Icons.cloud_sync_rounded, color: Color(0xFF38BDF8), size: 24),
                        ),
                        title: const Text(
                          'Google Drive Vault',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            driveSync.isConfigured
                                ? 'Terhubung (${driveSync.cloudSongCount} lagu, ${driveSync.cloudChordCount} chord)\nAuto-Sync Real-time Aktif'
                                : 'Belum dihubungkan ke Google Drive',
                            style: const TextStyle(color: Colors.white60, fontSize: 12, height: 1.3),
                          ),
                        ),
                        trailing: driveSync.isSyncing
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.2, color: Color(0xFFD9F99D)),
                              )
                            : IconButton(
                                icon: const Icon(Icons.sync_rounded, color: Color(0xFFD9F99D)),
                                tooltip: 'Sync Sekarang',
                                onPressed: driveSync.isConfigured ? () => driveSync.syncVault() : null,
                              ),
                      ),
                    ),
                    const SizedBox(height: 22),

                    // ── 2. Pemutaran & Tuts ──
                    _buildSectionHeader('Pemutaran & Tampilan'),
                    _buildGlassCard(
                      child: Column(
                        children: [
                          SwitchListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                            title: const Text('Auto-scroll Lirik & Chord', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                            subtitle: const Text('Otomatis menggulir ke chord dan lirik yang sedang aktif', style: TextStyle(color: Colors.white54, fontSize: 12)),
                            value: true,
                            onChanged: (v) {},
                            activeThumbColor: const Color(0xFFD9F99D),
                            activeTrackColor: const Color(0xFFD9F99D).withValues(alpha: 0.35),
                          ),
                          Divider(color: Colors.white.withValues(alpha: 0.07), height: 1),
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                            title: const Text('Diagram Instrumen Default', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                            subtitle: const Text('Piano 11 Tuts (Dot Hitam/Putih)', style: TextStyle(color: Color(0xFFD9F99D), fontSize: 12, fontWeight: FontWeight.bold)),
                            trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white54),
                            onTap: () {},
                          ),
                          Divider(color: Colors.white.withValues(alpha: 0.07), height: 1),
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                            title: const Text('Notasi Tanda Nada', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                            subtitle: Text(
                              accidentalPref.isFlat
                                  ? 'Mol / Flat (♭)  [Db, Eb, Gb, Ab, Bb]'
                                  : 'Kres / Sharp (♯)  [C#, D#, F#, G#, A#]',
                              style: const TextStyle(color: Color(0xFFD9F99D), fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white54),
                            onTap: () => _showAccidentalDialog(context, accidentalPref),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),

                    // ── 4. Tentang Accord ──
                    _buildSectionHeader('Tentang Accord'),
                    _buildGlassCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.asset(
                                      'assets/logo.jpeg',
                                      width: 38,
                                      height: 38,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: const [
                                      Text('Accord Music & Chord', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                                      Text('Harmoni Musik Kosmik', style: TextStyle(color: Colors.white54, fontSize: 12)),
                                    ],
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFD9F99D),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'v2.0.0',
                                  style: TextStyle(
                                    color: Color(0xFF09090B),
                                    fontWeight: FontWeight.w900,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'Platform: Multi-App (${!kIsWeb && Platform.isAndroid ? "Android (ARM64)" : "Laptop/Desktop"})\nAudio Engine: Local High-Fidelity & Drive Stream\nChord Engine: Chordify Matrix + Interactive Piano Voicing',
                              style: const TextStyle(color: Colors.white54, fontSize: 11.5, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFFD9F99D),
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          shadows: _textShadows,
        ),
      ),
    );
  }

  Widget _buildGlassCard({required Widget child, EdgeInsetsGeometry? padding}) {
    return LiquidGlassLens(
      style: const LiquidGlassStyle(
        shape: LiquidGlassShape.roundedRectangle(cornerRadius: 18),
        appearance: LiquidGlassAppearance(
          blur: LiquidGlassBlur(sigmaX: 14, sigmaY: 14),
          color: Color(0x3B0B0C12),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 1.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.30),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          child: padding != null ? Padding(padding: padding, child: child) : child,
        ),
      ),
    );
  }

  void _showAccidentalDialog(BuildContext context, AccidentalPreferenceService service) {
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: LiquidGlassLens(
            style: const LiquidGlassStyle(
              shape: LiquidGlassShape.roundedRectangle(cornerRadius: 24),
              appearance: LiquidGlassAppearance(
                blur: LiquidGlassBlur(sigmaX: 18, sigmaY: 18),
                color: Color(0x520F101A),
              ),
            ),
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF38BDF8).withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.music_note_rounded, color: Color(0xFF38BDF8), size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Notasi Tanda Nada',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          shadows: _textShadows,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Pilih format default untuk menampilkan nada berkoma/setengah nada di seluruh chord:',
                    style: TextStyle(color: Colors.white70, fontSize: 13, shadows: _textShadows),
                  ),
                  const SizedBox(height: 16),
                  // Option Kres (#)
                  InkWell(
                    onTap: () {
                      service.setNotation(AccidentalNotation.sharp);
                      Navigator.pop(ctx);
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: service.isSharp ? const Color(0x33D9F99D) : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: service.isSharp ? const Color(0xFFD9F99D) : Colors.white.withValues(alpha: 0.12),
                          width: service.isSharp ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            service.isSharp ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                            color: service.isSharp ? const Color(0xFFD9F99D) : Colors.white38,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Kres / Sharp (♯)',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    shadows: _textShadows,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'C#, D#, F#, G#, A#',
                                  style: TextStyle(color: Colors.white70, fontSize: 12, shadows: _textShadows),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Option Mol (b)
                  InkWell(
                    onTap: () {
                      service.setNotation(AccidentalNotation.flat);
                      Navigator.pop(ctx);
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: service.isFlat ? const Color(0x33D9F99D) : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: service.isFlat ? const Color(0xFFD9F99D) : Colors.white.withValues(alpha: 0.12),
                          width: service.isFlat ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            service.isFlat ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                            color: service.isFlat ? const Color(0xFFD9F99D) : Colors.white38,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Mol / Flat (♭)',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    shadows: _textShadows,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Db, Eb, Gb, Ab, Bb',
                                  style: TextStyle(color: Colors.white70, fontSize: 12, shadows: _textShadows),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Tutup', style: TextStyle(color: Colors.white70, shadows: _textShadows)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
