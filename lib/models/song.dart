import 'package:flutter/material.dart';

import 'song_line.dart';

class Song {
  final String id;
  final String title;
  final String artist;
  final String? albumArtUrl;
  final int durationMs;
  final String? originalKey;
  final List<SongLine> lines;
  final List<Color>? gradientColors;
  final String? filePath;
  final String? streamUrl;
  final String? sourceType;
  final double? bpm;
  final String? timeSignature;
  final int? startBeat;
  final int? startBeatOffsetMs;

  const Song({
    required this.id,
    required this.title,
    required this.artist,
    this.albumArtUrl,
    required this.durationMs,
    this.originalKey,
    required this.lines,
    this.gradientColors,
    this.filePath,
    this.streamUrl,
    this.sourceType,
    this.bpm,
    this.timeSignature,
    this.startBeat,
    this.startBeatOffsetMs,
  });

  bool get isGoogleDrive =>
      sourceType == 'drive' ||
      sourceType == 'google_drive' ||
      id.startsWith('drive_');

  double get effectiveBpm => (bpm != null && bpm! > 0) ? bpm! : 120.0;

  String get effectiveTimeSignature =>
      (timeSignature != null && timeSignature!.isNotEmpty) ? timeSignature! : '4/4';

  int get effectiveStartBeat => (startBeat != null && startBeat! >= 1) ? startBeat! : 1;

  int get effectiveStartBeatOffsetMs =>
      (startBeatOffsetMs != null && startBeatOffsetMs! >= 0) ? startBeatOffsetMs! : 0;

  int get beatsPerBar {
    final parts = effectiveTimeSignature.split('/');
    return int.tryParse(parts.first) ?? 4;
  }

  String get durationFormatted {
    if (durationMs <= 0) return '--:--';
    final m = durationMs ~/ 60000;
    final s = (durationMs % 60000) ~/ 1000;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String get displayArtist {
    final a = artist.trim();
    if (a.isEmpty ||
        a == 'Google Drive' ||
        a == 'Unknown Artist' ||
        a == 'Local Audio') {
      return 'Tidak Diketahui';
    }
    return a;
  }

  Song copyWith({
    String? id,
    String? title,
    String? artist,
    String? albumArtUrl,
    int? durationMs,
    String? originalKey,
    List<SongLine>? lines,
    List<Color>? gradientColors,
    String? filePath,
    String? streamUrl,
    String? sourceType,
    double? bpm,
    String? timeSignature,
    int? startBeat,
    int? startBeatOffsetMs,
  }) {
    return Song(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      albumArtUrl: albumArtUrl ?? this.albumArtUrl,
      durationMs: durationMs ?? this.durationMs,
      originalKey: originalKey ?? this.originalKey,
      lines: lines ?? this.lines,
      gradientColors: gradientColors ?? this.gradientColors,
      filePath: filePath ?? this.filePath,
      streamUrl: streamUrl ?? this.streamUrl,
      sourceType: sourceType ?? this.sourceType,
      bpm: bpm ?? this.bpm,
      timeSignature: timeSignature ?? this.timeSignature,
      startBeat: startBeat ?? this.startBeat,
      startBeatOffsetMs: startBeatOffsetMs ?? this.startBeatOffsetMs,
    );
  }
}
