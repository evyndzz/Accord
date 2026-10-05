import 'package:flutter/material.dart';

class Playlist {
  final String id;
  final String name;
  final List<String> songIds;
  final DateTime createdAt;
  final List<Color>? gradientColors;
  final String logoId;

  const Playlist({
    required this.id,
    required this.name,
    this.songIds = const [],
    required this.createdAt,
    this.gradientColors,
    this.logoId = 'saturn_orbit',
  });

  Playlist copyWith({
    String? id,
    String? name,
    List<String>? songIds,
    DateTime? createdAt,
    List<Color>? gradientColors,
    String? logoId,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      songIds: songIds ?? this.songIds,
      createdAt: createdAt ?? this.createdAt,
      gradientColors: gradientColors ?? this.gradientColors,
      logoId: logoId ?? this.logoId,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'song_ids': songIds.join(','),
      'created_at': createdAt.millisecondsSinceEpoch,
      'logo_id': logoId,
    };
  }

  factory Playlist.fromMap(Map<String, dynamic> map) {
    final rawSongIds = map['song_ids'] as String? ?? '';
    final songIds = rawSongIds.isEmpty
        ? <String>[]
        : rawSongIds.split(',').where((s) => s.trim().isNotEmpty).toList();

    return Playlist(
      id: map['id'] as String,
      name: map['name'] as String,
      songIds: songIds,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int? ?? 0),
      gradientColors: const [Color(0xFF0284C7), Color(0xFF2563EB)],
      logoId: (map['logo_id'] as String?)?.isNotEmpty == true ? map['logo_id'] as String : 'saturn_orbit',
    );
  }
}
