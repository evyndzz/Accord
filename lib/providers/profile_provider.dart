import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileAvatarOption {
  final String id;
  final String name;
  final IconData icon;
  final List<Color> gradient;

  const ProfileAvatarOption({
    required this.id,
    required this.name,
    required this.icon,
    required this.gradient,
  });
}

class ProfileProvider extends ChangeNotifier {
  static const String _prefNameKey = 'user_profile_name';
  static const String _prefAvatarIdKey = 'user_profile_avatar_id';
  static const String _prefCustomImagePathKey = 'user_profile_custom_path';

  static const List<ProfileAvatarOption> avatarOptions = [
    ProfileAvatarOption(
      id: 'cosmic_astronaut',
      name: 'Astronaut',
      icon: Icons.rocket_launch_rounded,
      gradient: [Color(0xFF6366F1), Color(0xFFA855F7)],
    ),
    ProfileAvatarOption(
      id: 'pixel_planet',
      name: 'Pixel Planet',
      icon: Icons.public_rounded,
      gradient: [Color(0xFF06B6D4), Color(0xFF10B981)],
    ),
    ProfileAvatarOption(
      id: 'vinyl_maestro',
      name: 'Vinyl Maestro',
      icon: Icons.album_rounded,
      gradient: [Color(0xFFF59E0B), Color(0xFFEF4444)],
    ),
    ProfileAvatarOption(
      id: 'cyber_synth',
      name: 'Cyber Synth',
      icon: Icons.graphic_eq_rounded,
      gradient: [Color(0xFFEC4899), Color(0xFF8B5CF6)],
    ),
    ProfileAvatarOption(
      id: 'acoustic_soul',
      name: 'Guitar Soul',
      icon: Icons.music_note_rounded,
      gradient: [Color(0xFF14B8A6), Color(0xFF3B82F6)],
    ),
    ProfileAvatarOption(
      id: 'neon_dj',
      name: 'Cyber Wave',
      icon: Icons.headphones_rounded,
      gradient: [Color(0xFF0284C7), Color(0xFF38BDF8)],
    ),
  ];

  String _name = 'Musician';
  String _avatarId = 'cosmic_astronaut';
  String? _customImagePath;
  bool _isLoaded = false;

  String get name => _name;
  String get avatarId => _avatarId;
  String? get customImagePath => _customImagePath;
  bool get isLoaded => _isLoaded;

  ProfileAvatarOption get currentAvatarOption {
    return avatarOptions.firstWhere(
      (opt) => opt.id == _avatarId,
      orElse: () => avatarOptions.first,
    );
  }

  ProfileProvider() {
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _name = prefs.getString(_prefNameKey) ?? 'Musician';
      _avatarId = prefs.getString(_prefAvatarIdKey) ?? 'cosmic_astronaut';
      _customImagePath = prefs.getString(_prefCustomImagePathKey);
      _isLoaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading profile: $e');
      _isLoaded = true;
      notifyListeners();
    }
  }

  Future<String?> pickAndSaveCustomImage() async {
    try {
      final result = await FilePicker.pickFiles(type: FileType.image);
      if (result.isNotEmpty && result.first.path != null) {
        final originalFile = File(result.first.path!);
        final appDir = await getApplicationDocumentsDirectory();
        final ext = p.extension(result.first.path!).isNotEmpty
            ? p.extension(result.first.path!)
            : '.jpg';
        final targetPath = '${appDir.path}/profile_custom_${DateTime.now().millisecondsSinceEpoch}$ext';
        await originalFile.copy(targetPath);
        return targetPath;
      }
    } catch (e) {
      debugPrint('Error picking profile image: $e');
    }
    return null;
  }

  Future<void> updateProfile({
    required String newName,
    required String newAvatarId,
    String? newCustomImagePath,
  }) async {
    _name = newName.trim().isEmpty ? 'Musician' : newName.trim();
    _avatarId = newAvatarId;
    _customImagePath = newCustomImagePath;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefNameKey, _name);
      await prefs.setString(_prefAvatarIdKey, _avatarId);
      if (_customImagePath != null && _customImagePath!.isNotEmpty) {
        await prefs.setString(_prefCustomImagePathKey, _customImagePath!);
      } else {
        await prefs.remove(_prefCustomImagePathKey);
      }
    } catch (e) {
      debugPrint('Error saving profile: $e');
    }
  }

  Widget buildAvatarWidget({double size = 42, bool showBorder = true}) {
    if (_customImagePath != null &&
        _customImagePath!.isNotEmpty &&
        File(_customImagePath!).existsSync()) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: showBorder
              ? Border.all(
                  color: const Color(0xFFD9F99D),
                  width: 1.5,
                )
              : null,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD9F99D).withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
          image: DecorationImage(
            image: FileImage(File(_customImagePath!)),
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    final opt = currentAvatarOption;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: opt.gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: showBorder
            ? Border.all(
                color: Colors.white.withValues(alpha: 0.35),
                width: 1.5,
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: opt.gradient.first.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(
        opt.icon,
        color: Colors.white,
        size: size * 0.52,
      ),
    );
  }
}
