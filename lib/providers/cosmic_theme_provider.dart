import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AstronomyLogoOption {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final Color glowColor;

  const AstronomyLogoOption({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.glowColor,
  });
}

class CosmicThemeProvider extends ChangeNotifier {
  static const String _prefKey = 'selected_astronomy_logo_id';

  static const List<AstronomyLogoOption> options = [
    AstronomyLogoOption(
      id: 'saturn_orbit',
      name: 'Saturn Orbit',
      description: 'Cincin planet kosmik futuristik',
      icon: Icons.album_outlined,
      glowColor: Color(0xFFD9F99D),
    ),
    AstronomyLogoOption(
      id: 'cosmic_vortex',
      name: 'Cosmic Vortex',
      description: 'Spiral pusaran galaksi dinamis',
      icon: Icons.all_inclusive_rounded,
      glowColor: Color(0xFF67E8F9),
    ),
    AstronomyLogoOption(
      id: 'solar_corona',
      name: 'Solar Corona',
      description: 'Pijar keemasan korona mentari',
      icon: Icons.wb_sunny_rounded,
      glowColor: Color(0xFFFBBF24),
    ),
    AstronomyLogoOption(
      id: 'lunar_crescent',
      name: 'Lunar Eclipse',
      description: 'Fase bulan sabit & gerhana kosmik',
      icon: Icons.nightlight_round,
      glowColor: Color(0xFFA78BFA),
    ),
    AstronomyLogoOption(
      id: 'supernova_pulsar',
      name: 'Supernova Pulsar',
      description: 'Letupan bintang neutron bercahaya',
      icon: Icons.auto_awesome_rounded,
      glowColor: Color(0xFF34D399),
    ),
    AstronomyLogoOption(
      id: 'deep_space',
      name: 'Deep Space',
      description: 'Lintasan orbit antar-bintang',
      icon: Icons.language_rounded,
      glowColor: Color(0xFF38BDF8),
    ),
  ];

  String _currentLogoId = 'saturn_orbit';

  String get currentLogoId => _currentLogoId;

  AstronomyLogoOption get currentOption {
    return options.firstWhere(
      (opt) => opt.id == _currentLogoId,
      orElse: () => options.first,
    );
  }

  CosmicThemeProvider() {
    _loadFromPrefs();
  }

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      if (saved != null && options.any((opt) => opt.id == saved)) {
        _currentLogoId = saved;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> setLogo(String id) async {
    if (_currentLogoId == id) return;
    _currentLogoId = id;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, id);
    } catch (_) {}
  }

  static AstronomyLogoOption getOptionById(String id) {
    return options.firstWhere(
      (opt) => opt.id == id,
      orElse: () => options.first,
    );
  }

  static Widget buildEmblemForId(String id, {double size = 28}) {
    final opt = getOptionById(id);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: opt.glowColor.withValues(alpha: 0.15),
        border: Border.all(
          color: opt.glowColor.withValues(alpha: 0.5),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: opt.glowColor.withValues(alpha: 0.35),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Center(
        child: opt.id == 'saturn_orbit'
            ? Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: size * 0.44,
                    height: size * 0.44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: opt.glowColor,
                    ),
                  ),
                  Transform.rotate(
                    angle: -math.pi / 5,
                    child: Container(
                      width: size * 0.78,
                      height: size * 0.22,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(size),
                        border: Border.all(
                          color: opt.glowColor,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : Icon(
                opt.icon,
                color: opt.glowColor,
                size: size * 0.58,
              ),
      ),
    );
  }

  Widget buildEmblemWidget({double size = 28, AstronomyLogoOption? option}) {
    final opt = option ?? currentOption;
    return buildEmblemForId(opt.id, size: size);
  }
}
